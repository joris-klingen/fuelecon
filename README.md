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

Fuel efficiency improved about **45%** between build years 2000 and 2024 — 45.3%
holding the car's specification fixed, 46.4% following the same nameplate through
its generations. Two methods with entirely different identifying variation agree to
within a point. Both show a plateau from 2014 to 2019; neither shows engines
getting worse. The fleet-level numbers that suggest otherwise are composition and
measurement, not engineering.

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

## Replacing your car with a five-year-newer one

Holding the kind of car fixed — same body type, same size class — how much fuel
does five years of progress buy? (`sql/060_segments.sql`, figures 12–16.)

| Newer car built | Replaces | Saving |
|---|---|---|
| 2010 | 2005 | 0.70 l/100km (8.7%) |
| 2013 | 2008 | 1.28 l/100km (16.0%) |
| 2019 | 2014 | **−0.74 l/100km (−10.8%)** |
| 2024 | 2019 | **2.02 l/100km (25.1%)** |

The 2024-against-2019 row is the only clean one: 100% and 91% of the two sides
carry a measured WLTP figure, so no conversion assumption enters. Repeating it on
true vehicle length instead of mass bands gives 1.66 l/100km (21.6%) — the
mass-band version overstates by about 0.35 l/100km, because equipment mass creep
means a 1,200 kg car in 2024 is a physically smaller car than a 1,200 kg car in
2019. Take the honest answer as **roughly 1.7–2.0 l/100 km, or about a fifth**.

Cars built through the middle 2010s were *worse* than the five-year-older car they
replaced. Part of that is measured — same-size cars kept gaining mass and power —
and part is the modelled NEDC gap ramp, since a 2018 car with the same laboratory
figure as a 2013 car burned more on the road. Comparisons whose older side is a
converted NEDC figure inherit that assumption; `pct_measured_old` and
`pct_measured_new` flag which rows those are.

### Is the V-shape an artefact of the corrections?

Fair question, since two modelling steps sit between the registry and that curve.
It is testable, and `segment_saving_basis` (figure 17) runs the test: the identical
saving computed on three bases.

| Newer car | On the road | Type approval, no gap | Raw NEDC, uncorrected |
|---|---|---|---|
| 2013 | 1.28 | 1.77 | **1.50** |
| 2019 | −0.74 | −0.14 | **−0.18** |
| 2024 | 2.02 | 2.00 | (6% coverage) |

**The V is not manufactured by the corrections.** It is there in the untouched NEDC
declarations, which cover ~100% of both sides for every comparison up to 2019: the
saving peaks in 2013 and crosses into negative territory in 2018–19 on raw data.

What the corrections do:

- The **cycle conversion cannot be responsible at all.** For NEDC-era cars
  `sql/050` builds the on-road figure from the raw NEDC value times that year's
  gap, never via the WLTP-equivalent — the 040 factor never enters. (The one
  exception is plug-in hybrids, negligible before 2018.)
- The **real-world gap ramp deepens the trough and flattens the early limb.** In
  every NEDC-era pair the newer car carries a larger assumed gap, which subtracts
  0.4–0.6 l/100 km from the measured saving throughout. It roughly quadruples the
  2019 dip (−0.18 raw → −0.74 on the road) without creating it.
- The **2024 recovery is not model-dependent**: on-road and type approval agree to
  0.02 l/100 km, because both sides carry the same WLTP gap factor and it cancels.

The raw column stops being informative after 2020 — NEDC declarations survive for
only 5.9% of 2024 cars, and that residue is self-selected toward long-running type
approvals. The handover years (2018–2021) carry the most model dependence, since
they pair a converted old side with a measured new one.

### The saving is powertrain switching, not engine progress

Hold size *and* powertrain fixed, and the picture changes completely (figure 16).
Petrol cars, on-road litres, by size class:

| Size class | 2000 | 2013 | 2024 | since 2013 |
|---|---|---|---|---|
| Small (<950 kg) | 6.9 | 5.7 | 5.9 | **+3.1%** |
| Middle (1150–1350 kg) | 9.36 | 7.54 | 7.07 | −6.3% |
| Very large (≥1600 kg) | 14.1 | 10.8 | 12.2 | **+8.0%** |

A petrol car of a given size improved about 19% between 2000 and 2013 and has
been flat or slightly worse since. The small and very large classes now burn
*more* than their 2013 equivalents. Practically all of the 25% five-year saving
above comes from buying a different kind of drivetrain — by 2024, 82% of the
heaviest size band is plug-in hybrid, consuming 4.3 l/100 km against 12.2 for a
petrol car of the same mass.

That last figure leans hard on one assumption: the Commission's +267% real-world
correction for plug-in hybrids. If those cars are charged less than the OBFCM
sample charged them, the saving is smaller.

## The proper answer: same specification, one year newer

A segment is not a specification. Inside one cell (hatchback, 1150–1350 kg) the
hybrid share runs 0% → **35% in 2010** → 1% in 2016 → 73% in 2024, tracking Dutch
tax incentives rather than technology; engine power drifts 91 → 98 kW over
2014–2019 and back; diesel goes 13% → 0%. Those swings, not engine regression, are
what the V-shape in figure 14 is mostly made of.

So `sql/070_hedonic.sql` and `R/05_hedonic.R` hold the specification itself fixed:
a regression of log fuel consumption on build-year dummies plus mass, power, fuel
type and body type, over 20,117 cells. The year coefficients answer the question
directly — **a car of identical size, power, fuel and shape, built a year later,
uses how much less fuel?**

Measurement is handled by splitting rather than converting. The regression is run
twice on *raw* declarations, once per test cycle, and the two are chained over
2019–2020 where both exist — the way a statistical agency splices an index. **No
cycle factor and no real-world gap enters the trend at any point**, so this index
is immune to the objection that the corrections drive the result. (The implied
splice is 1.212, independently reproducing the 1.204 of step 040.)

| | Quality-adjusted |
|---|---|
| Total improvement 2000 → 2024 | **45.3%** |
| Average per year | **2.47%** |
| 2001–2013 | 2.95% / year |
| 2014–2024 | 1.91% / year |
| Years that got worse | 2 of 24 (worst: 2019, +1.6%) |

**Engines did not get worse.** At constant specification, efficiency improved in 22
of 24 years. What did happen is a genuine *plateau* from 2014 to 2019 — five years
newer bought 18.8% in 2013, 1.4% in 2019, and 15.5% again by 2024.

So the answer to "how much do I save on a five-year-newer car" has two parts:

- **Holding specification fixed** (figure 20): 15.5% today, near zero in 2019.
- **As actually bought** (figure 14): ~20%, because buyers also switch to hybrids.

The two nearly coincide today by coincidence — in 2019 they were 1.4% and −10.8%.

One caveat on the plateau. NEDC figures for cars built after 2018 are not fresh lab
tests; they were produced by back-conversion from WLTP. The 2014–2017 part of the
plateau rests on genuine NEDC measurements, but its 2018–2020 tail and the chaining
point inherit that derivation.

## Within the model: a matched-model index

The last cut follows the nameplate instead of the specification — a Golf against a
Golf, a Clio against a Clio (`sql/080_model_index.sql`, figures 21–23). It is a
chained Törnqvist index over year-on-year links, matching 175–395 models per link.

Two properties make it the cleanest measure in the project:

- **It needs no assumptions at all.** Each link compares one model in two adjacent
  years on the *same* declaration, and no link straddles the cycle switch. No
  conversion factor, no splice constant, no real-world gap enters anywhere.
- **Renaming is handled by the chaining, not by hand.** Peugeot's 206, 207 and 208
  overlap in the registry (206 to 2013, 207 from 2006, 208 from 2011), so each is
  matched against itself in adjacent years and the chain passes through the
  renaming without a break. No lineage table is needed.

| Index, 2000 = 100 | 2024 | Improvement |
|---|---|---|
| Same **model** | 53.6 | **46.4%** |
| Same **specification** (hedonic) | 54.7 | 45.3% |
| Same model, alternative cycle cut | 57.9 | 42.1% |

**Two methods with completely different identifying variation land within a point
of each other.** The hedonic uses cross-sectional characteristics; the matched-model
index uses only within-nameplate change over time and touches none of the
corrections. Their agreement at ~45% is a much stronger result than either alone.

The wedge between them is informative in both directions (figure 23). Until about
2020 the nameplate line sits *above* the specification line: following a Golf
delivered less than a constant specification would have, because the Golf itself
kept growing. After 2020 it dips below, because powertrain is a control in the
hedonic — hybridisation is stripped out there, while a nameplate that goes hybrid
keeps the benefit.

The matched-model index also corroborates the plateau independently: the same
models got *worse* in four consecutive years, 2016–2019, and in 2019 alone they
gained 14 kg and 2.1 kW.

### A measurement finding worth recording

Where both declarations exist, the two bases disagree in **every** year, with NEDC
always showing less improvement:

| Link | NEDC basis | WLTP basis |
|---|---|---|
| 2019 | +3.3% | −0.7% |
| 2021 | −1.4% | −8.7% |

Two things explain this and both discredit the NEDC side after 2018: those figures
are back-conversions from WLTP rather than fresh tests, and the population still
carrying one shrinks to 17 models by 2024, self-selected toward type approvals
carried over unchanged. The index therefore switches to WLTP from 2019; the
alternative cut at 2021 is reported as a sensitivity and costs 4 index points.

### Why size is proxied by kerb mass

RDW records a length for only 53% of cars built before 2016 (98% by 2024), and the
missing half is not random — cars with a recorded length in 2010 average 1,085 kg
against 1,208 kg for those without. Segmenting on length would compare a biased,
lighter early sample against a complete late one and read the difference as
progress. Kerb mass is recorded for every car in every year. The length-based
version is computed anyway over 2016–2024 as a check, and is reported alongside.

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
| `consumption_by_type` / `consumption_by_size` | On-road l/100km per year × body type / size class |
| `consumption_by_segment` | The same by type × size, the replacement cell |
| `segment_saving` / `segment_saving_summary` | Five-year replacement saving per segment |
| `segment_saving_length` | The same on true length bands, 2016-2024 |
| `fixed_weight_index` | Fleet consumption at the 2000 type and size mix |
| `segment_saving_basis` | The saving on three bases, to test the corrections |
| `hedonic_cells` / `hedonic_splice` | Cells and regime splice for the quality-adjusted index |
| `hedonic_coverage` | Which cycle each build year can support |
| `model_index_links` | Year-on-year matched-model links, per cycle basis |
| `model_histories` | Consumption history of every nameplate, for inspection |
| `model_basket` | Fixed basket of long-lived nameplates, as a check |

The 9.5M-row `vehicles` table stays in `data/fuelecon.duckdb`; query it directly for
anything the aggregates do not cover.

`R/run_analysis.R` writes twenty-three figures to `output/figures/`. `docs/results.html`
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
