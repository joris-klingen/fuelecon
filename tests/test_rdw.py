"""Tests for the keyset pagination, which is where the download can silently lose rows."""

from __future__ import annotations

import json

import pytest

from fuelecon import rdw
from fuelecon.config import Dataset


@pytest.fixture
def rows_dataset(tmp_path, monkeypatch):
    """A Dataset whose raw/state paths live under tmp_path."""

    class TmpDataset(Dataset):
        @property
        def raw_path(self):
            return tmp_path / f"{self.key}.csv"

        @property
        def state_path(self):
            return tmp_path / f"{self.key}.state.json"

    return TmpDataset


def fake_server(rows: list[tuple[str, str]], page_size: int, duplicate_keys: bool):
    """Return a _fetch_page stand-in serving ``rows`` with the real keyset semantics."""

    def _fetch(client, dataset, cursor, app_token):
        if cursor is None:
            selected = rows
        elif duplicate_keys:
            selected = [r for r in rows if r[0] >= cursor]
        else:
            selected = [r for r in rows if r[0] > cursor]
        page = selected[:page_size]
        body = "\n".join(f"{k},{v}" for k, v in page)
        return "kenteken,value\n" + body + ("\n" if body else "")

    return _fetch


def run_download(monkeypatch, dataset_cls, tmp_path, rows, *, duplicate_keys, page_size):
    dataset = dataset_cls(
        key="t",
        resource_id="xxxx-yyyy",
        title="test",
        columns=("kenteken", "value"),
        duplicate_keys=duplicate_keys,
    )
    monkeypatch.setattr(rdw, "PAGE_SIZE", page_size)
    monkeypatch.setattr(rdw, "_fetch_page", fake_server(rows, page_size, duplicate_keys))
    state = rdw.download(dataset)
    written = dataset.raw_path.read_text().splitlines()
    return state, written


def test_unique_keys_roundtrip(monkeypatch, rows_dataset, tmp_path):
    rows = [(f"K{i:04d}", str(i)) for i in range(250)]
    state, written = run_download(
        monkeypatch, rows_dataset, tmp_path, rows, duplicate_keys=False, page_size=100
    )

    assert state.complete
    assert state.rows == 250
    assert written[0] == "kenteken,value"
    assert len(written) == 251  # header + every row, exactly once
    assert [line.split(",")[0] for line in written[1:]] == [k for k, _ in rows]


def test_duplicate_keys_keeps_every_row_including_the_last_group(
    monkeypatch, rows_dataset, tmp_path
):
    """The final partial page must keep its trailing key group.

    Dropping it is correct mid-download (the group is re-requested next page) but
    loses rows at the end, where there is no next page. That bug cost one row of
    the real 16.9M-row fuel table.
    """
    # Three rows per key so page boundaries land inside a group.
    rows = [(f"K{i:03d}", str(j)) for i in range(40) for j in range(3)]
    state, written = run_download(
        monkeypatch, rows_dataset, tmp_path, rows, duplicate_keys=True, page_size=25
    )

    assert state.complete
    assert state.rows == len(rows)
    assert len(written) == len(rows) + 1
    # No row lost and none duplicated by the >= re-request.
    assert sorted(written[1:]) == sorted(f"{k},{v}" for k, v in rows)


def test_download_resumes_from_state(monkeypatch, rows_dataset, tmp_path):
    rows = [(f"K{i:04d}", str(i)) for i in range(250)]
    dataset = rows_dataset(
        key="t", resource_id="x-y", title="test", columns=("kenteken", "value")
    )
    monkeypatch.setattr(rdw, "PAGE_SIZE", 100)
    monkeypatch.setattr(rdw, "_fetch_page", fake_server(rows, 100, False))

    first = rdw.download(dataset, max_pages=1)
    assert not first.complete
    assert first.rows == 100

    second = rdw.download(dataset)
    assert second.complete
    assert second.rows == 250
    assert len(dataset.raw_path.read_text().splitlines()) == 251


def test_complete_download_is_not_refetched(monkeypatch, rows_dataset, tmp_path):
    rows = [(f"K{i:04d}", str(i)) for i in range(10)]
    dataset = rows_dataset(
        key="t", resource_id="x-y", title="test", columns=("kenteken", "value")
    )
    monkeypatch.setattr(rdw, "PAGE_SIZE", 100)
    monkeypatch.setattr(rdw, "_fetch_page", fake_server(rows, 100, False))
    rdw.download(dataset)

    def explode(*args, **kwargs):
        raise AssertionError("should not re-fetch a completed download")

    monkeypatch.setattr(rdw, "_fetch_page", explode)
    state = rdw.download(dataset)
    assert state.complete and state.rows == 10


def test_state_roundtrip(tmp_path):
    path = tmp_path / "s.json"
    rdw.DownloadState(cursor="AB12", rows=7, pages=1, complete=False).save(path)
    assert json.loads(path.read_text())["cursor"] == "AB12"
    assert rdw.DownloadState.load(path).rows == 7
    assert rdw.DownloadState.load(tmp_path / "missing.json").cursor is None


@pytest.mark.parametrize(
    ("row", "expected"),
    [("AB12XY,Benzine", "AB12XY"), ('"AB12XY",Benzine', "AB12XY"), ("X,", "X")],
)
def test_key_of(row, expected):
    assert rdw._key_of(row) == expected
