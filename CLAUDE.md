# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Analysis of Dutch passenger cars built 2000-2024 using RDW open data: how fuel
efficiency improved, and how many of each car survive in the current fleet. See
`README.md` for the findings and the full methodology.

## Commands

```bash
uv sync                          # Python deps
uv run fuelecon all              # ingest + build + export (~14 min from cold)
uv run fuelecon ingest --max-pages 5   # small slice, for a smoke test
uv run fuelecon build            # re-run sql/ only (~95 s, needs Parquet present)
uv run fuelecon export           # result tables -> output/*.csv
uv run fuelecon info             # paths and what is on disk
uv run pytest -q                 # tests (pagination correctness)
uv run ruff check .              # lint
Rscript R/run_analysis.R         # figures + headline numbers
```

Editing SQL means re-running `build` then `export` then the R script. Editing only
R means re-running the R script.

## Architecture, and why

DuckDB does the row crunching once; R does the interpretation. The boundary is
`output/*.csv`: DuckDB writes aggregate tables of tens to thousands of rows, R
reads those. Do not move the 9.5M-row join into R, and do not push interpretation
or plotting into SQL.

- `src/fuelecon/config.py` — dataset definitions, columns, scope. Change what gets
  downloaded here, not in the downloader.
- `src/fuelecon/rdw.py` — keyset pagination. Socrata's `$offset` degrades badly at
  depth (12 s at offset 9M against 1.6 s for a keyset page), so paging is always
  `WHERE key > cursor ORDER BY key`. State is written after every page, so an
  interrupted download resumes.
- `sql/0NN_*.sql` — run in filename order by `warehouse.build()`. `010` produces
  the one-row-per-vehicle `vehicles` table; everything after it aggregates.
- `R/00_setup.R` — shared labels, year axis, `fig()` export helper. `01_fleet.R`
  and `02_efficiency.R` each build figures and a `*_facts` list that
  `run_analysis.R` prints.

## Domain traps

These are the ways this dataset produces confident wrong answers. All four are
handled in `sql/010_vehicles.sql`; read the comments there before changing it.

1. **NEDC vs WLTP.** Type approval switched cycles over 2017-2018 and WLTP figures
   run 15-25% higher for the same car. Never build a CO2 or l/100km series that
   spans the switch without splitting on `test_cycle`.
2. **BEVs have null CO2, not zero.** Aggregating over non-null CO2 drops exactly
   the cars that are displacing combustion. Use `co2_g_km_tailpipe` for
   fleet-wide series, `co2_g_km` when you deliberately want combustion only.
3. **PHEV vs HEV needs `klasse_hybride_elektrisch_voertuig`.** The fuel list is
   identical for both. `OVC-HEV` = plug-in, `NOVC-HEV` = self-charging.
4. **Counts are stock, not sales.** `fleet_by_year` is what survives today.

Also: `build_year` is `datum_eerste_toelating` (first admission anywhere), so used
imports carry a foreign build year; and RDW encodes missing as an empty string and
sometimes as `0`, which is why casts are `TRY_CAST` with `nullif(..., 0)`.

## Conventions

- Raw columns keep their Dutch RDW names; derived columns are English snake_case.
- Figures and their labels are Dutch (CPB house style); code and comments English.
- Everything is read from CSV as VARCHAR and cast once, explicitly, in `010`.
- `data/` and `output/` are gitignored — reproducible, never committed.
- Paths in DuckDB SQL are inlined via `sql_literal()`, not bound as parameters:
  positional parameters in a `COPY ... TO` statement bind to the copy target first
  and silently swap source and destination.

## Plotting

Figures use `ggcpb` (CPB house style, <https://github.com/joris-klingen/ggcpb>):
`cpb_line()`, `cpb_col()`, `save_cpb()`. It needs ggplot2 ≥ 3.5.0. `save_cpb()`
only accepts the two CPB page widths, so pass `page = "half"` or `"full"` rather
than a custom width. Palette colours are picked by position with `index =`.
