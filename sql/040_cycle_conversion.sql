-- Step 040: put the whole 2000-2024 window on one measurement cycle.
--
-- The NEDC -> WLTP switch splits the series in two, and the usual fix is a
-- published scalar (CO2MPAS, or a flat ~1.2). This dataset makes that unnecessary.
-- Over the 2018-2024 transition RDW carries *both* declarations on the same
-- vehicle record for 1.41M cars, so the conversion can be estimated from paired
-- within-vehicle observations: the same car, measured both ways. That is a
-- stronger identification than any borrowed table, because nothing has to be
-- assumed about which cars the ratio was calibrated on.
--
-- What is still an assumption, and cannot be avoided: the relationship is
-- estimated on cars built 2018-2024 and applied backwards to cars built from 2000,
-- which were never WLTP tested. A 2003 car converted this way is an estimate of
-- what WLTP would have said, not a measurement.

-- Mass bands for the conversion. Coarse on purpose: fine bands buy precision that
-- the backward extrapolation cannot honour anyway.
CREATE OR REPLACE TABLE mass_bands AS
SELECT * FROM (VALUES
    (1, 'tot 1100 kg',    0,    1100),
    (2, '1100-1300 kg',   1100, 1300),
    (3, '1300-1500 kg',   1300, 1500),
    (4, '1500-1800 kg',   1500, 1800),
    (5, '1800 kg en meer',1800, 100000)
) AS t(band_id, band_label, mass_min, mass_max);

-- The paired sample: cars declaring both cycles.
--
-- Two exclusions matter. Rows where the two figures are byte-identical are not
-- dual declarations, they are the same number copied into both fields (this is
-- what produces the spurious ratio of exactly 1.000 in every pre-2018 vintage).
-- And ratios outside 0.9-1.7 are data errors rather than cars: the physical range
-- of the cycle penalty is nowhere near that wide.
CREATE OR REPLACE TABLE cycle_pairs AS
SELECT
    v.kenteken,
    v.build_year,
    v.powertrain,
    v.kerb_mass_kg,
    b.band_id,
    b.band_label,
    v.co2_nedc,
    v.co2_wltp,
    v.l_100km_nedc                                          AS l_nedc,
    coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp)       AS l_wltp,
    v.co2_wltp / v.co2_nedc                                 AS ratio_co2
FROM vehicles v
LEFT JOIN mass_bands b
       ON v.kerb_mass_kg >= b.mass_min AND v.kerb_mass_kg < b.mass_max
WHERE v.co2_nedc IS NOT NULL
  AND v.co2_wltp IS NOT NULL
  AND v.co2_wltp <> v.co2_nedc            -- copied field, not a second measurement
  AND v.co2_wltp / v.co2_nedc BETWEEN 0.9 AND 1.7;

-- Conversion factors by powertrain and mass band, with the coarser fallbacks that
-- thin cells fall back to.
CREATE OR REPLACE TABLE cycle_conversion AS
WITH cell AS (
    SELECT powertrain, band_id, band_label,
           count(*)                                    AS n,
           median(ratio_co2)                           AS ratio_co2,
           quantile_cont(ratio_co2, 0.25)              AS p25,
           quantile_cont(ratio_co2, 0.75)              AS p75,
           median(l_wltp / l_nedc) FILTER (
               WHERE l_nedc > 0 AND l_wltp > 0 AND l_wltp <> l_nedc
           )                                           AS ratio_l
    FROM cycle_pairs
    WHERE band_id IS NOT NULL
    GROUP BY ALL
),
by_powertrain AS (
    SELECT powertrain, count(*) AS n, median(ratio_co2) AS ratio_co2,
           median(l_wltp / l_nedc) FILTER (
               WHERE l_nedc > 0 AND l_wltp > 0 AND l_wltp <> l_nedc
           ) AS ratio_l
    FROM cycle_pairs GROUP BY 1
),
overall AS (
    SELECT median(ratio_co2) AS ratio_co2,
           median(l_wltp / l_nedc) FILTER (
               WHERE l_nedc > 0 AND l_wltp > 0 AND l_wltp <> l_nedc
           ) AS ratio_l
    FROM cycle_pairs
)
SELECT
    c.powertrain,
    c.band_id,
    c.band_label,
    c.n,
    round(c.ratio_co2, 4)                              AS ratio_co2_cell,
    round(c.ratio_l, 4)                                AS ratio_l_cell,
    round(c.p25, 4)                                    AS p25_co2,
    round(c.p75, 4)                                    AS p75_co2,
    -- The factor actually applied: the cell when it is well populated, otherwise
    -- the powertrain median, otherwise the pooled median.
    round(CASE WHEN c.n >= 100 THEN c.ratio_co2
               WHEN p.n >= 100 THEN p.ratio_co2
               ELSE o.ratio_co2 END, 4)                AS ratio_co2_applied,
    round(coalesce(CASE WHEN c.n >= 100 THEN c.ratio_l END, p.ratio_l, o.ratio_l), 4)
                                                       AS ratio_l_applied,
    CASE WHEN c.n >= 100 THEN 'cell'
         WHEN p.n >= 100 THEN 'powertrain'
         ELSE 'pooled' END                             AS factor_source
FROM cell c
LEFT JOIN by_powertrain p USING (powertrain)
CROSS JOIN overall o
ORDER BY c.powertrain, c.band_id;

-- One row per vehicle carrying a WLTP-equivalent figure: the measured WLTP value
-- where one exists, the converted NEDC value where it does not.
CREATE OR REPLACE TABLE vehicles_wltp AS
SELECT
    v.kenteken,
    v.build_year,
    v.powertrain,
    v.combustion_fuel,
    v.kerb_mass_kg,
    v.test_cycle,
    b.band_id,
    coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp)  AS l_wltp_measured,
    v.l_100km_nedc,
    v.co2_wltp,
    v.co2_nedc,

    CASE
        WHEN coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp) IS NOT NULL
            THEN coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp)
        WHEN v.l_100km_nedc IS NOT NULL
            THEN v.l_100km_nedc * coalesce(cc.ratio_l_applied, 1.20)
    END                                                AS l_100km_wltp_equiv,

    CASE
        WHEN v.co2_wltp IS NOT NULL THEN v.co2_wltp
        WHEN v.co2_nedc IS NOT NULL
            THEN v.co2_nedc * coalesce(cc.ratio_co2_applied, 1.20)
    END                                                AS co2_wltp_equiv,

    -- Whether the figure above was measured on WLTP or converted from NEDC, so
    -- every downstream series can report how much of it is estimated.
    CASE
        WHEN coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp) IS NOT NULL
             OR v.co2_wltp IS NOT NULL THEN 'measured'
        WHEN v.l_100km_nedc IS NOT NULL OR v.co2_nedc IS NOT NULL THEN 'converted'
        ELSE 'none'
    END                                                AS wltp_basis
FROM vehicles v
LEFT JOIN mass_bands b
       ON v.kerb_mass_kg >= b.mass_min AND v.kerb_mass_kg < b.mass_max
LEFT JOIN cycle_conversion cc
       ON cc.powertrain = v.powertrain AND cc.band_id = b.band_id;
