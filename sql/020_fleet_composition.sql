-- Step 020: how many cars of each vintage, powertrain and nameplate are still
-- on the road today.
--
-- Every count here is a *stock* count: the RDW registry is a snapshot of what is
-- registered in the Netherlands right now, not a record of what was sold. Counts
-- for older build years are therefore depressed by scrappage and export, and the
-- decline with age is survival, not sales.

CREATE OR REPLACE TABLE fleet_by_year AS
SELECT
    build_year,
    count(*)                                             AS vehicles,
    count(*) FILTER (WHERE NOT exported)                 AS vehicles_not_exported,
    count(*) FILTER (WHERE insured)                      AS vehicles_insured,
    count(*) FILTER (WHERE nl_registration_year > build_year + 1) AS imported_used,
    round(avg(kerb_mass_kg))                             AS mean_kerb_mass_kg,
    round(avg(power_kw), 1)                              AS mean_power_kw,
    round(avg(displacement_cc))                          AS mean_displacement_cc,
    round(median(co2_g_km), 1)                           AS median_co2_g_km,
    round(median(l_100km), 2)                            AS median_l_100km
FROM vehicles
GROUP BY build_year
ORDER BY build_year;

CREATE OR REPLACE TABLE fleet_by_year_powertrain AS
SELECT
    build_year,
    powertrain,
    count(*)                                             AS vehicles,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY build_year), 2) AS pct_of_year,
    round(avg(kerb_mass_kg))                             AS mean_kerb_mass_kg,
    round(avg(power_kw), 1)                              AS mean_power_kw,
    round(median(co2_g_km), 1)                           AS median_co2_g_km,
    round(median(l_100km), 2)                            AS median_l_100km,
    round(median(kwh_100km), 1)                          AS median_kwh_100km
FROM vehicles
GROUP BY build_year, powertrain
ORDER BY build_year, vehicles DESC;

CREATE OR REPLACE TABLE fleet_by_make AS
SELECT
    make,
    count(*)                                             AS vehicles,
    round(100.0 * count(*) / sum(count(*)) OVER (), 2)   AS pct_of_fleet,
    min(build_year)                                      AS first_build_year,
    max(build_year)                                      AS last_build_year,
    round(median(build_year))                            AS median_build_year,
    round(avg(kerb_mass_kg))                             AS mean_kerb_mass_kg,
    round(median(co2_g_km), 1)                           AS median_co2_g_km
FROM vehicles
WHERE make IS NOT NULL
GROUP BY make
HAVING count(*) >= 500
ORDER BY vehicles DESC;

-- Nameplate level. Restricted to combinations with a real presence so the table
-- stays readable and the medians mean something.
CREATE OR REPLACE TABLE fleet_by_model AS
SELECT
    v.make,
    m.model_clean                                        AS model,
    count(*)                                             AS vehicles,
    min(v.build_year)                                    AS first_build_year,
    max(v.build_year)                                    AS last_build_year,
    mode(v.powertrain)                                   AS main_powertrain,
    mode(v.body_type)                                    AS main_body_type,
    round(avg(v.kerb_mass_kg))                           AS mean_kerb_mass_kg,
    round(avg(v.power_kw), 1)                            AS mean_power_kw,
    round(median(v.co2_g_km), 1)                         AS median_co2_g_km,
    round(median(v.l_100km), 2)                          AS median_l_100km
FROM vehicles v
JOIN model_lookup m ON m.make = v.make AND m.model_raw = v.model_raw
WHERE v.make IS NOT NULL AND m.model_clean IS NOT NULL
GROUP BY v.make, m.model_clean
HAVING count(*) >= 1000
ORDER BY vehicles DESC;

-- Model x vintage, the table that answers "how many of this car from this year
-- are still out there".
CREATE OR REPLACE TABLE fleet_by_model_year AS
SELECT
    v.make,
    m.model_clean                                        AS model,
    v.build_year,
    count(*)                                             AS vehicles,
    mode(v.powertrain)                                   AS main_powertrain,
    round(median(v.co2_g_km), 1)                         AS median_co2_g_km,
    round(median(v.l_100km), 2)                          AS median_l_100km
FROM vehicles v
JOIN model_lookup m ON m.make = v.make AND m.model_raw = v.model_raw
WHERE v.make IS NOT NULL AND m.model_clean IS NOT NULL
GROUP BY v.make, m.model_clean, v.build_year
HAVING count(*) >= 100
ORDER BY vehicles DESC;

CREATE OR REPLACE TABLE fleet_by_body_type AS
SELECT
    build_year,
    coalesce(body_type, 'unknown')                      AS body_type,
    count(*)                                             AS vehicles,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY build_year), 2) AS pct_of_year,
    round(avg(kerb_mass_kg))                             AS mean_kerb_mass_kg,
    round(median(co2_g_km), 1)                           AS median_co2_g_km
FROM vehicles
GROUP BY build_year, body_type
ORDER BY build_year, vehicles DESC;
