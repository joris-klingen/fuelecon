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

On a like-for-like basis — one measurement cycle, litres actually burned, constant
kerb mass — fuel economy improved by **40%** between build years 2000 and 2024, not
the **52%** the type-approval figures claim. The difference is a widening gap
between laboratory and road, and cars getting heavier.

## Quick start

```bash
uv sync                       # Python: duckdb + httpx
uv run fuelecon all           # download ~47M rows, build the warehouse, export CSV
Rscript R/run_analysis.R      # analysis and figures in CPB house style
```

The ingest takes about 25 minutes over the RDW API and is resumable — interrupt it
and re-run, it picks up from the last page. `uv run fuelecon info` shows what is on
disk. Roughly half of that is the four type-approval tables; pass
`uv run fuelecon ingest vehicles fuel` to skip them and build the fleet series
alone.

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
| Type approval | `sql/015_type_approval.sql` | Plate → approval → variant → version |
| Aggregate | `sql/020_*.sql`, `sql/030_*.sql` | Fleet composition and efficiency tables |
| Per car | `sql/060_vehicle_energy.sql` | Energy per km per carrier, with provenance |
| Analysis | `R/` | Figures in CPB house style via `ggcpb`, headline numbers |

### Data sources

| Dataset | Rows | Contents |
|---|---|---|
| [`m9d7-ebf2`](https://opendata.rdw.nl/dataset/m9d7-ebf2) | 9,529,597 (filtered) | Registry: make, model, build year, mass, dimensions |
| [`8ys7-d773`](https://opendata.rdw.nl/dataset/8ys7-d773) | 16,936,567 | Fuel and emissions: consumption, CO2, Euro standard |
| [`gr7t-qfnb`](https://opendata.rdw.nl/dataset/gr7t-qfnb) | 6,330,502 | Type approval: energy declarations per version |
| [`byxc-wwua`](https://opendata.rdw.nl/dataset/byxc-wwua) | 2,955,968 (M1 only) | Type approval: masses, dimensions, road load |
| [`4by9-ammk`](https://opendata.rdw.nl/dataset/4by9-ammk) | 6,144,109 | Type approval: engine and drive |
| [`7rjk-eycs`](https://opendata.rdw.nl/dataset/7rjk-eycs) | 5,819,853 | Type approval: transmission |

The registry is filtered server-side to `voertuigsoort='Personenauto'` with first
admission in 2000-2024. Nothing else can be filtered to those vehicles server-side
(Socrata has no cross-dataset joins), so the fuel and type-approval tables are taken
whole and joined locally — except the road-load table, which carries a vehicle
category and is cut to `M1%` at the source.

## Findings

### Fuel economy, corrected

Everything below is in litres per 100 km, on one cycle (WLTP-equivalent), for cars
that burn fuel. Each row strips out one more distortion.

| Basis | 2000 | 2024 | Change |
|---|---|---|---|
| Type approval | 9.43 | 4.54 | −52% |
| …on the road | 8.57 | 6.09 | **−29%** |
| …and at constant 2000 kerb mass | 8.57 | 5.17 | **−40%** |
| Whole fleet, electric counted as 0 l | 8.57 | 4.04 | −53% |

Read down the table: type approval claims a halving. Correcting to what cars
actually burned cuts that to −29%, because the laboratory-to-road gap widened from
9% to 40% over the NEDC era — improvement that existed on paper only. Holding kerb
mass at its 2000 level restores it to −40%: about **0.9 l/100 km** of real
engineering gain was spent carrying heavier cars rather than saving fuel.

On-road consumption actually **rose** between 2013 and 2019, peaking at 7.67
l/100 km, while the type-approval figure kept falling. The last row is the fleet
including cars with no fuel tank; it returns to −53% only because 30% of the 2024
vintage burns nothing.

### Type-approval CO2

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

## The three corrections

### 1. One measurement cycle, estimated not assumed

The NEDC→WLTP switch splits the series in two. Rather than borrow a published
scalar, the conversion is estimated from **1,411,000 cars that carry both
declarations on the same registry record** — the same car, measured both ways
(`sql/040_cycle_conversion.sql`). Factors are fitted per powertrain × kerb-mass
band:

| Powertrain | WLTP/NEDC ratio | Paired cars |
|---|---|---|
| Petrol | 1.157 – 1.204 (falling with mass) | 1,068,000 |
| Diesel | 1.215 – 1.290 | 57,000 |
| Self-charging hybrid | 1.178 – 1.286 | 265,000 |
| Plug-in hybrid | 1.254 (pooled; cells too thin) | 113 |

These pool to **1.204**. The European Commission's impact assessments assumed 21%,
later confirmed by a JRC study — an independent check the estimate passes without
having been fitted to it.

The unavoidable assumption: factors estimated on 2018–2024 cars are applied back to
cars built from 2000, which were never WLTP tested. A converted 2003 figure is an
estimate of what WLTP would have said, not a measurement. 65% of the fleet carries
a converted figure, 25% a measured one; `wltp_basis` flags which.

### 2. Litres actually burned

Type approval is a laboratory number, and the divergence from real driving is not
constant — it grew through the NEDC era as test tolerances were exploited, then
reset under WLTP. Two external sources, both in `sql/050_real_world.sql` where they
can be replaced in one place:

- **WLTP era** — European Commission, [COM(2024) 122 final](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:52024DC0122),
  Table 3, from OBFCM on-board monitoring of 617,194 cars registered in 2021:
  petrol **+20.4%**, diesel **+16.7%**, plug-in hybrid **+267%**. The report notes
  the gap is identical for CO2 and fuel consumption.
- **NEDC era** — the same report puts the gap at "around 40%" by 2017 (citing JRC
  28734 EN); ICCT put it near 9% in 2001. Intermediate years are linearly
  interpolated, which is an approximation, not a sourced series.

Converted cars are corrected off their own NEDC figure using that year's NEDC gap,
*not* via the WLTP-equivalent. Going the other way would apply today's 20% gap to a
2003 car and overstate it by a third — those cars broadly did meet their NEDC
figure, which is precisely why the gap had room to grow.

Plug-in hybrids take their own factor in every year: the divergence is driven by
how often the car is actually plugged in, not by which cycle certified it.

### 3. Constant kerb mass

Cars gained 31% kerb mass over the period, so part of the engineering gain went
into carrying more car. The counterfactual holds mass at its 2000 level using a
consumption-per-kilogram slope identified *within* build year — a heavy against a
light car of the same vintage, so engine technology is held fixed:

    beta = sum_y n_y cov_y(litres, mass) / sum_y n_y var_y(mass)

DuckDB computes the per-cell moments, R assembles the estimate, and 9.5M rows never
enter R. The pooled combustion slope is **0.0033 l/100 km per kg**.

One subtlety worth knowing: run this *within petrol only* and the correction nearly
vanishes, because mean petrol kerb mass barely moved (1,111 → 1,119 kg). Every time
a larger car electrified it left the petrol category and took its mass with it. The
fleet-wide mass gain is largely that composition shift, so the correction is only
meaningful with the powertrains pooled. Both are reported.

## Per-car energy, for comparing two specific cars

Everything above is about the fleet. A different question — what does *this* car
cost to drive, and how does that differ from the one it replaced — needs a
different table, because the cost of a kilometre is

    sum over carriers of  (energy per km) x (price per unit)

and the fleet corrections are the wrong resolution for a difference between two
cars. They are constant within powertrain (WLTP era) or within build year (NEDC
era), so for a petrol-to-electric comparison the correction is a deterministic
function of the two powertrains: it carries nothing a powertrain dummy would not,
while looking like it does.

So `sql/015_type_approval.sql` and `sql/060_vehicle_energy.sql` build a per-car
layer that leaves the fleet series untouched.

### The type-approval chain

A licence plate names the exact version it was certified as:

    kenteken                                  H738VS
      typegoedkeuringsnummer                  e1*2007/46*0627*09
      variant                                 SACCYVBX0
      uitvoering                              FD7FD7CW001N7MMOVL01VR2

That is a far finer object than make and model — it fixes the drivetrain and body
the figures were measured on. 90.4% of 2000 vintages carry the keys, rising to
99.2% of 2024 ones. Following them into the type-approval tables adds three things
the licence plate does not hold:

- **The NEDC phase split.** Urban and extra-urban CO2 separately, which differ by
  about a third on the same certificate. The plate carries only the combined
  figure, so a household doing short trips and one doing motorway miles get the
  same number.
- **Both bounds of every declaration.** A version quotes a range; the plate quotes
  a point. `spread_pct` says how much the one number is standing in for.
- **Road load.** The coast-down polynomial `F(v) = f0 + f1·v + f2·v²` the
  dynamometer was set to — rolling resistance and aerodynamic drag, the only
  physical description of the car anywhere in this data. It arrived with WLTP, so
  it exists for roughly 2018 onwards, which is where the electric switches are.

### `vehicle_energy`

One row per licence plate per energy carrier — petrol, diesel, LPG, CNG,
electricity — so attaching a price series is a join rather than a rewrite of the
arithmetic per powertrain combination.

The grain is the *fuel row*, not the car, and that matters: 25,493 of the 57,534
LPG cars here declare a different figure for petrol than for gas. One reads 6.80
l/100 km on LPG and 5.10 on petrol. Reducing that to one number per car picks
whichever is larger and labels it with whichever fuel the classifier preferred, so
the car ends up with one carrier, the wrong figure, and the wrong price.

Each row says where its figure came from:

| `basis` | Meaning |
|---|---|
| `wltp_plate` | WLTP declaration on the licence plate |
| `wltp_variant` | WLTP declaration on the type-approval version |
| `nedc_plate` | NEDC declaration on the licence plate, converted |
| `nedc_variant` | NEDC declaration on the version, converted |
| `none` | The car uses this carrier and no figure was found |

The `_variant` rows are what the chain buys: plates whose own fuel record is blank.
For the electricity of 2021 vintages that is a third of all cars, and it cuts the
share with no figure at all from 43% to 10%. Rows are emitted even when the figure
is missing, so a price join returns a null cost rather than dropping the car.
`energy_coverage_by_year` reports the mix per vintage, and `variant_match_quality`
reports how well the chain held.

Two things this table deliberately does not do. It does not apply the constant-mass
counterfactual, which answers a fleet question and says nothing about what a
specific car costs its owner. And it puts no on-road correction on electricity:
there is a real gap between a battery car's WLTP figure and what it draws in Dutch
conditions, but no sourced series for it here, and a fabricated one would land on
exactly the side of the comparison that matters.

### One unit bug, fixed on the way

RDW declares electricity in **Wh/km** while everything else is per 100 km, so every
electric field is ten times what its name suggests — the median battery car reads
162, meaning 16.2 kWh/100 km. The existing `BETWEEN 5 AND 60` sanity bound on
`kwh_100km` therefore discarded 619,374 of 619,375 battery cars, and
`median_kwh_100km` came out empty in `fleet_by_year_powertrain` and
`efficiency_by_powertrain`. Both now carry real values.

That is the only fleet number that moves. Every other exported table reproduces bit
for bit against the pre-change SQL, checked by rebuilding both against the same
Parquet and hashing every column.

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
| `cycle_conversion` | Estimated WLTP/NEDC factors per powertrain × mass band |
| `fuel_economy_trend` | Type-approval and on-road l/100km per year × powertrain |
| `fleet_fuel_trend` | Fleet l/100km, electric counted as zero litres |
| `realworld_gap_nedc` / `realworld_gap_wltp` | The gap assumptions, as data |
| `mass_regression_stats` | Within-year moments for the constant-mass correction |
| `variant_match_quality` | How far the type-approval chain reaches, per vintage |
| `energy_coverage_by_year` | Where each vintage's per-car figure comes from |

The per-vehicle and per-version tables — `vehicles`, `vehicle_energy`,
`vehicle_fuel`, `vehicle_variant`, `vehicle_variant_energy`, `variants` — stay in
`data/fuelecon.duckdb` rather than being written out as CSV, because they run to
millions of rows. Query them directly:

```sql
-- Energy and its provenance for one car, per carrier.
SELECT carrier, unit, energy_per_100km_typeapproval, basis, spread_pct
FROM vehicle_energy WHERE kenteken = 'H738VS';
```

`R/run_analysis.R` writes eleven figures to `output/figures/`. `docs/results.html`
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
