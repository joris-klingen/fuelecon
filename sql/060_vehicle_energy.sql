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
-- WHY CARRIERS COME FROM THE FUEL ROWS. RDW records one row per fuel a car can
-- run on, each with its own consumption. 25,493 of the 57,534 LPG cars here
-- declare different figures for petrol and for LPG -- one reads 6.80 on gas and
-- 5.10 on petrol. Reducing that to one figure per car picks whichever is larger
-- and then labels it with whichever fuel the classifier happened to prefer, so the
-- car gets one carrier, the wrong number, and the wrong price. The grain here is
-- therefore the fuel row, not the car.
--
-- WHAT THIS DOES NOT DO. It does not apply the constant-mass counterfactual from
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
-- The declarations on the licence plate, one row per car per carrier.
--
-- Figures are taken from that carrier's own fuel rows. Where a carrier's rows are
-- blank, the car-level maximum stands in: RDW sometimes writes a single set of
-- figures onto the first fuel row only, and falling back keeps those cars rather
-- than dropping them for a bookkeeping choice made at registration.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE vehicle_fuel AS
WITH rows_by_carrier AS (
    SELECT
        kenteken,
        CASE trim(brandstof_omschrijving)
            WHEN 'Benzine'       THEN 'petrol'
            WHEN 'Alcohol'       THEN 'petrol'   -- ethanol blends, pumped as petrol
            WHEN 'Diesel'        THEN 'diesel'
            WHEN 'LPG'           THEN 'lpg'
            WHEN 'CNG'           THEN 'cng'
            WHEN 'LNG'           THEN 'lng'
            WHEN 'Elektriciteit' THEN 'electricity'
            WHEN 'Waterstof'     THEN 'hydrogen'
        END                                                          AS carrier,
        TRY_CAST(brandstofverbruik_gecombineerd AS DOUBLE)           AS l_nedc,
        TRY_CAST(brandstofverbruik_gewogen_gecombineerd AS DOUBLE)   AS l_nedc_weighted,
        TRY_CAST(brandstof_verbruik_gecombineerd_wltp AS DOUBLE)     AS l_wltp,
        TRY_CAST(brandstof_verbruik_gewogen_gecombineerd_wltp AS DOUBLE) AS l_wltp_weighted
    FROM raw_fuel
),
per_carrier AS (
    SELECT kenteken, carrier,
           max(l_nedc) AS l_nedc, max(l_nedc_weighted) AS l_nedc_weighted,
           max(l_wltp) AS l_wltp, max(l_wltp_weighted) AS l_wltp_weighted
    FROM rows_by_carrier WHERE carrier IS NOT NULL GROUP BY 1, 2
),
per_vehicle AS (
    SELECT kenteken,
           max(l_nedc) AS l_nedc, max(l_nedc_weighted) AS l_nedc_weighted,
           max(l_wltp) AS l_wltp, max(l_wltp_weighted) AS l_wltp_weighted
    FROM rows_by_carrier GROUP BY 1
)
SELECT
    c.kenteken,
    c.carrier,
    coalesce(c.l_nedc,          v.l_nedc)          AS l_nedc,
    coalesce(c.l_nedc_weighted, v.l_nedc_weighted) AS l_nedc_weighted,
    coalesce(c.l_wltp,          v.l_wltp)          AS l_wltp,
    coalesce(c.l_wltp_weighted, v.l_wltp_weighted) AS l_wltp_weighted
FROM per_carrier c
JOIN per_vehicle v USING (kenteken);

-- ---------------------------------------------------------------------------
-- One row per car per carrier, with the figure resolved and its provenance.
--
-- Four sources in preference order, best first:
--   wltp_plate     WLTP declaration on the licence plate
--   wltp_variant   WLTP declaration on the type-approval version
--   nedc_plate     NEDC declaration on the licence plate, converted
--   nedc_variant   NEDC declaration on the version, converted
--
-- The variant sources are what the type-approval join buys: they fill plates whose
-- own fuel record is blank. Where a version quotes a range, its midpoint is taken
-- and both bounds are kept.
--
-- Combustion and electricity are resolved separately, because for a plug-in hybrid
-- the two are not the same kind of number. Its litres are the utility-factor
-- weighted figure, so its kilowatt hours must be the weighted one too ("extern
-- opladen"); the pure-electric figure describes only the kilometres it drives on
-- the battery and would double-count against them.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE vehicle_energy AS
WITH base AS (
    SELECT
        v.kenteken,
        v.build_year,
        v.powertrain,
        f.carrier,
        b.band_id,
        f.carrier = 'electricity'                            AS is_electric,

        -- Litres. The weighted figure comes first in each pair: for a plug-in
        -- hybrid it is the certified one, and for everything else it is null.
        coalesce(f.l_wltp_weighted, f.l_wltp)                AS plate_wltp,
        coalesce(f.l_nedc_weighted, f.l_nedc)                AS plate_nedc,
        coalesce((e.l_wltp_weighted_lo + e.l_wltp_weighted_hi) / 2,
                 (e.l_wltp_lo + e.l_wltp_hi) / 2)            AS variant_wltp,
        coalesce((e.l_nedc_weighted_lo + e.l_nedc_weighted_hi) / 2,
                 (e.l_nedc_lo + e.l_nedc_hi) / 2)            AS variant_nedc,
        coalesce(e.l_wltp_weighted_lo, e.l_wltp_lo)          AS variant_lo,
        coalesce(e.l_wltp_weighted_hi, e.l_wltp_hi)          AS variant_hi,

        -- Kilowatt hours, already in kWh/100 km on both sides.
        CASE WHEN v.powertrain = 'PHEV'
             THEN coalesce(v.kwh_100km_ovc_wltp, v.kwh_100km)
             ELSE v.kwh_100km END                            AS plate_wltp_kwh,
        CASE WHEN v.powertrain = 'PHEV' THEN v.kwh_100km_nedc_weighted END AS plate_nedc_kwh,
        CASE WHEN v.powertrain = 'PHEV'
             THEN (e.kwh_wltp_ovc_lo + e.kwh_wltp_ovc_hi) / 2
             ELSE (e.kwh_wltp_bev_lo + e.kwh_wltp_bev_hi) / 2 END AS variant_wltp_kwh,
        CASE WHEN v.powertrain = 'PHEV' THEN e.kwh_nedc_weighted ELSE e.kwh_nedc END
                                                             AS variant_nedc_kwh,
        CASE WHEN v.powertrain = 'PHEV' THEN e.kwh_wltp_ovc_lo ELSE e.kwh_wltp_bev_lo END
                                                             AS variant_lo_kwh,
        CASE WHEN v.powertrain = 'PHEV' THEN e.kwh_wltp_ovc_hi ELSE e.kwh_wltp_bev_hi END
                                                             AS variant_hi_kwh
    FROM vehicles v
    JOIN vehicle_fuel f USING (kenteken)
    LEFT JOIN vehicle_variant_energy e ON e.kenteken = v.kenteken AND e.carrier = f.carrier
    LEFT JOIN mass_bands b
           ON v.kerb_mass_kg >= b.mass_min AND v.kerb_mass_kg < b.mass_max
    -- A self-charging hybrid carries an Elektriciteit fuel row because it has a
    -- battery, but it cannot be plugged in: every kilowatt hour it uses was made
    -- on board out of petrol it has already been charged for. Pricing that row
    -- would bill the same energy twice, so only externally chargeable cars get an
    -- electricity carrier. (It is empty in any case -- of the 774,904 rows this
    -- drops, essentially none carried a figure.)
    WHERE f.carrier <> 'electricity' OR v.powertrain IN ('BEV', 'PHEV')
),
resolved AS (
    SELECT
        kenteken, build_year, powertrain, carrier, band_id, is_electric,
        CASE WHEN is_electric THEN plate_wltp_kwh   ELSE plate_wltp   END AS v_wltp_plate,
        CASE WHEN is_electric THEN variant_wltp_kwh ELSE variant_wltp END AS v_wltp_variant,
        CASE WHEN is_electric THEN plate_nedc_kwh   ELSE plate_nedc   END AS v_nedc_plate,
        CASE WHEN is_electric THEN variant_nedc_kwh ELSE variant_nedc END AS v_nedc_variant,
        CASE WHEN is_electric THEN variant_lo_kwh   ELSE variant_lo   END AS declared_lo,
        CASE WHEN is_electric THEN variant_hi_kwh   ELSE variant_hi   END AS declared_hi
    FROM base
),
picked AS (
    SELECT
        *,
        coalesce(v_wltp_plate, v_wltp_variant, v_nedc_plate, v_nedc_variant) AS raw_value,
        CASE
            WHEN v_wltp_plate   IS NOT NULL THEN 'wltp_plate'
            WHEN v_wltp_variant IS NOT NULL THEN 'wltp_variant'
            WHEN v_nedc_plate   IS NOT NULL THEN 'nedc_plate'
            WHEN v_nedc_variant IS NOT NULL THEN 'nedc_variant'
        END                                                  AS basis
    FROM resolved
)
SELECT
    p.kenteken,
    p.build_year,
    p.powertrain,
    p.carrier,
    CASE p.carrier WHEN 'electricity' THEN 'kWh/100km'
                   WHEN 'cng' THEN 'kg/100km'
                   WHEN 'lng' THEN 'kg/100km'
                   WHEN 'hydrogen' THEN 'kg/100km'
                   ELSE 'l/100km' END                        AS unit,

    -- On one cycle. A figure that came from NEDC is multiplied by the factor
    -- estimated in step 040 for its powertrain and mass band; a WLTP figure is
    -- already there. Electricity is left alone: those factors are estimated from
    -- paired CO2 declarations and say nothing about kilowatt hours, so `cycle`
    -- records which cycle an electric figure came from instead of converting it.
    round(CASE
        WHEN p.basis IN ('wltp_plate', 'wltp_variant') OR p.is_electric THEN p.raw_value
        ELSE p.raw_value * coalesce(cc.ratio_l_applied, 1.20)
    END, 4)                                                  AS energy_per_100km_typeapproval,

    -- On the road. Mirrors step 050 exactly: a plug-in hybrid always takes the
    -- WLTP-era factor because its divergence is about how often it is plugged in
    -- rather than which laboratory measured it; anything else converted from NEDC
    -- is corrected off its own NEDC figure with that build year's gap.
    round(CASE
        WHEN p.is_electric THEN NULL
        WHEN p.basis IN ('wltp_plate', 'wltp_variant') THEN p.raw_value * (1 + gw.gap)
        WHEN p.powertrain = 'PHEV'
            THEN p.raw_value * coalesce(cc.ratio_l_applied, 1.20) * (1 + gw.gap)
        ELSE p.raw_value * (1 + gn.gap)
    END, 4)                                                  AS energy_per_100km_onroad,

    round(p.declared_lo, 4)                                  AS declared_lo,
    round(p.declared_hi, 4)                                  AS declared_hi,
    -- How wide the version's own declaration is, as a share of its midpoint. A car
    -- whose approval spans 5.2 to 6.4 l/100 km is being described by one number on
    -- its licence plate, and this says by how much.
    round(100.0 * (p.declared_hi - p.declared_lo)
          / nullif((p.declared_hi + p.declared_lo) / 2, 0), 2) AS spread_pct,

    coalesce(p.basis, 'none')                                AS basis,
    CASE WHEN p.basis LIKE 'wltp%' THEN 'WLTP'
         WHEN p.basis LIKE 'nedc%' THEN 'NEDC' END           AS cycle,
    CASE
        WHEN p.is_electric OR p.basis IS NULL THEN NULL
        WHEN p.basis IN ('wltp_plate', 'wltp_variant') OR p.powertrain = 'PHEV' THEN gw.gap
        ELSE gn.gap
    END                                                      AS gap_applied
FROM picked p
LEFT JOIN cycle_conversion cc
       ON cc.powertrain = p.powertrain AND cc.band_id = p.band_id
LEFT JOIN realworld_gap_wltp gw ON gw.powertrain = p.powertrain
LEFT JOIN realworld_gap_nedc gn ON gn.build_year = p.build_year;

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
