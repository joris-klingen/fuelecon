-- Step 060: energy per kilometre for one car, long by energy carrier.
--
-- WHAT THIS IS FOR. Steps 020-050 answer "how did the fleet change". This one
-- answers "what does this particular car use", which is the object a per-switch
-- study needs: the cost of driving a kilometre is
--
--     sum over carriers of  (energy per km) x (price per unit)
--
-- and the difference between two cars is the difference of two such sums. Long by
-- carrier is what makes that a join against a price series rather than a rewrite
-- of the arithmetic for every powertrain combination.
--
-- WHAT IT DOES NOT DO. It does not apply the constant-mass counterfactual from
-- step 050. That correction answers a fleet question -- what would a vintage have
-- consumed had cars not grown -- and holding a specific car at a mass it never had
-- is not a statement about what it costs its owner to drive.
--
-- A WARNING ABOUT THE ON-ROAD COLUMN. `energy_per_100km_onroad` applies the
-- corrections from step 050, which are constant within powertrain (WLTP era) or
-- within build year (NEDC era). That is the right resolution for a fleet average
-- and the wrong one for a difference between two cars: for a petrol-to-electric
-- switch the correction is a deterministic function of the powertrains, so it
-- adds nothing a powertrain dummy would not, and it will look like signal.
-- `energy_per_100km_typeapproval` varies car by car and is the safer default; the
-- on-road column is here to be compared against, and to be replaced when a
-- per-vehicle measurement (OBFCM) or a per-model series can be obtained.

-- ---------------------------------------------------------------------------
-- Resolve one figure per car, recording where it came from.
--
-- Four sources in preference order, best first:
--   wltp_plate     WLTP declaration on the licence plate
--   wltp_variant   WLTP declaration on the type-approval version
--   nedc_plate     NEDC declaration on the licence plate
--   nedc_variant   NEDC declaration on the type-approval version
--
-- The variant sources are what the type-approval join buys: they fill plates whose
-- own fuel record is blank, which is most of the ~10% gap in the early vintages.
-- Where a version quotes a range, its midpoint is taken and both bounds are kept.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE vehicle_energy_wide AS
WITH src AS (
    SELECT
        v.kenteken,
        v.build_year,
        v.powertrain,
        v.combustion_fuel,
        v.kerb_mass_kg,
        v.ev_range_km,
        coalesce(v.ev_range_ovc_km, v.ev_range_ovc_nedc_km, m.ev_range_ovc_wltp,
                 m.ev_range_ovc_nedc)                       AS ev_range_ovc_km,
        b.band_id,

        -- Litres per 100 km, by source. The weighted figure comes first in each
        -- pair: for a plug-in hybrid it is the certified one, and for everything
        -- else it is null and coalesces away.
        coalesce(v.l_100km_wltp_weighted, v.l_100km_wltp)    AS l_wltp_plate,
        coalesce((m.l_wltp_weighted_lo + m.l_wltp_weighted_hi) / 2,
                 (m.l_wltp_lo + m.l_wltp_hi) / 2)            AS l_wltp_variant,
        coalesce(v.l_100km_nedc_weighted, v.l_100km_nedc)    AS l_nedc_plate,
        coalesce((m.l_nedc_weighted_lo + m.l_nedc_weighted_hi) / 2,
                 (m.l_nedc_lo + m.l_nedc_hi) / 2)            AS l_nedc_variant,
        coalesce(m.l_wltp_weighted_lo, m.l_wltp_lo)          AS l_wltp_variant_lo,
        coalesce(m.l_wltp_weighted_hi, m.l_wltp_hi)          AS l_wltp_variant_hi,

        -- kWh per 100 km. A plug-in hybrid's externally charged figure and a
        -- battery car's are different quantities and are not coalesced together
        -- across powertrains: which one applies is decided by powertrain here.
        -- The plug-in takes "extern opladen", the figure that already carries the
        -- utility factor, because it is the one that pairs with the weighted litres
        -- chosen above. Its pure-electric figure describes only the kilometres it
        -- drives on the battery and would double-count against them.
        CASE WHEN v.powertrain = 'PHEV'
             THEN coalesce(v.kwh_100km_ovc_wltp, v.kwh_100km)
             ELSE v.kwh_100km
        END                                                  AS kwh_wltp_plate,
        CASE WHEN v.powertrain = 'PHEV'
             THEN (m.kwh_wltp_ovc_lo + m.kwh_wltp_ovc_hi) / 2
             ELSE (m.kwh_wltp_bev_lo + m.kwh_wltp_bev_hi) / 2
        END                                                  AS kwh_wltp_variant,
        CASE WHEN v.powertrain = 'PHEV' THEN v.kwh_100km_nedc_weighted END AS kwh_nedc_plate,
        CASE WHEN v.powertrain = 'PHEV' THEN m.kwh_nedc_weighted ELSE m.kwh_nedc END
                                                             AS kwh_nedc_variant,
        CASE WHEN v.powertrain = 'PHEV' THEN m.kwh_wltp_ovc_lo ELSE m.kwh_wltp_bev_lo END
                                                             AS kwh_wltp_variant_lo,
        CASE WHEN v.powertrain = 'PHEV' THEN m.kwh_wltp_ovc_hi ELSE m.kwh_wltp_bev_hi END
                                                             AS kwh_wltp_variant_hi,

        -- Carried through for the physical work the corrections stand in for.
        m.co2_nedc_urban_hi,
        m.co2_nedc_extra_urban_hi,
        m.road_load_f0_hi,
        m.road_load_f1_hi,
        m.road_load_f2_hi,
        m.gearbox_type,
        m.gears,
        m.engine_code,
        m.is_plug_in                                         AS approval_says_plug_in,
        m.match_quality
    FROM vehicles v
    LEFT JOIN vehicle_variant m USING (kenteken)
    LEFT JOIN mass_bands b
           ON v.kerb_mass_kg >= b.mass_min AND v.kerb_mass_kg < b.mass_max
),
picked AS (
    SELECT
        *,
        coalesce(l_wltp_plate, l_wltp_variant, l_nedc_plate, l_nedc_variant) AS l_raw,
        CASE
            WHEN l_wltp_plate   IS NOT NULL THEN 'wltp_plate'
            WHEN l_wltp_variant IS NOT NULL THEN 'wltp_variant'
            WHEN l_nedc_plate   IS NOT NULL THEN 'nedc_plate'
            WHEN l_nedc_variant IS NOT NULL THEN 'nedc_variant'
        END                                                  AS l_basis,
        coalesce(kwh_wltp_plate, kwh_wltp_variant, kwh_nedc_plate, kwh_nedc_variant) AS kwh_raw,
        CASE
            WHEN kwh_wltp_plate   IS NOT NULL THEN 'wltp_plate'
            WHEN kwh_wltp_variant IS NOT NULL THEN 'wltp_variant'
            WHEN kwh_nedc_plate   IS NOT NULL THEN 'nedc_plate'
            WHEN kwh_nedc_variant IS NOT NULL THEN 'nedc_variant'
        END                                                  AS kwh_basis
    FROM src
)
SELECT
    p.*,

    -- On one cycle. A figure that came from NEDC is multiplied by the factor
    -- estimated in step 040 for its powertrain and mass band; a WLTP figure is
    -- already there. Same rule, same factors, as vehicles_wltp.
    CASE
        WHEN p.l_basis IN ('wltp_plate', 'wltp_variant') THEN p.l_raw
        WHEN p.l_basis IN ('nedc_plate', 'nedc_variant')
            THEN p.l_raw * coalesce(cc.ratio_l_applied, 1.20)
    END                                                      AS l_100km_wltp_equiv,

    -- On the road. Mirrors step 050 exactly: a plug-in hybrid always takes the
    -- WLTP-era factor because its divergence is about how often it is plugged in
    -- rather than which laboratory measured it; anything else converted from NEDC
    -- is corrected off its own NEDC figure with that build year's gap.
    CASE
        WHEN p.powertrain IN ('BEV', 'FCEV') THEN NULL
        WHEN p.powertrain = 'PHEV' OR p.l_basis IN ('wltp_plate', 'wltp_variant')
            THEN CASE WHEN p.l_basis IN ('wltp_plate', 'wltp_variant')
                      THEN p.l_raw * (1 + gw.gap)
                      ELSE p.l_raw * coalesce(cc.ratio_l_applied, 1.20) * (1 + gw.gap) END
        ELSE p.l_raw * (1 + gn.gap)
    END                                                      AS l_100km_onroad,
    CASE
        WHEN p.powertrain IN ('BEV', 'FCEV') THEN NULL
        WHEN p.powertrain = 'PHEV' OR p.l_basis IN ('wltp_plate', 'wltp_variant') THEN gw.gap
        WHEN p.l_basis IS NOT NULL THEN gn.gap
    END                                                      AS l_gap_applied,

    -- How wide the version's own declaration is, as a share of its midpoint. A car
    -- whose approval spans 5.2 to 6.4 l/100 km is being described by one number on
    -- its licence plate, and this says by how much.
    round(100.0 * (p.l_wltp_variant_hi - p.l_wltp_variant_lo)
          / nullif((p.l_wltp_variant_hi + p.l_wltp_variant_lo) / 2, 0), 2) AS l_spread_pct,
    round(100.0 * (p.kwh_wltp_variant_hi - p.kwh_wltp_variant_lo)
          / nullif((p.kwh_wltp_variant_hi + p.kwh_wltp_variant_lo) / 2, 0), 2) AS kwh_spread_pct,

    -- The NEDC phase split as a ratio. Above 1 means the car is relatively worse in
    -- town, which is where a short-trip household drives it.
    round(p.co2_nedc_urban_hi / nullif(p.co2_nedc_extra_urban_hi, 0), 4) AS urban_penalty_nedc
FROM picked p
LEFT JOIN cycle_conversion cc
       ON cc.powertrain = p.powertrain AND cc.band_id = p.band_id
LEFT JOIN realworld_gap_wltp gw ON gw.powertrain = p.powertrain
LEFT JOIN realworld_gap_nedc gn ON gn.build_year = p.build_year;

-- ---------------------------------------------------------------------------
-- One row per car per carrier it can draw energy from.
--
-- Rows are emitted for every carrier the car actually uses, including where the
-- figure is missing, so that a join against a price series shows a null cost
-- rather than silently dropping the car. `basis` says how much to trust it.
--
-- Electricity carries no on-road correction. There is a real gap between a battery
-- car's WLTP figure and what it draws in Dutch conditions, but this repository has
-- no sourced series for it, and inventing one here would put a fabricated number
-- on exactly the side of the switch the research is about.
--
-- Nor is electricity put on one cycle. The factors in step 040 are estimated from
-- paired CO2 declarations and say nothing about kilowatt hours, so an NEDC-era
-- electric figure is left as it was measured and `cycle` says which it is. Read
-- that column before comparing a 2015 battery car with a 2022 one.
--
-- The CNG unit is RDW's own and is not consistent across the cycle switch; CNG is
-- well under a tenth of a per cent of these vintages, so it is carried rather than
-- resolved. Check it before pricing those rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE vehicle_energy AS
SELECT
    kenteken,
    build_year,
    powertrain,
    lower(combustion_fuel)                                   AS carrier,
    CASE WHEN combustion_fuel = 'CNG' THEN 'kg/100km' ELSE 'l/100km' END AS unit,
    round(l_100km_wltp_equiv, 4)                             AS energy_per_100km_typeapproval,
    round(l_100km_onroad, 4)                                 AS energy_per_100km_onroad,
    round(l_wltp_variant_lo, 4)                              AS declared_lo,
    round(l_wltp_variant_hi, 4)                              AS declared_hi,
    l_spread_pct                                             AS spread_pct,
    coalesce(l_basis, 'none')                                AS basis,
    CASE WHEN l_basis LIKE 'wltp%' THEN 'WLTP'
         WHEN l_basis LIKE 'nedc%' THEN 'NEDC' END           AS cycle,
    l_gap_applied                                            AS gap_applied
FROM vehicle_energy_wide
WHERE combustion_fuel IS NOT NULL

UNION ALL

SELECT
    kenteken,
    build_year,
    powertrain,
    'electricity'                                            AS carrier,
    'kWh/100km'                                              AS unit,
    round(kwh_raw, 4)                                        AS energy_per_100km_typeapproval,
    NULL                                                     AS energy_per_100km_onroad,
    round(kwh_wltp_variant_lo, 4)                            AS declared_lo,
    round(kwh_wltp_variant_hi, 4)                            AS declared_hi,
    kwh_spread_pct                                           AS spread_pct,
    coalesce(kwh_basis, 'none')                              AS basis,
    CASE WHEN kwh_basis LIKE 'wltp%' THEN 'WLTP'
         WHEN kwh_basis LIKE 'nedc%' THEN 'NEDC' END         AS cycle,
    NULL                                                     AS gap_applied
FROM vehicle_energy_wide
WHERE powertrain IN ('BEV', 'PHEV');

-- ---------------------------------------------------------------------------
-- How much of each vintage carries a usable per-car figure, and from where.
--
-- This is the table to read before using any of the above: it says what share of a
-- build year rests on the car's own WLTP declaration and what share on a
-- type-approval fallback or an NEDC conversion.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE energy_coverage_by_year AS
SELECT
    build_year,
    carrier,
    count(*)                                                 AS vehicles,
    round(100.0 * count(*) FILTER (WHERE basis = 'wltp_plate')   / count(*), 1) AS pct_wltp_plate,
    round(100.0 * count(*) FILTER (WHERE basis = 'wltp_variant') / count(*), 1) AS pct_wltp_variant,
    round(100.0 * count(*) FILTER (WHERE basis = 'nedc_plate')   / count(*), 1) AS pct_nedc_plate,
    round(100.0 * count(*) FILTER (WHERE basis = 'nedc_variant') / count(*), 1) AS pct_nedc_variant,
    round(100.0 * count(*) FILTER (WHERE basis = 'none')         / count(*), 1) AS pct_missing,
    -- What the type-approval join added: cars that would have had nothing without it.
    round(100.0 * count(*) FILTER (WHERE basis LIKE '%_variant') / count(*), 1) AS pct_from_variant,
    round(median(energy_per_100km_typeapproval), 3)          AS median_energy,
    round(median(spread_pct), 2)                             AS median_spread_pct
FROM vehicle_energy
GROUP BY build_year, carrier
HAVING count(*) >= 100
ORDER BY build_year, carrier;
