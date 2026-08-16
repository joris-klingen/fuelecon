"""DuckDB warehouse: run the numbered SQL steps against the ingested Parquet."""

from __future__ import annotations

import logging
import re
from pathlib import Path

import duckdb

from .config import DATASETS, PATHS
from .ingest import sql_literal

log = logging.getLogger(__name__)

# Tables held back from the CSV export: either intermediates that exist to serve
# the result tables, or per-vehicle and per-version tables running to millions of
# rows, which are meant to be queried in the warehouse rather than shipped as CSV.
STAGING_TABLES = frozenset({
    "vehicles",
    "model_lookup",
    "variant_energy",
    "variant_basis",
    "variant_drivetrain",
    "variant_gearbox",
    "variants",
    "vehicle_variant",
    "vehicle_variant_energy",
    "vehicle_fuel",
    "vehicle_energy",
})


def connect(read_only: bool = False) -> duckdb.DuckDBPyConnection:
    PATHS.data.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(PATHS.warehouse), read_only=read_only)
    con.execute("SET preserve_insertion_order = false")
    return con


def register_sources(con: duckdb.DuckDBPyConnection) -> None:
    """Expose each ingested Parquet file as a view named ``raw_<key>``."""
    for key, dataset in DATASETS.items():
        if not dataset.parquet_path.exists():
            raise FileNotFoundError(
                f"{dataset.parquet_path} missing; run `fuelecon ingest {key}` first"
            )
        con.execute(
            f"CREATE OR REPLACE VIEW raw_{key} AS "
            f"SELECT * FROM read_parquet({sql_literal(dataset.parquet_path)})"
        )


def sql_steps(pattern: str = "[0-9]*.sql") -> list[Path]:
    return sorted(PATHS.sql.glob(pattern))


def _statements(script: str) -> list[str]:
    """Split a script on semicolons at end of line, ignoring comment-only chunks."""
    parts = re.split(r";\s*(?:\n|$)", script)
    return [p.strip() for p in parts if p.strip() and not _is_comment_only(p)]


def _is_comment_only(chunk: str) -> bool:
    return all(not line.strip() or line.strip().startswith("--") for line in chunk.splitlines())


def run_script(con: duckdb.DuckDBPyConnection, path: Path) -> None:
    log.info("running %s", path.name)
    for statement in _statements(path.read_text()):
        con.execute(statement)


def build() -> dict[str, int]:
    """Run every SQL step in order and report the row count of each table created."""
    con = connect()
    try:
        register_sources(con)
        for path in sql_steps():
            run_script(con, path)
        tables = [r[0] for r in con.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'main' AND table_type = 'BASE TABLE' ORDER BY table_name"
        ).fetchall()]
        return {t: con.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0] for t in tables}
    finally:
        con.close()


def export_outputs() -> list[Path]:
    """Write every non-staging table to output/ as CSV for downstream use."""
    PATHS.output.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    con = connect(read_only=True)
    try:
        tables = [r[0] for r in con.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'main' AND table_type = 'BASE TABLE' ORDER BY table_name"
        ).fetchall()]
        for table in tables:
            if table in STAGING_TABLES:
                continue  # too big to be useful as CSV; query the warehouse instead
            target = PATHS.output / f"{table}.csv"
            con.execute(f'COPY "{table}" TO {sql_literal(target)} (FORMAT csv, HEADER true)')
            written.append(target)
            log.info("wrote %s", target)
    finally:
        con.close()
    return written
