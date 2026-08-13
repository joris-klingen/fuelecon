# fuelecon

Fuel efficiency and fleet composition of Dutch passenger cars built 2000-2024,
from [RDW open data](https://opendata.rdw.nl) — the Dutch vehicle registry.

Two questions:

1. **How much did fuel efficiency improve** across build years 2000-2024?
2. **How many of each car** are still present in the current fleet?

**[Read the results page](https://claude.ai/code/artifact/f757c6cf-8711-419f-b8b8-1763015c9e09)** — all seven
figures with the headline numbers and the caveats. Also checked in at
[`docs/results.html`](docs/results.html), self-contained, openable straight from a
clone.

## Result in one line

Type-approval CO2 for a Dutch passenger car fell from **180 to 119 g/km** between
build years 2000 and 2019 on the NEDC cycle (−34%). Fleet-wide tailpipe CO2 fell
from **190 to 71 g/km** (−62%) — but almost all of the post-2019 part of that is
electrification, not engines: 30% of the 2024 vintage has no tailpipe at all,
while a petrol car built in 2024 still emits 124 g/km against 144 in 2019.

## Quick start

```bash
uv sync                       # Python: duckdb + httpx
uv run fuelecon all           # download ~26M rows, build the warehouse, export CSV
Rscript R/run_analysis.R      # analysis and figures in CPB house style
```

The ingest takes about 12 minutes over the RDW API and is resumable — interrupt it
and re-run, it picks up from the last page. `uv run fuelecon info` shows what is on
disk.

## How it fits together

```
RDW Socrata API ──> data/raw/*.csv ──> data/parquet/*.parquet
                                              │
                                     sql/*.sql (DuckDB)
                                              │
                             data/fuelecon.duckdb ──> output/*.csv
                                                            │
                                                    R/*.R (ggcpb)
                                                            │
                                                  output/figures/*.png
```

Python and DuckDB do the heavy lifting once — 9.5M vehicles joined to 16.9M fuel
records, cleaned and aggregated. R reads the small aggregate tables and does the
interpretation and the figures, so it never handles more than a few thousand rows.

| Layer | Where | What |
|---|---|---|
| Download | `src/fuelecon/rdw.py` | Resumable keyset pagination over the Socrata API |
| Ingest | `src/fuelecon/ingest.py` | CSV → Parquet, everything as VARCHAR |
| Transform | `sql/010_vehicles.sql` | Join, cast, classify powertrain and test cycle |
| Aggregate | `sql/020_*.sql`, `sql/030_*.sql` | Fleet composition and efficiency tables |
| Analysis | `R/` | Figures in CPB house style via `ggcpb`, headline numbers |

### Data sources

| Dataset | Rows | Contents |
|---|---|---|
| [`m9d7-ebf2`](https://opendata.rdw.nl/dataset/m9d7-ebf2) | 9,529,597 (filtered) | Registry: make, model, build year, mass, dimensions |
| [`8ys7-d773`](https://opendata.rdw.nl/dataset/8ys7-d773) | 16,936,567 | Fuel and emissions: consumption, CO2, Euro standard |

The registry is filtered server-side to `voertuigsoort='Personenauto'` with first
admission in 2000-2024. The fuel table cannot be filtered to those vehicles
server-side (Socrata has no cross-dataset joins), so it is taken whole and joined
locally.

## Findings

### Efficiency

| Series | From | To | Change |
|---|---|---|---|
| NEDC median CO2 | 180 g/km (2000) | 119 g/km (2019) | −34% |
| NEDC median consumption | 7.4 l/100km | 5.0 l/100km | −32% |
| WLTP median CO2 | 142 g/km (2018) | 114 g/km (2024) | −20% |
| Fleet mean tailpipe CO2 | 190 g/km (2000) | 71 g/km (2024) | −62% |
| Petrol only, WLTP | 144 g/km (2019) | 124 g/km (2024) | −14% |
| Diesel only, WLTP | 156 g/km (2019) | 253 g/km (2024) | **+62%** |

Diesel's number rises because diesel retreated to heavy vehicles: mean kerb mass of
a new diesel went from 1,669 kg in 2019 to 2,538 kg in 2024. Over the same years
the mean petrol car got *lighter* (1,203 → 1,128 kg) as larger cars electrified.
Neither series is a clean read on engine development on its own.

Across the whole period cars got substantially bigger: mean kerb mass rose 31%
(1,187 → 1,556 kg) and mean power 18% (88 → 104 kW). Part of the per-kilometre
efficiency gain was spent on carrying more car, which is why
`efficiency_normalised` also reports CO2 per tonne.

### Fleet

- **9,529,597** passenger cars from build years 2000-2024 are in the current
  register.
- The largest single vintage is **2019** (581,251 cars still registered).
- **22.2%** of the fleet was built in 2000-2009.
- Largest make: **Volkswagen** (11.7%). Largest nameplate: **Volkswagen Polo**
  (282,781 cars).
- Powertrain split of the whole 2000-2024 fleet: petrol 71.3%, self-charging hybrid
  8.1%, diesel 7.7%, battery-electric 6.5%, plug-in hybrid 5.6%, LPG 0.7%.

## Reading the numbers correctly

Four things will produce wrong answers if ignored. All four are handled in the SQL
and documented at the point where they are handled.

**The registry is a stock, not sales.** Every count is what is registered *today*.
The thin tail before 2008 is survival and export, not a small market in those
years. Do not read `fleet_by_year` as a sales series.

**NEDC and WLTP are not comparable.** Type approval switched from NEDC to WLTP
between September 2017 (new types) and September 2018 (all new registrations), and
WLTP returns 15-25% higher figures for a physically identical car. A single series
across the switch shows a fake efficiency regression in 2018-2019. Every efficiency
table carries `test_cycle` and the trend figures plot the two separately.

**Battery-electric cars have no CO2 record.** RDW leaves CO2 null for BEVs rather
than writing a zero, so a plain median over non-null CO2 silently conditions on
"car that burns something" — exactly the cars being displaced. `co2_g_km_tailpipe`
enters BEV and FCEV at 0 g/km so the fleet series stays on a constant population.
This is zero *at the tailpipe*; generation emissions are outside RDW's scope.

**Hybrids are not separable by fuel list alone.** RDW gives a plug-in hybrid and a
self-charging hybrid the same two fuel rows (Benzine + Elektriciteit). Only
`klasse_hybride_elektrisch_voertuig` distinguishes them (`OVC-HEV` = plug-in,
`NOVC-HEV` = self-charging). Classifying on the fuel list alone puts ~775k
self-charging hybrids in the PHEV bucket and roughly triples it.

Smaller caveats: build year is `datum_eerste_toelating`, first admission anywhere in
the world, so for used imports it is the year the car entered service abroad. Model
names are free text and normalised conservatively (punctuation squashed, a repeated
make prefix stripped); `model_lookup` keeps the raw string alongside. CO2 coverage
is ~90% for 2000-2005 vintages against ~99.8% today.

## Output

`uv run fuelecon export` writes these to `output/`:

| Table | Contents |
|---|---|
| `fleet_by_year` | Cars per build year, with mass, power, CO2 |
| `fleet_by_year_powertrain` | The same split by powertrain, with shares |
| `fleet_by_make` / `fleet_by_model` | Fleet counts per make and nameplate |
| `fleet_by_model_year` | Model × vintage counts (≥100 cars) |
| `fleet_by_body_type` | Body type mix per vintage |
| `efficiency_trend` | CO2 and consumption per build year × test cycle |
| `fleet_co2_trend` | Fleet tailpipe CO2 with BEVs at 0, versus combustion only |
| `efficiency_by_powertrain` | The trend per powertrain |
| `efficiency_nedc_series` | Continuous NEDC-only series, no cycle break |
| `efficiency_normalised` | CO2 per tonne and per kW |
| `coverage_by_year` | Share of each vintage carrying a usable figure |

The 9.5M-row `vehicles` table stays in `data/fuelecon.duckdb`; query it directly for
anything the aggregates do not cover.

`R/run_analysis.R` writes seven figures to `output/figures/`. `docs/results.html`
presents them with the numbers and caveats; regenerate it with
`python3 docs/build_page.py` after re-running the analysis.

`data/` and `output/` are not committed — everything is reproducible from the two
commands above.

## Requirements

- Python 3.11+ and [uv](https://docs.astral.sh/uv/)
- R 4.1+ with [`ggcpb`](https://github.com/joris-klingen/ggcpb) and ggplot2 ≥ 3.5.0
  (`ggcpb` uses `guide_axis(minor.ticks=)`, which 3.4 does not have)
- ~2.5 GB of disk for the raw CSV, Parquet and warehouse

An `RDW_APP_TOKEN` environment variable is used if set. It is not required; the
ingest runs fine unauthenticated.
