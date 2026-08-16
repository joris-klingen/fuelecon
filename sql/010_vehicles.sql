-- Step 010: clean the two raw RDW extracts into one row per vehicle.
--
-- Everything arrives as VARCHAR. RDW encodes "missing" as an empty string and
-- occasionally as a literal zero, so casts use TRY_CAST and zeros are nulled out
-- where zero is not a physically meaningful value.

CREATE OR REPLACE TABLE vehicles AS
WITH v AS (
    SELECT
        kenteken,
        -- Date of first admission to traffic, anywhere in the world. This is the
        -- closest thing RDW carries to a build year; for imports it is the year
        -- the car entered service abroad, not the year it reached the Netherlands.
        TRY_CAST(datum_eerste_toelating[1:4] AS INTEGER)              AS build_year,
        TRY_CAST(datum_eerste_tenaamstelling_in_nederland[1:4] AS INTEGER) AS nl_registration_year,
        upper(trim(merk))                                             AS make,
        upper(trim(handelsbenaming))                                  AS model_raw,
        nullif(trim(inrichting), '')                                  AS body_type,
        nullif(trim(europese_voertuigcategorie), '')                  AS eu_category,
        nullif(TRY_CAST(massa_ledig_voertuig AS INTEGER), 0)          AS kerb_mass_kg,
        nullif(TRY_CAST(massa_rijklaar AS INTEGER), 0)                AS running_mass_kg,
        nullif(TRY_CAST(cilinderinhoud AS INTEGER), 0)                AS displacement_cc,
        nullif(TRY_CAST(aantal_cilinders AS INTEGER), 0)              AS cylinders,
        nullif(TRY_CAST(aantal_zitplaatsen AS INTEGER), 0)            AS seats,
        nullif(TRY_CAST(aantal_deuren AS INTEGER), 0)                 AS doors,
        nullif(TRY_CAST(lengte AS INTEGER), 0)                        AS length_cm,
        nullif(TRY_CAST(breedte AS INTEGER), 0)                       AS width_cm,
        nullif(TRY_CAST(catalogusprijs AS INTEGER), 0)                AS list_price_eur,
        nullif(trim(zuinigheidsclassificatie), '')                    AS energy_label,
        trim(export_indicator)   = 'Ja'                               AS exported,
        trim(taxi_indicator)     = 'Ja'                               AS taxi,
        trim(wam_verzekerd)      = 'Ja'                               AS insured,
        trim(tenaamstellen_mogelijk) = 'Ja'                           AS transferable
    FROM raw_vehicles
),
-- One row per fuel per vehicle collapses to one row per vehicle. Consumption and
-- CO2 figures sit on whichever fuel row carries them (usually volgnummer 1), so
-- they are reduced with max() rather than picked from a fixed row.
f AS (
    SELECT
        kenteken,
        count(*)                                                       AS fuel_rows,
        list_sort(list(DISTINCT nullif(trim(brandstof_omschrijving), ''))) AS fuels,
        max(CASE WHEN TRY_CAST(brandstof_volgnummer AS INTEGER) = 1
                 THEN nullif(trim(brandstof_omschrijving), '') END)    AS primary_fuel,

        -- NEDC-era declarations (l/100 km and g CO2/km).
        max(TRY_CAST(brandstofverbruik_gecombineerd AS DOUBLE))        AS l_100km_nedc,
        max(TRY_CAST(co2_uitstoot_gecombineerd AS DOUBLE))             AS co2_nedc,
        max(TRY_CAST(co2_uitstoot_gewogen AS DOUBLE))                  AS co2_nedc_weighted,

        -- WLTP declarations. "gewogen" (weighted) variants are the utility-factor
        -- weighted numbers that plug-in hybrids are certified on.
        max(TRY_CAST(brandstof_verbruik_gecombineerd_wltp AS DOUBLE))  AS l_100km_wltp,
        max(TRY_CAST(brandstof_verbruik_gewogen_gecombineerd_wltp AS DOUBLE)) AS l_100km_wltp_weighted,
        max(TRY_CAST(emissie_co2_gecombineerd_wltp AS DOUBLE))         AS co2_wltp,
        max(TRY_CAST(emis_co2_gewogen_gecombineerd_wltp AS DOUBLE))    AS co2_wltp_weighted,

        -- Electric side.
        max(TRY_CAST(elektrisch_verbruik_enkel_elektrisch_wltp AS DOUBLE))   AS kwh_100km_bev_wltp,
        max(TRY_CAST(elektrisch_verbruik_extern_opladen_wltp AS DOUBLE))     AS kwh_100km_ovc_wltp,
        max(TRY_CAST(elektriciteitsverbruik_volledig_elektrisch AS DOUBLE))  AS kwh_100km_bev,
        max(TRY_CAST(actie_radius_enkel_elektrisch_wltp AS DOUBLE))          AS ev_range_km,

        max(TRY_CAST(nettomaximumvermogen AS DOUBLE))                  AS power_kw,
        max(TRY_CAST(netto_max_vermogen_elektrisch AS DOUBLE))         AS power_kw_electric,
        max(nullif(trim(klasse_hybride_elektrisch_voertuig), ''))      AS hybrid_class,
        max(nullif(trim(uitlaatemissieniveau), ''))                    AS euro_standard
    FROM raw_fuel
    GROUP BY kenteken
)
SELECT
    v.*,
    f.fuels,
    f.primary_fuel,
    f.fuel_rows,
    f.hybrid_class,
    f.euro_standard,
    f.power_kw,
    f.power_kw_electric,
    f.ev_range_km,

    -- Powertrain. RDW registers one fuel row per fuel the car can run on, so both
    -- a plug-in hybrid and a self-charging hybrid carry Benzine *and*
    -- Elektriciteit. The fuel list alone therefore cannot tell them apart -- doing
    -- that puts ~775k self-charging hybrids in the PHEV bucket and roughly triples
    -- it. What separates them is klasse_hybride_elektrisch_voertuig:
    --   OVC-HEV   off-vehicle charging   -> plug-in hybrid
    --   NOVC-HEV  no off-vehicle charging -> self-charging (full/mild) hybrid
    --   *-FCHV                            -> hydrogen fuel-cell hybrid
    CASE
        WHEN f.fuels IS NULL                                 THEN 'Unknown'
        WHEN f.hybrid_class LIKE '%FCHV'
          OR list_contains(f.fuels, 'Waterstof')             THEN 'FCEV'
        WHEN f.fuels = ['Elektriciteit']                     THEN 'BEV'
        WHEN f.hybrid_class LIKE 'OVC-%'                     THEN 'PHEV'
        WHEN f.hybrid_class LIKE 'NOVC-%'                    THEN 'HEV'
        -- No hybrid class recorded: fall back on whether the car declares an
        -- externally charged range, which only a plug-in can have.
        WHEN list_contains(f.fuels, 'Elektriciteit') AND len(f.fuels) > 1 THEN
            CASE WHEN coalesce(f.kwh_100km_ovc_wltp, 0) > 0 THEN 'PHEV' ELSE 'HEV' END
        WHEN list_contains(f.fuels, 'LPG')                   THEN 'LPG'
        WHEN list_contains(f.fuels, 'CNG')                   THEN 'CNG'
        WHEN list_contains(f.fuels, 'Diesel')                THEN 'Diesel'
        WHEN list_contains(f.fuels, 'Benzine')               THEN 'Petrol'
        WHEN list_contains(f.fuels, 'Alcohol')               THEN 'Petrol'
        ELSE 'Other'
    END AS powertrain,

    -- The combustion fuel a hybrid actually burns, so HEV/PHEV volumes can be
    -- folded back into a petrol-versus-diesel view when that is what is wanted.
    CASE
        WHEN list_contains(f.fuels, 'Diesel')  THEN 'Diesel'
        WHEN list_contains(f.fuels, 'Benzine') THEN 'Petrol'
        WHEN list_contains(f.fuels, 'LPG')     THEN 'LPG'
        WHEN list_contains(f.fuels, 'CNG')     THEN 'CNG'
    END AS combustion_fuel,

    -- Which test cycle the declared figures come from. The NEDC -> WLTP switch ran
    -- from Sep 2017 (new types) to Sep 2018 (all new registrations), and WLTP
    -- numbers are 15-25% higher for the same car. Any trend that mixes the two
    -- without this flag shows a fake efficiency regression around 2018-2020.
    CASE
        WHEN f.co2_wltp IS NOT NULL OR f.l_100km_wltp IS NOT NULL
          OR f.co2_wltp_weighted IS NOT NULL OR f.kwh_100km_bev_wltp IS NOT NULL THEN 'WLTP'
        WHEN f.co2_nedc IS NOT NULL OR f.l_100km_nedc IS NOT NULL THEN 'NEDC'
        ELSE 'none'
    END AS test_cycle,

    -- Preferred headline figures, cycle-aware, with implausible values dropped.
    -- Bounds are generous: they exist to remove data-entry noise (0 l/100km petrol
    -- cars, 4-digit CO2), not to trim the distribution.
    CASE WHEN coalesce(f.l_100km_wltp_weighted, f.l_100km_wltp, f.l_100km_nedc)
              BETWEEN 0.5 AND 40
         THEN coalesce(f.l_100km_wltp_weighted, f.l_100km_wltp, f.l_100km_nedc) END AS l_100km,
    CASE WHEN coalesce(f.co2_wltp_weighted, f.co2_wltp, f.co2_nedc_weighted, f.co2_nedc)
              BETWEEN 1 AND 700
         THEN coalesce(f.co2_wltp_weighted, f.co2_wltp, f.co2_nedc_weighted, f.co2_nedc) END AS co2_g_km,
    CASE WHEN coalesce(f.kwh_100km_bev_wltp, f.kwh_100km_bev, f.kwh_100km_ovc_wltp)
              BETWEEN 5 AND 60
         THEN coalesce(f.kwh_100km_bev_wltp, f.kwh_100km_bev, f.kwh_100km_ovc_wltp) END AS kwh_100km,

    -- Tailpipe CO2 for fleet-wide averages. RDW leaves CO2 null for battery-electric
    -- and fuel-cell cars rather than recording a zero, so a plain median over
    -- non-null CO2 silently conditions on "car that burns something" -- exactly the
    -- cars that are being displaced. Counting a BEV as the 0 g/km at the tailpipe
    -- that it is keeps the fleet series on a constant population.
    -- (Zero tailpipe, not zero well-to-wheel: generation emissions sit outside RDW.)
    CASE
        WHEN powertrain IN ('BEV', 'FCEV') THEN 0.0
        WHEN coalesce(f.co2_wltp_weighted, f.co2_wltp, f.co2_nedc_weighted, f.co2_nedc)
             BETWEEN 1 AND 700
        THEN coalesce(f.co2_wltp_weighted, f.co2_wltp, f.co2_nedc_weighted, f.co2_nedc)
    END AS co2_g_km_tailpipe,

    -- Raw cycle-specific figures kept so a like-for-like NEDC-only series is possible.
    CASE WHEN f.l_100km_nedc BETWEEN 0.5 AND 40 THEN f.l_100km_nedc END AS l_100km_nedc,
    CASE WHEN f.l_100km_wltp BETWEEN 0.5 AND 40 THEN f.l_100km_wltp END AS l_100km_wltp,
    -- Utility-factor weighted WLTP consumption: the figure a plug-in hybrid is
    -- actually certified on. Null for everything else, so it coalesces away.
    CASE WHEN f.l_100km_wltp_weighted BETWEEN 0.5 AND 40
         THEN f.l_100km_wltp_weighted END                             AS l_100km_wltp_weighted,
    CASE WHEN f.co2_nedc BETWEEN 1 AND 700 THEN f.co2_nedc END          AS co2_nedc,
    CASE WHEN f.co2_wltp BETWEEN 1 AND 700 THEN f.co2_wltp END          AS co2_wltp
FROM v
LEFT JOIN f USING (kenteken);

-- Model names are free text ("GOLF", "GOLF VII", "Golf 1.4 TSI"), and roughly a
-- third of makes repeat themselves in the model field ("TOYOTA AYGO" under make
-- TOYOTA), which reads as "Toyota Toyota Aygo" once make and model are pasted
-- together. Strip a leading copy of the make, then squash punctuation to spaces.
CREATE OR REPLACE TABLE model_lookup AS
SELECT
    make,
    model_raw,
    nullif(
        trim(regexp_replace(
            regexp_replace(
                -- Two forms of the same redundancy: "MAZDA 2" under make MAZDA, and
                -- "MAZDA2" without the space, which would otherwise survive as a
                -- separate nameplate and split the model's history in two.
                regexp_replace(
                    trim(regexp_replace(model_raw, '[^A-Z0-9 ]', ' ', 'g')),
                    '^' || regexp_escape(make) || '( |$)', ''
                ),
                '^' || regexp_escape(make) || '([0-9])', '\1'
            ),
            ' +', ' ', 'g'
        )),
        ''
    ) AS model_clean,
    count(*) AS n
FROM vehicles
WHERE model_raw IS NOT NULL
GROUP BY ALL;
