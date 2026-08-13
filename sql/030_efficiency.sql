-- Step 030: the fuel-efficiency trend across build years 2000-2024.
--
-- The one thing that has to be right here is the test cycle. Type-approval CO2 and
-- consumption figures were measured on NEDC until the WLTP switchover (new types
-- from Sep 2017, all new registrations from Sep 2018), and WLTP returns figures
-- roughly 15-25% higher for a physically identical car. Splitting by test_cycle
-- keeps the comparison honest; the `efficiency_trend` table below reports the two
-- series side by side rather than pretending they are one.

-- Fleet-wide tailpipe CO2 on a constant population: every car of the vintage that
-- has a usable figure, with battery-electric and fuel-cell cars entered at 0 g/km
-- instead of dropped for having no CO2 record. This is the series that shows what
-- the switch to electric did; the combustion-only series below shows what engine
-- development did. They answer different questions and diverge sharply after 2019.
CREATE OR REPLACE TABLE fleet_co2_trend AS
SELECT
    build_year,
    count(*)                                                 AS vehicles,
    count(co2_g_km_tailpipe)                                 AS vehicles_measured,
    round(100.0 * count(co2_g_km_tailpipe) / count(*), 1)    AS pct_measured,
    round(avg(co2_g_km_tailpipe), 1)                         AS mean_co2_tailpipe,
    round(median(co2_g_km_tailpipe), 1)                      AS median_co2_tailpipe,
    round(avg(co2_g_km_tailpipe) FILTER (WHERE powertrain NOT IN ('BEV', 'FCEV')), 1)
                                                             AS mean_co2_combustion_only,
    round(100.0 * count(*) FILTER (WHERE powertrain IN ('BEV', 'FCEV')) / count(*), 2)
                                                             AS pct_zero_tailpipe
FROM vehicles
GROUP BY build_year
ORDER BY build_year;

CREATE OR REPLACE TABLE efficiency_trend AS
SELECT
    build_year,
    test_cycle,
    count(*)                                                 AS vehicles,
    count(co2_g_km)                                          AS vehicles_with_co2,
    round(avg(co2_g_km), 1)                                  AS mean_co2_g_km,
    round(median(co2_g_km), 1)                               AS median_co2_g_km,
    round(quantile_cont(co2_g_km, 0.25), 1)                  AS p25_co2_g_km,
    round(quantile_cont(co2_g_km, 0.75), 1)                  AS p75_co2_g_km,
    round(avg(l_100km), 2)                                   AS mean_l_100km,
    round(median(l_100km), 2)                                AS median_l_100km,
    round(avg(kerb_mass_kg))                                 AS mean_kerb_mass_kg,
    round(avg(power_kw), 1)                                  AS mean_power_kw
FROM vehicles
WHERE test_cycle <> 'none'
GROUP BY build_year, test_cycle
ORDER BY build_year, test_cycle;

-- Same trend, split by powertrain. Combustion powertrains only for the l/100km
-- columns; BEV energy use is reported separately in kWh/100 km.
CREATE OR REPLACE TABLE efficiency_by_powertrain AS
SELECT
    build_year,
    powertrain,
    test_cycle,
    count(*)                                                 AS vehicles,
    round(median(co2_g_km), 1)                               AS median_co2_g_km,
    round(median(l_100km), 2)                                AS median_l_100km,
    round(median(kwh_100km), 1)                              AS median_kwh_100km,
    round(avg(kerb_mass_kg))                                 AS mean_kerb_mass_kg,
    round(avg(power_kw), 1)                                  AS mean_power_kw
FROM vehicles
WHERE test_cycle <> 'none'
GROUP BY build_year, powertrain, test_cycle
HAVING count(*) >= 30
ORDER BY build_year, powertrain, test_cycle;

-- A single continuous NEDC-only series for petrol and diesel. NEDC figures keep
-- being declared alongside WLTP for several years after the switch, which gives a
-- like-for-like series that runs the full 2000-2024 window without a cycle break.
CREATE OR REPLACE TABLE efficiency_nedc_series AS
SELECT
    build_year,
    powertrain,
    count(*)                                                 AS vehicles,
    round(median(co2_nedc), 1)                               AS median_co2_g_km,
    round(median(l_100km_nedc), 2)                           AS median_l_100km,
    round(avg(kerb_mass_kg))                                 AS mean_kerb_mass_kg
FROM vehicles
WHERE co2_nedc IS NOT NULL
  AND powertrain IN ('Petrol', 'Diesel', 'LPG', 'HEV', 'PHEV')
GROUP BY build_year, powertrain
HAVING count(*) >= 30
ORDER BY build_year, powertrain;

-- Efficiency is not only a function of the engine: cars also got heavier and more
-- powerful over the period. This table carries CO2 per tonne of kerb mass and per
-- kW so the "how much of the gain is real" question can be asked in R.
CREATE OR REPLACE TABLE efficiency_normalised AS
SELECT
    build_year,
    powertrain,
    test_cycle,
    count(*)                                                 AS vehicles,
    round(median(co2_g_km), 1)                               AS median_co2_g_km,
    round(median(co2_g_km / (kerb_mass_kg / 1000.0)), 1)     AS median_co2_per_tonne,
    round(median(co2_g_km / nullif(power_kw, 0)), 2)         AS median_co2_per_kw,
    round(median(kerb_mass_kg))                              AS median_kerb_mass_kg,
    round(median(power_kw), 1)                               AS median_power_kw
FROM vehicles
WHERE test_cycle <> 'none'
  AND co2_g_km IS NOT NULL
  AND kerb_mass_kg IS NOT NULL
  AND powertrain IN ('Petrol', 'Diesel', 'LPG', 'HEV', 'PHEV')
GROUP BY build_year, powertrain, test_cycle
HAVING count(*) >= 30
ORDER BY build_year, powertrain, test_cycle;

-- Data-quality companion to every table above: how much of each vintage actually
-- carries a usable figure. Coverage is poor for the oldest cars, which is a real
-- constraint on how far back the trend can be read.
CREATE OR REPLACE TABLE coverage_by_year AS
SELECT
    build_year,
    count(*)                                                 AS vehicles,
    round(100.0 * count(*) FILTER (WHERE fuels IS NOT NULL) / count(*), 1)   AS pct_with_fuel_row,
    round(100.0 * count(co2_g_km) / count(*), 1)             AS pct_with_co2,
    round(100.0 * count(l_100km) / count(*), 1)              AS pct_with_consumption,
    round(100.0 * count(kerb_mass_kg) / count(*), 1)         AS pct_with_mass,
    round(100.0 * count(power_kw) / count(*), 1)             AS pct_with_power,
    round(100.0 * count(*) FILTER (WHERE test_cycle = 'WLTP') / count(*), 1) AS pct_wltp,
    round(100.0 * count(*) FILTER (WHERE test_cycle = 'NEDC') / count(*), 1) AS pct_nedc
FROM vehicles
GROUP BY build_year
ORDER BY build_year;
