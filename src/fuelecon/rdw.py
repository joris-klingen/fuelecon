"""Download RDW Socrata datasets to local CSV using resumable keyset pagination."""

from __future__ import annotations

import csv
import json
import logging
import time
from dataclasses import dataclass
from pathlib import Path

import httpx

from .config import PAGE_SIZE, Dataset

log = logging.getLogger(__name__)

REQUEST_TIMEOUT = httpx.Timeout(300.0, connect=30.0)
MAX_ATTEMPTS = 5


@dataclass
class DownloadState:
    """Resume point for a dataset download, persisted after every page."""

    cursor: list[str] | None = None
    rows: int = 0
    pages: int = 0
    complete: bool = False

    @classmethod
    def load(cls, path: Path) -> DownloadState:
        if not path.exists():
            return cls()
        state = cls(**json.loads(path.read_text()))
        if isinstance(state.cursor, str):  # written before keys could be composite
            state.cursor = [state.cursor]
        return state

    def save(self, path: Path) -> None:
        path.write_text(json.dumps(self.__dict__, indent=2))


def _quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _keyset_clause(columns: tuple[str, ...], cursor: list[str], inclusive: bool) -> str:
    """SoQL for ``(c1, ..., cn) > cursor``, expanded term by term.

    SoQL has no row-value comparison, so the lexicographic test is written out:
    ``c1 > v1 OR (c1 = v1 AND c2 > v2) OR ...``. ``inclusive`` makes the final
    comparison ``>=``, which is how a dropped boundary group gets re-requested.
    """
    terms = []
    for i, column in enumerate(columns):
        equalities = [
            f"{c} = {_quote(v)}" for c, v in zip(columns[:i], cursor[:i], strict=True)
        ]
        op = ">=" if inclusive and i == len(columns) - 1 else ">"
        terms.append(" AND ".join([*equalities, f"{column} {op} {_quote(cursor[i])}"]))
    return " OR ".join(f"({t})" for t in terms)


def _fetch_page(
    client: httpx.Client, dataset: Dataset, cursor: list[str] | None, app_token: str | None
) -> str:
    clauses = [dataset.where] if dataset.where else []
    if cursor is not None:
        # ``>=`` for duplicate keys: the boundary group was dropped from the last
        # page, so re-requesting it is what makes the download lossless.
        clauses.append(_keyset_clause(dataset.order_by, cursor, dataset.duplicate_keys))

    params = {
        "$select": ",".join(dataset.columns),
        "$order": ",".join(dataset.order_by),
        "$limit": str(PAGE_SIZE),
    }
    if clauses:
        params["$where"] = " AND ".join(f"({c})" for c in clauses)
    headers = {"X-App-Token": app_token} if app_token else {}

    last_error: Exception | None = None
    for attempt in range(MAX_ATTEMPTS):
        try:
            response = client.get(dataset.csv_url, params=params, headers=headers)
            response.raise_for_status()
            return response.text
        except (httpx.HTTPError, httpx.StreamError) as exc:  # noqa: PERF203
            last_error = exc
            backoff = 2**attempt
            log.warning(
                "%s: request failed (%s), retrying in %ss [%d/%d]",
                dataset.key,
                exc,
                backoff,
                attempt + 1,
                MAX_ATTEMPTS,
            )
            time.sleep(backoff)
    raise RuntimeError(f"{dataset.key}: giving up after {MAX_ATTEMPTS} attempts") from last_error


def _split_page(text: str) -> tuple[str, list[str]]:
    lines = text.splitlines()
    if not lines:
        return "", []
    return lines[0], [line for line in lines[1:] if line]


def _key_of(row: str, width: int = 1) -> list[str]:
    """The leading ``width`` CSV fields of a row, which are the ordering key.

    Parsed with the csv module rather than split(','): type-approval version codes
    are free-form manufacturer strings, and one containing a comma would otherwise
    shift the key and silently corrupt the cursor.
    """
    return next(csv.reader([row]))[:width]


def download(
    dataset: Dataset,
    *,
    max_pages: int | None = None,
    force: bool = False,
    app_token: str | None = None,
) -> DownloadState:
    """Fetch ``dataset`` into its raw CSV path, resuming a partial download.

    Returns the final state. ``max_pages`` caps the number of requests, which is how
    the smoke test pulls a usable slice without waiting for all 9.5M rows.
    """
    dataset.raw_path.parent.mkdir(parents=True, exist_ok=True)

    if force:
        dataset.raw_path.unlink(missing_ok=True)
        dataset.state_path.unlink(missing_ok=True)

    state = DownloadState.load(dataset.state_path)
    if state.complete:
        log.info("%s: already complete (%d rows), skipping", dataset.key, state.rows)
        return state
    if state.cursor and not dataset.raw_path.exists():
        log.warning("%s: state file without CSV, restarting from scratch", dataset.key)
        state = DownloadState()
    if state.cursor and len(state.cursor) != len(dataset.order_by):
        # The ordering key changed since the download paused, so the rows already on
        # disk are in an order the new cursor cannot resume from.
        log.warning("%s: ordering key changed, restarting from scratch", dataset.key)
        dataset.raw_path.unlink(missing_ok=True)
        state = DownloadState()

    started = time.monotonic()
    pages_this_run = 0

    with httpx.Client(timeout=REQUEST_TIMEOUT, follow_redirects=True) as client:
        while max_pages is None or pages_this_run < max_pages:
            text = _fetch_page(client, dataset, state.cursor, app_token)
            header, rows = _split_page(text)
            if not rows:
                state.complete = True
                break

            # A short page is the last one: there is nothing after it, so the
            # trailing key group is complete and must be kept rather than dropped.
            final_page = len(rows) < PAGE_SIZE

            width = len(dataset.order_by)
            last_key = _key_of(rows[-1], width)
            if dataset.duplicate_keys and not final_page:
                # Drop the trailing key group; the next page starts at it again.
                # Rows arrive ordered, so the group is the contiguous run at the end.
                cut = len(rows)
                while cut and _key_of(rows[cut - 1], width) == last_key:
                    cut -= 1
                if not cut:
                    raise RuntimeError(
                        f"{dataset.key}: key {last_key!r} fills a whole page; raise PAGE_SIZE"
                    )
                keep = rows[:cut]
                next_cursor = last_key
            else:
                keep = rows
                next_cursor = last_key

            first_write = not dataset.raw_path.exists() or dataset.raw_path.stat().st_size == 0
            with dataset.raw_path.open("a", encoding="utf-8") as fh:
                if first_write:
                    fh.write(header + "\n")
                fh.write("\n".join(keep) + "\n")

            state.cursor = next_cursor
            state.rows += len(keep)
            state.pages += 1
            pages_this_run += 1
            state.save(dataset.state_path)

            if final_page:
                state.complete = True
                break

            if state.pages % 10 == 0:
                rate = state.rows / max(time.monotonic() - started, 1e-9)
                log.info(
                    "%s: %d rows in %d pages (%.0f rows/s)",
                    dataset.key,
                    state.rows,
                    state.pages,
                    rate,
                )

    state.save(dataset.state_path)
    log.info(
        "%s: %s at %d rows in %d pages (%.1fs)",
        dataset.key,
        "complete" if state.complete else "paused",
        state.rows,
        state.pages,
        time.monotonic() - started,
    )
    return state
