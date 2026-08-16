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
  the one-row-per-vehicle `vehicles` table; `020`/`030` aggregate it; `040` puts
  everything on one measurement cycle; `050` turns type approval into on-road
  litres and emits the moments for the mass correction.
- `R/00_setup.R` — shared labels, year axis, `fig()` export helper. `01_fleet.R`,
  `02_efficiency.R` and `03_adjusted.R` each build figures and a `*_facts` list
  that `run_analysis.R` prints.
- `docs/build_page.py` — regenerates `docs/results.html` from `output/figures/`.
  The page is deliberately short: five figures chosen for the marginal-cost-of-
  driving question, an abstract, two tables and a limitations note. Adding figures
  to it is a decision, not a default.

## The three corrections

`040` and `050` exist to make 2000 and 2024 comparable. Change them carefully.

- **Cycle.** WLTP/NEDC factors are *estimated*, from 1.41M cars carrying both
  declarations, per powertrain × mass band. Do not replace them with a scalar.
  Exclude pairs where the two figures are byte-identical — that is one number
  copied into both fields, and it is what produces the spurious 1.000 ratios in
  pre-2018 vintages.
- **Real-world gap.** Two external assumptions, both sourced in the header of
  `050_real_world.sql` and materialised as tables (`realworld_gap_nedc`,
  `realworld_gap_wltp`) so they can be swapped without touching logic. The NEDC
  series is year-varying and that is load-bearing: applying today's WLTP gap to a
  2003 car overstates it by a third.
- **Mass.** The slope is a within-build-year estimator; pooling across years lets
  the technology trend contaminate it. Compute moments in SQL, assemble in R.
  Always use the pooled-powertrain version for fleet statements — within petrol
  alone, mass is nearly flat because heavy cars electrified out of the category.

## Segments (060)

Size is proxied by **kerb mass**, not length: length is recorded for only 53% of
pre-2016 cars and the missing half is systematically 120 kg heavier, so a
length-based segment would read sample bias as progress. The cost is that mass
creep makes a fixed mass band drift toward physically smaller cars, which
overstates the saving; `segment_saving_length` quantifies that on 2016-2024.

Before quoting any five-year saving, check `pct_measured_old` / `pct_measured_new`.
Only 2024-vs-2019 has both sides essentially measured on WLTP; earlier rows inherit
the assumed NEDC gap ramp and are modelled, not measured.

For any claim about *engines*, use the hedonic index (`070`) or the matched-model
index (`080`), not a segment mean. The matched-model index is the one to reach for
first: each link compares one model in two adjacent years on the same declaration,
so it carries no conversion, splice or gap assumption at all. The two indices agree
to within a point (46.4% against 45.3%), which is the project's strongest result.
Note that NEDC declarations after 2018 are back-conversions and show systematically
less improvement than WLTP in every overlap year; prefer WLTP links from 2019. A segment is not a specification: inside one cell the hybrid share
swings 0-35-1-73% with Dutch tax policy and power drifts 7 kW. The index is
estimated on raw declarations per cycle and chained over 2019-2020, so no cycle
factor or gap assumption touches it.

Hold size *and* powertrain fixed (`mean_l_petrol`) before claiming engine progress.
Petrol cars of a given size have been flat since 2013 — the headline saving is
almost entirely people buying hybrids, and in the heaviest band it rests on the
+267% PHEV real-world correction.

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
- Everything user-facing is English: figure titles, axis labels, series names,
  the console summary and `docs/results.html`. Class labels (size bands, body
  types) are emitted in English by the SQL layer, not translated in R.
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
