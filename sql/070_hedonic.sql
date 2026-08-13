-- Step 070: a quality-adjusted efficiency index -- the same car, one year newer.
--
-- The within-segment saving in 060 still moves for reasons that have nothing to do
-- with engines. Inside one cell (hatchback, 1150-1350 kg) the hybrid share runs 0%
-- -> 35% in 2010 -> 1% in 2016 -> 73% in 2024, tracking Dutch tax incentives rather
-- than technology; engine power drifts 91 -> 98 kW over 2014-2019 and back; diesel
-- goes 13% -> 0%. A segment is not a specification.
--
-- So this step holds the specification itself fixed. It builds the cells for a
-- hedonic regression of log fuel consumption on build-year dummies plus mass,
-- power, fuel type and body type. The year coefficients then answer the question
-- directly: for a car of identical size, power, fuel and shape, how much less fuel
-- does one built a year later use?
--
-- MEASUREMENT IS HANDLED BY SPLITTING, NOT CONVERTING. The regression is estimated
-- twice, once on raw NEDC declarations and once on raw WLTP declarations, so no
-- cycle conversion and no real-world gap enters the trend within either regime.
-- The two regimes are then joined using the cars that carry both declarations,
-- which identifies the level shift conditional on specification. This removes the
-- measurement question from the year-on-year comparison entirely.

-- Cells are fine enough that within-cell variation in the continuous controls is
-- small, so a count-weighted regression on cell means recovers the individual-level
-- coefficients closely while keeping 7.8M rows inside DuckDB.
CREATE OR REPLACE TABLE hedonic_cells AS
SELECT
    s.build_year,
    s.powertrain,
    s.car_type,
    50  * (v.kerb_mass_kg // 50)                           AS mass_bin,
    10  * (CAST(v.power_kw AS INTEGER) // 10)              AS power_bin,
    count(*)                                               AS n,

    -- Raw declarations, never converted. A cell contributes to a regime only if it
    -- actually carries that regime's measurement.
    count(v.l_100km_nedc)                                  AS n_nedc,
    avg(ln(v.l_100km_nedc))                                AS mean_log_l_nedc,
    count(coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp)) AS n_wltp,
    avg(ln(coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp))) AS mean_log_l_wltp,

    avg(ln(v.kerb_mass_kg))                                AS mean_log_mass,
    avg(ln(v.power_kw))                                    AS mean_log_power,
    avg(v.kerb_mass_kg)                                    AS mean_mass,
    avg(v.power_kw)                                        AS mean_power
FROM vehicles_segment s
JOIN vehicles v USING (kenteken)
WHERE s.car_type <> 'overig'
  AND v.kerb_mass_kg BETWEEN 500 AND 3500
  AND v.power_kw BETWEEN 20 AND 500
GROUP BY ALL
HAVING count(*) >= 10;

-- The splice between the two measurement regimes, estimated on cells that carry
-- both declarations. This is the log cycle factor conditional on specification --
-- the same quantity step 040 estimates in levels, recovered here independently.
CREATE OR REPLACE TABLE hedonic_splice AS
SELECT
    count(*)                                               AS cells,
    sum(least(n_nedc, n_wltp))                             AS vehicles,
    round(exp(sum((mean_log_l_wltp - mean_log_l_nedc) * least(n_nedc, n_wltp))
              / sum(least(n_nedc, n_wltp))), 4)            AS ratio_wltp_nedc,
    round(sum((mean_log_l_wltp - mean_log_l_nedc) * least(n_nedc, n_wltp))
          / sum(least(n_nedc, n_wltp)), 6)                 AS log_shift
FROM hedonic_cells
WHERE n_nedc > 0 AND n_wltp > 0
  AND mean_log_l_wltp <> mean_log_l_nedc;   -- copied field, not a second measure

-- How much of each build year is available to each regime, so the index can be
-- read with its support in view.
CREATE OR REPLACE TABLE hedonic_coverage AS
SELECT
    build_year,
    sum(n)                                                 AS vehicles,
    sum(n_nedc)                                            AS n_nedc,
    sum(n_wltp)                                            AS n_wltp,
    round(100.0 * sum(n_nedc) / sum(n), 1)                 AS pct_nedc,
    round(100.0 * sum(n_wltp) / sum(n), 1)                 AS pct_wltp
FROM hedonic_cells
GROUP BY build_year
ORDER BY build_year;
