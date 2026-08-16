-- Step 080: a matched-model index -- the same nameplate, one year newer.
--
-- The hedonic index in 070 holds the specification fixed. This one holds the
-- *model* fixed instead: it follows a Golf against a Golf, a Clio against a Clio,
-- and asks how the fuel consumption of the same nameplate changed from one build
-- year to the next. Aggregating those model-level changes gives the index.
--
-- The two answer genuinely different questions and the difference between them is
-- informative. A 2024 Golf is a much larger and more powerful car than a 2000
-- Golf, so the matched-model index does *not* hold size constant -- it measures
-- what a buyer loyal to one nameplate actually experienced, upsizing included.
-- The hedonic index strips that out. Reading them together separates engine
-- progress from model growth.
--
-- CHAINING MAKES THE MEASUREMENT PROBLEM DISAPPEAR. The index is built from
-- year-on-year links, and each link compares one model in two adjacent years on
-- the *same* declaration. Links to 2020 use raw NEDC, links from 2021 use raw
-- WLTP, and no link ever straddles the switch. So unlike every earlier step this
-- index needs no cycle factor, no splice constant and no gap assumption anywhere.
--
-- Model renaming across generations is handled by the chaining rather than by a
-- hand-built lineage table. Peugeot's 206, 207 and 208 overlap in the registry
-- (206 runs to 2013, 207 from 2006, 208 from 2011), so each is matched against
-- itself in adjacent years and the chain passes through the renaming without a
-- break. A fixed basket of long-lived nameplates is reported alongside as a check.

-- One cell per model and build year, on both declarations, never converted.
CREATE OR REPLACE TABLE model_year_cells AS
SELECT
    v.make,
    l.model_clean                                          AS model,
    v.build_year,
    count(*)                                               AS n,
    count(v.l_100km_nedc)                                  AS n_nedc,
    avg(ln(v.l_100km_nedc))                                AS mean_log_nedc,
    count(coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp)) AS n_wltp,
    avg(ln(coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp))) AS mean_log_wltp,
    avg(v.kerb_mass_kg)                                    AS mean_mass,
    avg(v.power_kw)                                        AS mean_power
FROM vehicles v
JOIN model_lookup l ON l.make = v.make AND l.model_raw = v.model_raw
WHERE l.model_clean IS NOT NULL
  AND v.powertrain NOT IN ('BEV', 'FCEV')
GROUP BY ALL;

-- Year-on-year links. A model enters a link only if it has at least 30 cars in
-- both years on the same declaration, which keeps thin nameplates from swinging
-- the index without excluding them permanently.
--
-- Weights are Tornqvist: the average of the model's share of matched cars in the
-- two years. That treats the two years symmetrically, which matters here because
-- nameplates are entering and leaving throughout.
CREATE OR REPLACE TABLE model_links AS
WITH pairs AS (
    SELECT
        'NEDC'                                             AS basis,
        n.build_year                                       AS build_year,
        n.make, n.model,
        o.n_nedc                                           AS n_old,
        n.n_nedc                                           AS n_new,
        n.mean_log_nedc - o.mean_log_nedc                  AS log_diff,
        n.mean_mass - o.mean_mass                          AS mass_diff,
        n.mean_power - o.mean_power                        AS power_diff
    FROM model_year_cells n
    JOIN model_year_cells o
      ON o.make = n.make AND o.model = n.model AND o.build_year = n.build_year - 1
    WHERE n.n_nedc >= 30 AND o.n_nedc >= 30
      AND n.mean_log_nedc IS NOT NULL AND o.mean_log_nedc IS NOT NULL

    UNION ALL

    SELECT
        'WLTP',
        n.build_year,
        n.make, n.model,
        o.n_wltp, n.n_wltp,
        n.mean_log_wltp - o.mean_log_wltp,
        n.mean_mass - o.mean_mass,
        n.mean_power - o.mean_power
    FROM model_year_cells n
    JOIN model_year_cells o
      ON o.make = n.make AND o.model = n.model AND o.build_year = n.build_year - 1
    WHERE n.n_wltp >= 30 AND o.n_wltp >= 30
      AND n.mean_log_wltp IS NOT NULL AND o.mean_log_wltp IS NOT NULL
)
SELECT
    basis,
    build_year,
    make,
    model,
    n_old,
    n_new,
    log_diff,
    mass_diff,
    power_diff,
    0.5 * (n_old / sum(n_old) OVER (PARTITION BY basis, build_year)
         + n_new / sum(n_new) OVER (PARTITION BY basis, build_year)) AS weight
FROM pairs;

-- The links aggregated to one number per year and basis.
CREATE OR REPLACE TABLE model_index_links AS
SELECT
    basis,
    build_year,
    count(*)                                               AS models,
    sum(n_new)                                             AS vehicles,
    round(sum(weight * log_diff), 6)                       AS log_link,
    round(100.0 * (exp(sum(weight * log_diff)) - 1), 3)    AS pct_change,
    -- What happened to the matched models themselves, which is what separates this
    -- index from the hedonic one: the same nameplate growing year on year.
    round(sum(weight * mass_diff), 2)                      AS mean_mass_change_kg,
    round(sum(weight * power_diff), 2)                     AS mean_power_change_kw
FROM model_links
GROUP BY basis, build_year
ORDER BY basis, build_year;

-- A fixed basket of nameplates present across essentially the whole period, as a
-- check that the chained index is not being driven by models entering and leaving.
CREATE OR REPLACE TABLE model_basket AS
WITH long_lived AS (
    SELECT make, model
    FROM model_year_cells
    WHERE n_nedc >= 50
    GROUP BY make, model
    HAVING count(*) >= 20 AND min(build_year) <= 2002 AND max(build_year) >= 2018
)
SELECT
    c.build_year,
    count(*)                                               AS models,
    sum(c.n_nedc)                                          AS vehicles,
    round(exp(sum(c.mean_log_nedc * c.n_nedc) / sum(c.n_nedc)), 4) AS mean_l_nedc,
    round(avg(c.mean_mass))                                AS mean_mass,
    round(avg(c.mean_power), 1)                            AS mean_power
FROM model_year_cells c
JOIN long_lived b ON b.make = c.make AND b.model = c.model
WHERE c.n_nedc >= 50
GROUP BY c.build_year
ORDER BY c.build_year;

-- The individual model histories behind the index, for anyone who wants to look at
-- a particular nameplate rather than the aggregate.
CREATE OR REPLACE TABLE model_histories AS
SELECT
    c.make,
    c.model,
    c.build_year,
    c.n,
    round(exp(c.mean_log_nedc), 3)                         AS l_100km_nedc,
    round(exp(c.mean_log_wltp), 3)                         AS l_100km_wltp,
    round(c.mean_mass)                                     AS mean_mass_kg,
    round(c.mean_power, 1)                                 AS mean_power_kw
FROM model_year_cells c
WHERE c.n >= 50
ORDER BY c.make, c.model, c.build_year;
