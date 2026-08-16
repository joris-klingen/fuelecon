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
  interrupted download resumes. The key may be several columns: the type-approval
  tables have 69k rows under one approval number, more than a page, so their key is
  the `(approval, variant, version)` triple. SoQL has no row-value comparison, so
  `_keyset_clause` writes the lexicographic test out term by term.
- `sql/0NN_*.sql` — run in filename order by `warehouse.build()`. `010` produces
  the one-row-per-vehicle `vehicles` table; `015` attaches each plate to its
  type-approval version; `020`/`030` aggregate it; `040` puts everything on one
  measurement cycle; `050` turns type approval into on-road litres and emits the
  moments for the mass correction; `060` builds the per-car energy table.
- `R/00_setup.R` — shared labels, year axis, `fig()` export helper. `01_fleet.R`,
  `02_efficiency.R` and `03_adjusted.R` each build figures and a `*_facts` list
  that `run_analysis.R` prints.
- `docs/build_page.py` — regenerates `docs/results.html` from `output/figures/`.

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

## Two layers, and which one to use

There are now two answers to "what does this car consume", and they are for
different questions. Mixing them up is the easiest way to get a confident wrong
number out of this repository.

- **Fleet layer** (`020`–`050`, exported as the trend tables). Aggregates, with the
  three corrections applied. Use for anything about how the fleet changed.
- **Per-car layer** (`015` and `060`: `vehicle_energy`, `vehicle_variant`). One row
  per licence plate per energy carrier, with provenance. Use for anything that
  compares two specific cars — a household replacing one with another, say.

The corrections in `050` are constant within powertrain (WLTP era) or within build
year (NEDC era). That resolution is right for a fleet average and wrong for a
difference between two cars: for a petrol-to-electric comparison the correction is a
deterministic function of the two powertrains, so it carries no information a
powertrain dummy would not, while looking like it does.
`energy_per_100km_typeapproval` varies car by car; `energy_per_100km_onroad` is
there to be compared against, not to be trusted as a per-car quantity.

`015` and `060` are additive. They do not feed `020`–`050`, and the published fleet
numbers do not move when they change. Keep it that way: if a better per-car figure
should also change the fleet series, change the fleet series deliberately.

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
5. **Scrapped cars are gone; exported ones are not.** The register holds 580,039
   exported cars from these vintages (`export_indicator = 'Ja'`) but only 34,450
   other non-transferable ones, far too few to be the demolished population. So a
   panel of car replacements built from this snapshot is missing precisely the cars
   that were replaced *because* they were finished. That needs historical register
   snapshots, or CBS's copy, which retains deregistrations.

Also: `build_year` is `datum_eerste_toelating` (first admission anywhere), so used
imports carry a foreign build year; `owner_since` is the start of the *current*
ownership spell, because the open register keeps no ownership history; and RDW
encodes missing as an empty string and sometimes as `0`, which is why casts are
`TRY_CAST` with `nullif(..., 0)`.

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
