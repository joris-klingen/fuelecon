-- Step 060: fuel economy within a fixed kind of car.
--
-- The question this answers is the one a car owner actually asks: replace what I
-- drive with something five years newer and roughly the same size -- what do I
-- save? That needs the comparison held inside a segment, because the fleet-wide
-- trend mixes two different things: engines improving, and people buying
-- differently shaped cars.
--
-- SIZE IS PROXIED BY KERB MASS, and that is a deliberate choice over the obvious
-- alternative. RDW carries a length for only 53% of cars built before 2016 (98% by
-- 2024), and the missing half is not random: cars with a recorded length in 2010
-- average 1085 kg against 1208 kg for those without. Segmenting on length would
-- therefore compare a biased, lighter sample in the early years against a complete
-- one in the late years, and read the difference as progress. Kerb mass is
-- recorded for every car in every year.
--
-- The cost of that choice, stated plainly: equipment and safety mass creep means a
-- 1200 kg car in 2024 is a physically smaller car than a 1200 kg car in 2000, so
-- holding the mass band fixed compares a newer small car against an older larger
-- one and will somewhat *overstate* the saving. `segment_saving_length` below
-- repeats the calculation on true length bands over 2016-2024, where length
-- coverage is high, as a check on how much that matters.

CREATE OR REPLACE TABLE size_bands AS
SELECT * FROM (VALUES
    (1, 'small (under 950 kg)',      0,    950),
    (2, 'compact (950-1150 kg)',     950,  1150),
    (3, 'medium (1150-1350 kg)',     1150, 1350),
    (4, 'large (1350-1600 kg)',      1350, 1600),
    (5, 'very large (1600 kg+)',     1600, 100000)
) AS t(size_id, size_class, mass_min, mass_max);

-- One row per vehicle with a type and a size attached.
CREATE OR REPLACE TABLE vehicles_segment AS
SELECT
    r.kenteken,
    r.build_year,
    r.powertrain,
    r.kerb_mass_kg,
    r.l_100km_real,
    r.l_100km_wltp_equiv,
    r.wltp_basis,
    v.length_cm,
    s.size_id,
    s.size_class,
    -- Body types collapsed to the shapes a buyer would recognise. The remainder
    -- (campers, hearses, ambulances, wheelchair vehicles) are registered as
    -- passenger cars but are not what this question is about, so they are kept in
    -- the table under 'overig' and dropped from the figures.
    CASE v.body_type
        WHEN 'hatchback'    THEN 'hatchback'
        WHEN 'stationwagen' THEN 'estate'
        WHEN 'MPV'          THEN 'MPV'
        WHEN 'sedan'        THEN 'saloon'
        WHEN 'coupe'        THEN 'coupe/convertible'
        WHEN 'cabriolet'    THEN 'coupe/convertible'
        ELSE 'other'
    END                                                    AS car_type
FROM vehicles_real r
JOIN vehicles v USING (kenteken)
LEFT JOIN size_bands s
       ON r.kerb_mass_kg >= s.mass_min AND r.kerb_mass_kg < s.mass_max
WHERE r.powertrain NOT IN ('BEV', 'FCEV')   -- litres per 100 km must mean something
  AND r.l_100km_real IS NOT NULL
  AND r.kerb_mass_kg IS NOT NULL;

-- The series behind the headline figure: average on-road consumption per build
-- year, one row per car type.
CREATE OR REPLACE TABLE consumption_by_type AS
SELECT
    build_year,
    car_type,
    count(*)                                               AS vehicles,
    round(avg(l_100km_real), 3)                            AS mean_l_real,
    round(median(l_100km_real), 3)                         AS median_l_real,
    round(avg(l_100km_wltp_equiv), 3)                      AS mean_l_typeapproval,
    round(avg(kerb_mass_kg))                               AS mean_kerb_mass_kg
FROM vehicles_segment
WHERE car_type <> 'other'
GROUP BY build_year, car_type
HAVING count(*) >= 200
ORDER BY build_year, car_type;

-- The same by size class, which is the "same size specs" cut.
CREATE OR REPLACE TABLE consumption_by_size AS
SELECT
    build_year,
    size_id,
    size_class,
    count(*)                                               AS vehicles,
    round(avg(l_100km_real), 3)                            AS mean_l_real,
    round(median(l_100km_real), 3)                         AS median_l_real,
    round(avg(kerb_mass_kg))                               AS mean_kerb_mass_kg,
    -- Petrol only: the same series with the powertrain held fixed too, so that
    -- hybrids entering the segment cannot be mistaken for engine progress.
    round(avg(l_100km_real) FILTER (WHERE powertrain = 'Petrol'), 3) AS mean_l_petrol
FROM vehicles_segment
WHERE size_id IS NOT NULL
GROUP BY build_year, size_id, size_class
HAVING count(*) >= 200
ORDER BY build_year, size_id;

-- Type and size together: the cell the replacement question is actually asked in.
CREATE OR REPLACE TABLE consumption_by_segment AS
SELECT
    build_year,
    car_type,
    size_id,
    size_class,
    count(*)                                               AS vehicles,
    round(avg(l_100km_real), 3)                            AS mean_l_real,
    round(avg(kerb_mass_kg))                               AS mean_kerb_mass_kg,
    round(100.0 * count(*) FILTER (WHERE wltp_basis = 'measured') / count(*), 1)
                                                           AS pct_measured
FROM vehicles_segment
WHERE car_type <> 'other' AND size_id IS NOT NULL
GROUP BY build_year, car_type, size_id, size_class
HAVING count(*) >= 200
ORDER BY build_year, car_type, size_id;

-- Replace a car with one N years newer, same type and same size class.
--
-- `vehicles_new` weights each cell by how many of the *newer* car exist, which is
-- the right weight for "what would a buyer today experience": it is the mix of
-- cars actually available to move into, not the mix of cars being retired.
CREATE OR REPLACE TABLE segment_saving AS
SELECT
    n.build_year                                           AS year_new,
    o.build_year                                           AS year_old,
    n.build_year - o.build_year                            AS years_newer,
    n.car_type,
    n.size_id,
    n.size_class,
    o.vehicles                                             AS vehicles_old,
    n.vehicles                                             AS vehicles_new,
    o.mean_l_real                                          AS l_old,
    n.mean_l_real                                          AS l_new,
    round(o.mean_l_real - n.mean_l_real, 3)                AS saving_l_100km,
    round(100.0 * (o.mean_l_real - n.mean_l_real) / o.mean_l_real, 2) AS saving_pct,
    o.mean_kerb_mass_kg                                    AS mass_old,
    n.mean_kerb_mass_kg                                    AS mass_new,
    o.pct_measured                                         AS pct_measured_old,
    n.pct_measured                                         AS pct_measured_new
FROM consumption_by_segment n
JOIN consumption_by_segment o
  ON o.car_type = n.car_type
 AND o.size_id  = n.size_id
 AND o.build_year = n.build_year - 5
ORDER BY n.build_year, n.car_type, n.size_id;

-- The same saving aggregated to one number per year, weighted by the stock of the
-- newer car so that common segments count for more than rare ones.
CREATE OR REPLACE TABLE segment_saving_summary AS
SELECT
    year_new,
    year_old,
    sum(vehicles_new)                                      AS vehicles,
    round(sum(l_old * vehicles_new) / sum(vehicles_new), 3)       AS l_old_weighted,
    round(sum(l_new * vehicles_new) / sum(vehicles_new), 3)       AS l_new_weighted,
    round(sum(saving_l_100km * vehicles_new) / sum(vehicles_new), 3) AS saving_l_100km,
    round(100.0 * sum(saving_l_100km * vehicles_new)
          / sum(l_old * vehicles_new), 2)                  AS saving_pct,
    -- How much of each side was actually measured on WLTP rather than converted
    -- from NEDC. A comparison with a low share on either side inherits the
    -- assumed NEDC gap ramp and is a modelled result, not a measured one; only
    -- rows where both sides are near 100 are like-for-like measurements.
    round(sum(pct_measured_old * vehicles_new) / sum(vehicles_new), 1) AS pct_measured_old,
    round(sum(pct_measured_new * vehicles_new) / sum(vehicles_new), 1) AS pct_measured_new
FROM segment_saving
GROUP BY year_new, year_old
ORDER BY year_new;

-- Robustness: the same five-year saving computed on true length bands, restricted
-- to 2016-2024 where length is recorded for 78-98% of cars. If the mass-band
-- answer is inflated by mass creep, it should sit above this one.
CREATE OR REPLACE TABLE segment_saving_length AS
WITH len AS (
    SELECT
        build_year,
        car_type,
        CASE
            WHEN length_cm < 380 THEN '1 under 380 cm'
            WHEN length_cm < 420 THEN '2 380-420 cm'
            WHEN length_cm < 450 THEN '3 420-450 cm'
            WHEN length_cm < 480 THEN '4 450-480 cm'
            ELSE                      '5 480 cm and over'
        END                                                AS length_class,
        count(*)                                           AS vehicles,
        avg(l_100km_real)                                  AS mean_l_real
    FROM vehicles_segment
    WHERE car_type <> 'other'
      AND length_cm BETWEEN 250 AND 700
      AND build_year >= 2011
    GROUP BY ALL
    HAVING count(*) >= 200
)
SELECT
    n.build_year                                           AS year_new,
    n.car_type,
    n.length_class,
    n.vehicles                                             AS vehicles_new,
    round(o.mean_l_real, 3)                                AS l_old,
    round(n.mean_l_real, 3)                                AS l_new,
    round(o.mean_l_real - n.mean_l_real, 3)                AS saving_l_100km,
    round(100.0 * (o.mean_l_real - n.mean_l_real) / o.mean_l_real, 2) AS saving_pct
FROM len n
JOIN len o
  ON o.car_type = n.car_type
 AND o.length_class = n.length_class
 AND o.build_year = n.build_year - 5
WHERE n.build_year >= 2016
ORDER BY n.build_year, n.car_type, n.length_class;

-- Fleet consumption reweighted to the 2000 composition of type and size.
--
-- The fleet average falls partly because engines improved and partly because the
-- mix of cars changed. Holding the segment weights at their 2000 values isolates
-- the first: this is what the fleet would consume if people had gone on buying the
-- same kinds of cars in the same proportions.
CREATE OR REPLACE TABLE fixed_weight_index AS
WITH w2000 AS (
    SELECT car_type, size_id, vehicles AS w
    FROM consumption_by_segment
    WHERE build_year = 2000
),
actual AS (
    SELECT build_year,
           sum(mean_l_real * vehicles) / sum(vehicles)     AS l_actual
    FROM consumption_by_segment
    GROUP BY build_year
)
SELECT
    c.build_year,
    round(sum(c.mean_l_real * w.w) / sum(w.w), 3)          AS l_fixed_weight_2000,
    round(a.l_actual, 3)                                   AS l_actual,
    round(sum(c.mean_l_real * w.w) / sum(w.w) - a.l_actual, 3) AS mix_effect,
    sum(c.vehicles)                                        AS vehicles
FROM consumption_by_segment c
JOIN w2000 w ON w.car_type = c.car_type AND w.size_id = c.size_id
JOIN actual a ON a.build_year = c.build_year
GROUP BY c.build_year, a.l_actual
ORDER BY c.build_year;

-- Is the V-shape in the five-year saving an artefact of the corrections?
--
-- The question is a fair one, because two modelling steps sit between the registry
-- and that curve. This table recomputes the identical saving on three bases so the
-- answer can be read off rather than argued:
--
--   saving_realworld     cycle-converted and gap-corrected (the headline)
--   saving_typeapproval  cycle-converted, no real-world gap
--   saving_raw_nedc      the untouched NEDC declarations, no correction at all
--
-- Note first that the cycle-conversion factor from 040 cannot be the culprit: for
-- NEDC-era cars sql/050 builds the on-road figure from the raw NEDC value times
-- that year's gap, never via the WLTP-equivalent. Only the gap ramp enters.
--
-- `pct_with_nedc_new` is essential to reading the last column. NEDC declarations
-- are near-universal up to 2019 and then collapse (5.9% of 2024 cars), and the
-- residue is self-selected toward long-running type approvals. The raw column is
-- informative up to year_new 2020 and should not be read after it.
CREATE OR REPLACE TABLE segment_saving_basis AS
WITH seg AS (
    SELECT s.build_year, s.car_type, s.size_id,
           count(*)                                        AS n,
           count(v.l_100km_nedc)                           AS n_nedc,
           avg(s.l_100km_real)                             AS l_real,
           avg(s.l_100km_wltp_equiv)                       AS l_ta,
           avg(v.l_100km_nedc)                             AS l_nedc
    FROM vehicles_segment s
    JOIN vehicles v USING (kenteken)
    WHERE s.car_type <> 'other' AND s.size_id IS NOT NULL
    GROUP BY ALL
    HAVING count(*) >= 200
)
SELECT
    n.build_year                                           AS year_new,
    n.build_year - 5                                       AS year_old,
    sum(n.n)                                               AS vehicles,
    round(sum((o.l_real  - n.l_real)  * n.n) / sum(n.n), 3) AS saving_realworld,
    round(sum((o.l_ta    - n.l_ta)    * n.n) / sum(n.n), 3) AS saving_typeapproval,
    round(sum((o.l_nedc  - n.l_nedc)  * n.n) / sum(n.n), 3) AS saving_raw_nedc,
    round(100.0 * sum(n.n_nedc) / sum(n.n), 1)             AS pct_with_nedc_new,
    round(100.0 * sum(o.n_nedc) / sum(o.n), 1)             AS pct_with_nedc_old
FROM seg n
JOIN seg o
  ON o.car_type = n.car_type AND o.size_id = n.size_id
 AND o.build_year = n.build_year - 5
GROUP BY n.build_year
ORDER BY n.build_year;
