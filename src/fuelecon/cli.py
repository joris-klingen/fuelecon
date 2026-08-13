"""Command line entry point: `fuelecon ingest | build | export | all | info`."""

from __future__ import annotations

import argparse
import logging
import os
import sys

from . import __version__
from .config import DATASETS, PATHS
from .ingest import ingest, to_parquet
from .warehouse import build, export_outputs


def _configure_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S",
    )
    # One INFO line per HTTP request would be hundreds of lines per ingest run.
    logging.getLogger("httpx").setLevel(logging.DEBUG if verbose else logging.WARNING)


def _selected(names: list[str] | None):
    if not names:
        return list(DATASETS.values())
    missing = [n for n in names if n not in DATASETS]
    if missing:
        raise SystemExit(f"unknown dataset(s): {', '.join(missing)} (have: {', '.join(DATASETS)})")
    return [DATASETS[n] for n in names]


def cmd_ingest(args: argparse.Namespace) -> int:
    token = os.environ.get("RDW_APP_TOKEN")
    for dataset in _selected(args.datasets):
        if args.parquet_only:
            to_parquet(dataset)
        else:
            ingest(dataset, max_pages=args.max_pages, force=args.force, app_token=token)
    return 0


def cmd_build(_: argparse.Namespace) -> int:
    for table, rows in build().items():
        print(f"{table:<28} {rows:>12,}")
    return 0


def cmd_export(_: argparse.Namespace) -> int:
    for path in export_outputs():
        print(path)
    return 0


def cmd_all(args: argparse.Namespace) -> int:
    cmd_ingest(args)
    cmd_build(args)
    return cmd_export(args)


def cmd_info(_: argparse.Namespace) -> int:
    print(f"fuelecon {__version__}")
    print(f"data      {PATHS.data}")
    print(f"warehouse {PATHS.warehouse} ({'present' if PATHS.warehouse.exists() else 'absent'})")
    print(f"output    {PATHS.output}")
    print()
    for key, dataset in DATASETS.items():
        raw = dataset.raw_path
        pq = dataset.parquet_path
        print(f"{key}: {dataset.title}")
        print(f"  source  {dataset.landing_page}")
        print(f"  csv     {'%.0f MB' % (raw.stat().st_size / 1e6) if raw.exists() else '-'}")
        print(f"  parquet {'%.0f MB' % (pq.stat().st_size / 1e6) if pq.exists() else '-'}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="fuelecon", description=__doc__)
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    p_ingest = sub.add_parser("ingest", help="download RDW data and write Parquet")
    p_ingest.add_argument("datasets", nargs="*", help=f"subset of: {', '.join(DATASETS)}")
    p_ingest.add_argument("--max-pages", type=int, help="stop after N pages (smoke test)")
    p_ingest.add_argument("--force", action="store_true", help="discard any partial download")
    p_ingest.add_argument(
        "--parquet-only", action="store_true", help="skip download, re-encode CSV"
    )
    p_ingest.set_defaults(func=cmd_ingest)

    p_build = sub.add_parser("build", help="run the SQL steps into the DuckDB warehouse")
    p_build.set_defaults(func=cmd_build)

    p_export = sub.add_parser("export", help="write result tables to output/ as CSV")
    p_export.set_defaults(func=cmd_export)

    p_all = sub.add_parser("all", help="ingest, build and export in one go")
    p_all.add_argument("datasets", nargs="*")
    p_all.add_argument("--max-pages", type=int)
    p_all.add_argument("--force", action="store_true")
    p_all.add_argument("--parquet-only", action="store_true")
    p_all.set_defaults(func=cmd_all)

    p_info = sub.add_parser("info", help="show paths and what is on disk")
    p_info.set_defaults(func=cmd_info)

    args = parser.parse_args(argv)
    _configure_logging(args.verbose)
    PATHS.ensure()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
