"""Turn downloaded RDW CSV into columnar Parquet the warehouse can query."""

from __future__ import annotations

import logging

import duckdb

from .config import PATHS, Dataset
from .rdw import download

log = logging.getLogger(__name__)


def sql_literal(path) -> str:
    """Quote a path as a SQL string literal."""
    return "'" + str(path).replace("'", "''") + "'"


def to_parquet(dataset: Dataset) -> int:
    """Rewrite the raw CSV as Parquet. Returns the row count.

    Everything is read as VARCHAR: RDW ships numbers with mixed decimal handling and
    empty strings for missing values, and silent type coercion here would quietly
    drop rows. Casting happens once, explicitly, in ``sql/010_vehicles.sql``.
    """
    if not dataset.raw_path.exists():
        raise FileNotFoundError(f"{dataset.raw_path} not found; run `fuelecon ingest` first")

    PATHS.parquet.mkdir(parents=True, exist_ok=True)
    # Paths are inlined rather than bound: DuckDB assigns positional parameters in
    # a COPY ... TO statement to the copy target first, which silently swaps the
    # source and destination here.
    src = sql_literal(dataset.raw_path)
    dst = sql_literal(dataset.parquet_path)
    con = duckdb.connect()
    try:
        con.execute(
            f"""
            COPY (
                SELECT * FROM read_csv({src}, header = true, all_varchar = true,
                                       quote = '"', escape = '"')
            ) TO {dst} (FORMAT parquet, COMPRESSION zstd)
            """
        )
        (rows,) = con.execute(f"SELECT count(*) FROM read_parquet({dst})").fetchone()
    finally:
        con.close()

    size_mb = dataset.parquet_path.stat().st_size / 1e6
    log.info("%s: %d rows -> %s (%.0f MB)", dataset.key, rows, dataset.parquet_path.name, size_mb)
    return rows


def ingest(
    dataset: Dataset,
    *,
    max_pages: int | None = None,
    force: bool = False,
    app_token: str | None = None,
) -> int:
    """Download ``dataset`` if needed, then materialise it as Parquet."""
    log.info("%s: %s", dataset.key, dataset.title)
    download(dataset, max_pages=max_pages, force=force, app_token=app_token)
    return to_parquet(dataset)
