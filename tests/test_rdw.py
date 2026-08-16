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


def fake_server(rows: list[tuple[str, ...]], page_size: int, duplicate_keys: bool, width: int = 1):
    """Return a _fetch_page stand-in serving ``rows`` with the real keyset semantics.

    Rows are tuples whose first ``width`` fields are the ordering key; the server
    compares them lexicographically, exactly as SoQL does for the expanded clause.
    """

    def _fetch(client, dataset, cursor, app_token):
        if cursor is None:
            selected = rows
        elif duplicate_keys:
            selected = [r for r in rows if list(r[:width]) >= cursor]
        else:
            selected = [r for r in rows if list(r[:width]) > cursor]
        page = selected[:page_size]
        body = "\n".join(",".join(r) for r in page)
        return "k0,value\n" + body + ("\n" if body else "")

    return _fetch


def run_download(
    monkeypatch, dataset_cls, tmp_path, rows, *, duplicate_keys, page_size, order_by=("kenteken",)
):
    width = len(order_by)
    dataset = dataset_cls(
        key="t",
        resource_id="xxxx-yyyy",
        title="test",
        columns=(*order_by, "value"),
        order_by=order_by,
        duplicate_keys=duplicate_keys,
    )
    monkeypatch.setattr(rdw, "PAGE_SIZE", page_size)
    monkeypatch.setattr(rdw, "_fetch_page", fake_server(rows, page_size, duplicate_keys, width))
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
    assert written[0] == "k0,value"
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


def test_widened_ordering_key_restarts_the_download(monkeypatch, rows_dataset, tmp_path):
    """Rows already on disk are in the old order, so resuming would interleave them."""
    dataset = rows_dataset(
        key="t", resource_id="x-y", title="test", columns=("k0", "k1", "value"),
        order_by=("k0", "k1"),
    )
    dataset.raw_path.write_text("k0,k1,value\nA,1,x\n")
    rdw.DownloadState(cursor=["A"], rows=1, pages=1).save(dataset.state_path)

    rows = [(f"K{i}", f"{j}", "v") for i in range(4) for j in range(2)]
    monkeypatch.setattr(rdw, "PAGE_SIZE", 100)
    monkeypatch.setattr(rdw, "_fetch_page", fake_server(rows, 100, False, width=2))

    state = rdw.download(dataset)
    assert state.complete
    assert state.rows == len(rows)  # the stale row is gone, not counted or kept
    assert dataset.raw_path.read_text().splitlines()[1:] == [",".join(r) for r in rows]


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


def test_composite_key_roundtrip(monkeypatch, rows_dataset, tmp_path):
    """A three-column key paginates losslessly where a one-column key cannot.

    The type-approval tables run to 69k rows under a single approval number, more
    than fits in a page, so the key is the triple that identifies a version. Here
    the first field repeats 30 times, well past the page size, which is exactly the
    case that breaks single-column keyset pagination.
    """
    rows = [
        (f"TGK{a}", f"VAR{b:02d}", f"UIT{c:02d}", f"{a}-{b}-{c}")
        for a in range(3)
        for b in range(10)
        for c in range(3)
    ]
    state, written = run_download(
        monkeypatch,
        rows_dataset,
        tmp_path,
        rows,
        duplicate_keys=True,
        page_size=7,
        order_by=("k0", "k1", "k2"),
    )

    assert state.complete
    assert state.rows == len(rows)
    assert sorted(written[1:]) == sorted(",".join(r) for r in rows)


def test_keyset_clause_expands_lexicographic_comparison():
    clause = rdw._keyset_clause(("a", "b", "c"), ["1", "2", "3"], inclusive=False)
    assert clause == "(a > '1') OR (a = '1' AND b > '2') OR (a = '1' AND b = '2' AND c > '3')"

    # Only the final comparison loosens, or the re-request would return the whole
    # tail of the preceding key groups rather than just the dropped one.
    inclusive = rdw._keyset_clause(("a", "b"), ["1", "2"], inclusive=True)
    assert inclusive == "(a > '1') OR (a = '1' AND b >= '2')"

    assert rdw._keyset_clause(("a",), ["o'brien"], inclusive=False) == "(a > 'o''brien')"


def test_state_roundtrip(tmp_path):
    path = tmp_path / "s.json"
    rdw.DownloadState(cursor=["AB12"], rows=7, pages=1, complete=False).save(path)
    assert json.loads(path.read_text())["cursor"] == ["AB12"]
    assert rdw.DownloadState.load(path).rows == 7
    assert rdw.DownloadState.load(tmp_path / "missing.json").cursor is None

    # A state file written before keys could be composite still resumes.
    legacy = tmp_path / "legacy.json"
    legacy.write_text(json.dumps({"cursor": "AB12", "rows": 7, "pages": 1, "complete": False}))
    assert rdw.DownloadState.load(legacy).cursor == ["AB12"]


@pytest.mark.parametrize(
    ("row", "width", "expected"),
    [
        ("AB12XY,Benzine", 1, ["AB12XY"]),
        ('"AB12XY",Benzine', 1, ["AB12XY"]),
        ("X,", 1, ["X"]),
        ("e1*2007/46*0627*09,SACCYVBX0,FD7FD7CW001N7MMOVL01VR2,0", 3,
         ["e1*2007/46*0627*09", "SACCYVBX0", "FD7FD7CW001N7MMOVL01VR2"]),
        # A version code containing a comma: split(',') would shift the key here.
        ('TGK1,"VAR,A",UIT1,x', 3, ["TGK1", "VAR,A", "UIT1"]),
    ],
)
def test_key_of(row, width, expected):
    assert rdw._key_of(row, width) == expected


def test_order_by_must_lead_the_projection():
    with pytest.raises(ValueError, match="must be the leading columns"):
        Dataset(
            key="t",
            resource_id="x-y",
            title="test",
            columns=("value", "kenteken"),
            order_by=("kenteken",),
        )
