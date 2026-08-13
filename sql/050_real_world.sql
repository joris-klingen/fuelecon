-- Step 050: from type-approval figures to on-road fuel economy, and the inputs
-- for the constant-mass correction.
--
-- Type approval is a laboratory number. What a car actually burns is higher, and
-- the size of that divergence is not a constant: it grew through the NEDC era as
-- test tolerances were exploited, then reset when WLTP arrived. Applying one gap
-- to the whole period would erase precisely the effect this step exists to show.
--
-- SOURCES. Everything in the two tables below is external to RDW and is stated
-- here so it can be checked or replaced in one place.
--
--  * WLTP era: European Commission, COM(2024) 122 final, 18.3.2024, Table 3 --
--    the first report under Art. 12(3) of Regulation (EU) 2019/631, based on
--    OBFCM on-board monitoring data for 617,194 cars first registered in 2021.
--    km-weighted average gaps: petrol +20.4%, diesel +16.7%, plug-in hybrid
--    +267%. The report notes the gap is identical for CO2 and fuel consumption,
--    which is what lets these factors apply to l/100 km unchanged.
--  * NEDC era: the same report puts the real-world gap against NEDC at "around
--    40%" by 2017, citing Pavlovic et al., JRC 28734 EN (2017). The early-period
--    anchor is ICCT's estimate of roughly 9% for 2001. Years between the two
--    anchors are linearly interpolated -- the published series is close to linear
--    over this window, but the intermediate years are an interpolation, not
--    separately sourced figures.
--
-- A useful independent check on step 040: the Commission's impact assessments
-- assumed WLTP CO2 runs 21% above NEDC, later confirmed by JRC. The factors
-- estimated here from 1.41M paired RDW records pool to almost exactly that.

-- Gap against NEDC by build year, as a multiplier on the type-approval figure.
CREATE OR REPLACE TABLE realworld_gap_nedc AS
WITH anchors AS (SELECT 2001 AS y0, 0.09 AS g0, 2017 AS y1, 0.40 AS g1),
     yrs AS (SELECT range AS build_year FROM range(2000, 2025))
SELECT
    y.build_year,
    round(
        CASE
            WHEN y.build_year <= a.y0 THEN a.g0
            WHEN y.build_year >= a.y1 THEN a.g1
            ELSE a.g0 + (a.g1 - a.g0) * (y.build_year - a.y0) / (a.y1 - a.y0)
        END, 4)                                            AS gap
FROM yrs y CROSS JOIN anchors a
ORDER BY y.build_year;

-- Gap against WLTP by powertrain.
--
-- Self-charging hybrids are petrol cars and are not broken out in the source, so
-- they take the petrol gap. LPG and CNG likewise. Plug-in hybrids are the outlier
-- and the reason this is powertrain-specific rather than a single number: their
-- certified figure assumes the battery is charged far more often than it is.
CREATE OR REPLACE TABLE realworld_gap_wltp AS
SELECT * FROM (VALUES
    ('Petrol', 0.204, 'COM(2024) 122 Table 3, km-weighted'),
    ('Diesel', 0.167, 'COM(2024) 122 Table 3, km-weighted'),
    ('HEV',    0.204, 'not broken out in source; petrol gap applied'),
    ('LPG',    0.204, 'not broken out in source; petrol gap applied'),
    ('CNG',    0.204, 'not broken out in source; petrol gap applied'),
    ('PHEV',   2.670, 'COM(2024) 122 Table 3, plug-in hybrid (all), km-weighted')
) AS t(powertrain, gap, note);

-- One row per vehicle with the on-road figure attached.
CREATE OR REPLACE TABLE vehicles_real AS
SELECT
    w.kenteken,
    w.build_year,
    w.powertrain,
    w.kerb_mass_kg,
    w.wltp_basis,
    w.l_100km_wltp_equiv,
    w.co2_wltp_equiv,

    -- Which gap applies. Plug-in hybrids take their own factor in every year:
    -- the divergence is driven by how often the car is actually plugged in, not
    -- by which laboratory cycle certified it, so the year-varying NEDC series
    -- would understate them badly in the years before WLTP.
    CASE
        WHEN w.powertrain = 'PHEV'      THEN gw.gap
        WHEN w.wltp_basis = 'measured'  THEN gw.gap
        WHEN w.wltp_basis = 'converted' THEN gn.gap
    END                                                    AS gap_applied,

    CASE
        WHEN w.powertrain IN ('BEV', 'FCEV') THEN NULL     -- no litres to correct
        WHEN w.wltp_basis = 'measured' OR w.powertrain = 'PHEV'
            THEN w.l_100km_wltp_equiv * (1 + gw.gap)
        WHEN w.wltp_basis = 'converted'
            -- Converted cars are corrected off their own NEDC figure, using the
            -- divergence measured against NEDC in that year. Going via the
            -- WLTP-equivalent instead would apply today's gap to a 2003 car and
            -- overstate it by a third: those cars broadly did meet their NEDC
            -- figure, which is exactly why the gap had room to grow later.
            THEN w.l_100km_nedc * (1 + gn.gap)
    END                                                    AS l_100km_real,

    -- Fleet fuel use per 100 km on a constant population: zero litres for cars
    -- with no fuel tank, rather than dropping them.
    CASE
        WHEN w.powertrain IN ('BEV', 'FCEV') THEN 0.0
        WHEN w.wltp_basis = 'measured' OR w.powertrain = 'PHEV'
            THEN w.l_100km_wltp_equiv * (1 + gw.gap)
        WHEN w.wltp_basis = 'converted'
            THEN w.l_100km_nedc * (1 + gn.gap)
    END                                                    AS l_100km_real_fleet
FROM vehicles_wltp w
LEFT JOIN realworld_gap_wltp gw USING (powertrain)
LEFT JOIN realworld_gap_nedc gn USING (build_year);

-- Headline trend: type approval versus on road, per build year and powertrain.
CREATE OR REPLACE TABLE fuel_economy_trend AS
SELECT
    build_year,
    powertrain,
    count(*)                                               AS vehicles,
    count(l_100km_wltp_equiv)                              AS vehicles_measured,
    round(100.0 * count(*) FILTER (WHERE wltp_basis = 'converted')
          / nullif(count(*) FILTER (WHERE wltp_basis <> 'none'), 0), 1) AS pct_converted,
    round(avg(l_100km_wltp_equiv), 3)                      AS mean_l_typeapproval,
    round(median(l_100km_wltp_equiv), 3)                   AS median_l_typeapproval,
    round(avg(l_100km_real), 3)                            AS mean_l_real,
    round(median(l_100km_real), 3)                         AS median_l_real,
    round(avg(kerb_mass_kg))                               AS mean_kerb_mass_kg
FROM vehicles_real
GROUP BY build_year, powertrain
HAVING count(*) >= 100
ORDER BY build_year, powertrain;

-- The whole fleet on one line, with zero-fuel cars entered as zero litres.
CREATE OR REPLACE TABLE fleet_fuel_trend AS
SELECT
    build_year,
    count(*)                                               AS vehicles,
    round(avg(l_100km_real_fleet), 3)                      AS mean_l_real_fleet,
    round(avg(l_100km_real), 3)                            AS mean_l_real_combustion,
    round(avg(l_100km_wltp_equiv), 3)                      AS mean_l_typeapproval,
    round(100.0 * count(*) FILTER (WHERE powertrain IN ('BEV', 'FCEV'))
          / count(*), 2)                                   AS pct_zero_fuel
FROM vehicles_real
GROUP BY build_year
ORDER BY build_year;

-- Sufficient statistics for the constant-mass correction.
--
-- The counterfactual asks what a vintage would consume if cars had stayed at
-- their 2000 kerb mass. That needs the consumption-per-kilogram slope identified
-- *within* a build year -- comparing a heavy and a light car of the same vintage,
-- so engine technology is held fixed. Pooling across years instead would let the
-- downward technology trend contaminate the slope.
--
-- The within-year covariance and variance below are all R needs to assemble the
-- fixed-effects slope, which keeps 9.5M rows out of R:
--     beta = sum_y n_y * cov_y(l, mass) / sum_y n_y * var_y(mass)
CREATE OR REPLACE TABLE mass_regression_stats AS
SELECT
    build_year,
    powertrain,
    count(*)                                               AS n,
    round(avg(kerb_mass_kg), 4)                            AS mean_mass,
    round(var_pop(kerb_mass_kg), 4)                        AS var_mass,
    round(avg(l_100km_wltp_equiv), 6)                      AS mean_l_typeapproval,
    round(covar_pop(l_100km_wltp_equiv, kerb_mass_kg), 6)  AS cov_mass_l_typeapproval,
    round(avg(l_100km_real), 6)                            AS mean_l_real,
    round(covar_pop(l_100km_real, kerb_mass_kg), 6)        AS cov_mass_l_real
FROM vehicles_real
WHERE kerb_mass_kg IS NOT NULL
  AND l_100km_wltp_equiv IS NOT NULL
  AND l_100km_real IS NOT NULL
GROUP BY build_year, powertrain
HAVING count(*) >= 100
ORDER BY build_year, powertrain;

-- The same moments pooled over every combustion powertrain, grouped by build year
-- only. This is the version where the mass correction actually bites: within
-- petrol alone, mean kerb mass is almost flat across the period, because as larger
-- cars electrified they left the petrol category and took their mass with them.
-- The 31% fleet-wide mass gain is therefore mostly composition, and only shows up
-- when the powertrains are pooled.
CREATE OR REPLACE TABLE mass_regression_stats_fleet AS
SELECT
    build_year,
    count(*)                                               AS n,
    round(avg(kerb_mass_kg), 4)                            AS mean_mass,
    round(var_pop(kerb_mass_kg), 4)                        AS var_mass,
    round(avg(l_100km_wltp_equiv), 6)                      AS mean_l_typeapproval,
    round(covar_pop(l_100km_wltp_equiv, kerb_mass_kg), 6)  AS cov_mass_l_typeapproval,
    round(avg(l_100km_real), 6)                            AS mean_l_real,
    round(covar_pop(l_100km_real, kerb_mass_kg), 6)        AS cov_mass_l_real
FROM vehicles_real
WHERE kerb_mass_kg IS NOT NULL
  AND l_100km_real IS NOT NULL
  AND powertrain NOT IN ('BEV', 'FCEV')
GROUP BY build_year
ORDER BY build_year;
