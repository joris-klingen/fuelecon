-- Step 015: attach each licence plate to the type-approval version it was
-- certified as, and carry across what the per-plate tables do not hold.
--
-- WHY THIS EXISTS. `sql/010_vehicles.sql` reads the consumption figure that RDW
-- writes onto the licence plate. That is one number per car. The approval it came
-- from holds considerably more: the urban and extra-urban halves of the NEDC
-- figure, both bounds of every declaration, and the road-load polynomial the
-- dynamometer was set to. None of that is reachable from the plate alone.
--
-- The chain is registry -> approval -> variant -> version:
--
--     kenteken                                  H738VS
--       typegoedkeuringsnummer                  e1*2007/46*0627*09
--       variant                                 SACCYVBX0
--       uitvoering                              FD7FD7CW001N7MMOVL01VR2
--       volgnummer_wijziging_eu_typegoedkeuring 0
--
-- A version is a far finer object than make and model: it names the exact
-- drivetrain and body the figures were measured on. 90.4% of 2000 vintages carry
-- the keys, rising to 99.2% of 2024 ones.
--
-- Nothing here feeds the fleet series. Steps 020-050 are untouched, so the
-- published trend numbers do not move; this layer is additive and is what the
-- per-vehicle work in 060 is built from.

-- ---------------------------------------------------------------------------
-- Energy declarations per version.
--
-- The source has one row per drive per energy source, so a plug-in hybrid has a
-- petrol row and an electric row. Each figure sits on whichever row carries it,
-- so the group is reduced with max() rather than picked from a fixed row -- the
-- same reduction sql/010_vehicles.sql applies to the per-plate fuel table.
--
-- Every declaration comes as a pair: `ogr`/`bgr` are the lower and upper bound
-- over the configurations the version covers (`laag`/`hoog` in the NEDC fields).
-- Both are kept. The width between them is a per-car measure of how much the one
-- number on the licence plate is standing in for.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE variant_energy AS
SELECT
    typegoedkeuringsnummer                                   AS tgk_number,
    codevarianttgk                                           AS tgk_variant,
    codeuitvoeringtgk                                        AS tgk_version,
    TRY_CAST(volgnummerrevisieuitvoering AS INTEGER)         AS tgk_revision,

    list_sort(list(DISTINCT nullif(trim(codeenergiebron), ''))) AS energy_sources,
    max(nullif(trim(uitlaatemissieniveau), ''))              AS euro_standard,
    max(nullif(TRY_CAST(maximumnettovermogenbgr AS DOUBLE), 0)) AS power_kw_max,

    -- WLTP, plain.
    max(nullif(TRY_CAST(brandstofverbruikgecombwltpogr AS DOUBLE), 0)) AS l_wltp_lo,
    max(nullif(TRY_CAST(brandstofverbruikgecombwltpbgr AS DOUBLE), 0)) AS l_wltp_hi,
    max(nullif(TRY_CAST(co2emisgecombineerdwltpogr AS DOUBLE), 0))     AS co2_wltp_lo,
    max(nullif(TRY_CAST(co2emisgecombineerdwltpbgr AS DOUBLE), 0))     AS co2_wltp_hi,
    -- WLTP, utility-factor weighted: what a plug-in hybrid is certified on.
    max(nullif(TRY_CAST(brandstverbrgewogencombwltpogr AS DOUBLE), 0)) AS l_wltp_weighted_lo,
    max(nullif(TRY_CAST(brandstverbrgewogencombwltpbgr AS DOUBLE), 0)) AS l_wltp_weighted_hi,
    max(nullif(TRY_CAST(co2emisgewogengecombwltpogr AS DOUBLE), 0))    AS co2_wltp_weighted_lo,
    max(nullif(TRY_CAST(co2emisgewogengecombwltpbgr AS DOUBLE), 0))    AS co2_wltp_weighted_hi,

    -- Electric side, WLTP.
    max(nullif(TRY_CAST(verbruikvolledigelekwltpogr AS DOUBLE), 0))    AS kwh_wltp_bev_lo,
    max(nullif(TRY_CAST(verbruikvolledigelekwltpbgr AS DOUBLE), 0))    AS kwh_wltp_bev_hi,
    max(nullif(TRY_CAST(elekverbrexternoplaadbwltpogr AS DOUBLE), 0))  AS kwh_wltp_ovc_lo,
    max(nullif(TRY_CAST(elekverbrexternoplaadbwltpbgr AS DOUBLE), 0))  AS kwh_wltp_ovc_hi,
    max(nullif(TRY_CAST(actieradiusvolledigelekwltpbgr AS DOUBLE), 0)) AS ev_range_wltp,
    max(nullif(TRY_CAST(actieradiusexternoplaadwltpbgr AS DOUBLE), 0)) AS ev_range_ovc_wltp,

    -- NEDC, including the phase split. A car driven only in town and one driven
    -- only between towns differ by about a third on the same certificate, and the
    -- per-plate table carries only the combined figure.
    max(nullif(TRY_CAST(verbruikgecombineerdnedclaag AS DOUBLE), 0))   AS l_nedc_lo,
    max(nullif(TRY_CAST(verbruikgecombineerdnedchoog AS DOUBLE), 0))   AS l_nedc_hi,
    max(nullif(TRY_CAST(verbrgewogengecombnedclaag AS DOUBLE), 0))     AS l_nedc_weighted_lo,
    max(nullif(TRY_CAST(verbrgewogengecombnedchoog AS DOUBLE), 0))     AS l_nedc_weighted_hi,
    max(nullif(TRY_CAST(co2emisgecombineerdnedclaag AS DOUBLE), 0))    AS co2_nedc_lo,
    max(nullif(TRY_CAST(co2emisgecombineerdnedchoog AS DOUBLE), 0))    AS co2_nedc_hi,
    max(nullif(TRY_CAST(co2emisgewgecombnedclaag AS DOUBLE), 0))       AS co2_nedc_weighted_lo,
    max(nullif(TRY_CAST(co2emisgewgecombnedchoog AS DOUBLE), 0))       AS co2_nedc_weighted_hi,
    max(nullif(TRY_CAST(co2emissiestadnedclaag AS DOUBLE), 0))         AS co2_nedc_urban_lo,
    max(nullif(TRY_CAST(co2emissiestadnedchoog AS DOUBLE), 0))         AS co2_nedc_urban_hi,
    max(nullif(TRY_CAST(co2emissiebuitennedclaag AS DOUBLE), 0))       AS co2_nedc_extra_urban_lo,
    max(nullif(TRY_CAST(co2emissiebuitennedchoog AS DOUBLE), 0))       AS co2_nedc_extra_urban_hi,
    max(nullif(TRY_CAST(elekverbruikgecombineerdnedc AS DOUBLE), 0))   AS kwh_nedc,
    max(nullif(TRY_CAST(elekverbruikgewgecombverbrnedc AS DOUBLE), 0)) AS kwh_nedc_weighted,
    max(nullif(TRY_CAST(elektrischeactieradiusnedc AS DOUBLE), 0))     AS ev_range_nedc,
    max(nullif(TRY_CAST(elekactieradiusextoplaadbnedc AS DOUBLE), 0))  AS ev_range_ovc_nedc
FROM raw_tgk_energy
GROUP BY ALL;

-- ---------------------------------------------------------------------------
-- Masses, dimensions and road load per version.
--
-- The road-load polynomial F(v) = f0 + f1*v + f2*v^2 is the force the dynamometer
-- was set to resist: f0 is rolling resistance, f2 is aerodynamic drag. It is the
-- only physical description of the car in any of this data, and it is what a
-- consumption model can be built on rather than a scalar correction applied to
-- somebody else's laboratory number. It arrived with WLTP, so it exists for
-- roughly 2018 onwards only -- which is the window the EV switches sit in.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE variant_basis AS
SELECT
    typegoedkeuringsnummer                                   AS tgk_number,
    codevarianttgk                                           AS tgk_variant,
    codeuitvoeringtgk                                        AS tgk_version,
    TRY_CAST(volgnummerrevisieuitvoering AS INTEGER)         AS tgk_revision,
    max(nullif(trim(voertuigcategorie), ''))                 AS eu_category,
    max(TRY_CAST(begindatumrevisieuitvoering[1:4] AS INTEGER)) AS revision_start_year,
    max(TRY_CAST(einddatumrevisieuitvoering[1:4] AS INTEGER))  AS revision_end_year,

    max(nullif(TRY_CAST(massaledigondergrens AS DOUBLE), 0))     AS kerb_mass_lo,
    max(nullif(TRY_CAST(massaledigbovengrens AS DOUBLE), 0))     AS kerb_mass_hi,
    max(nullif(TRY_CAST(massarijklaarondergrens AS DOUBLE), 0))  AS running_mass_lo,
    max(nullif(TRY_CAST(massarijklaarbovengrens AS DOUBLE), 0))  AS running_mass_hi,
    max(nullif(TRY_CAST(wielbasisondergrens AS DOUBLE), 0))      AS wheelbase_lo,
    max(nullif(TRY_CAST(wielbasisbovengrens AS DOUBLE), 0))      AS wheelbase_hi,
    max(nullif(TRY_CAST(breedtebovengrens AS DOUBLE), 0))        AS width_cm,
    max(nullif(TRY_CAST(hoogtebovengrens AS DOUBLE), 0))         AS height_cm,

    max(nullif(TRY_CAST(paramrijweerstandf0ondergrens AS DOUBLE), 0)) AS road_load_f0_lo,
    max(nullif(TRY_CAST(paramrijweerstandf0bovengrens AS DOUBLE), 0)) AS road_load_f0_hi,
    max(nullif(TRY_CAST(paramrijweerstandf1ondergrens AS DOUBLE), 0)) AS road_load_f1_lo,
    max(nullif(TRY_CAST(paramrijweerstandf1bovengrens AS DOUBLE), 0)) AS road_load_f1_hi,
    max(nullif(TRY_CAST(paramrijweerstandf2ondergrens AS DOUBLE), 0)) AS road_load_f2_lo,
    max(nullif(TRY_CAST(paramrijweerstandf2bovengrens AS DOUBLE), 0)) AS road_load_f2_hi
FROM raw_tgk_basis
GROUP BY ALL;

-- Engine and drive. `externoplaadbaarindicator` is an approval-level plug-in flag,
-- arrived at independently of the registry's klasse_hybride_elektrisch_voertuig
-- that sql/010_vehicles.sql classifies on. Where the two disagree, one of them is
-- putting a self-charging hybrid in the plug-in bucket, and a plug-in hybrid's
-- running cost is nothing like a self-charging one's.
CREATE OR REPLACE TABLE variant_drivetrain AS
SELECT
    typegoedkeuringsnummer                                   AS tgk_number,
    codevarianttgk                                           AS tgk_variant,
    codeuitvoeringtgk                                        AS tgk_version,
    TRY_CAST(volgnummerrevisieuitvoering AS INTEGER)         AS tgk_revision,
    max(nullif(trim(motorcode), ''))                         AS engine_code,
    max(nullif(trim(codewerkingmotor), ''))                  AS engine_cycle,
    max(nullif(TRY_CAST(aantalcilinders AS INTEGER), 0))     AS cylinders,
    max(nullif(TRY_CAST(cilinderinhoud AS INTEGER), 0))      AS displacement_cc,
    list_sort(list(DISTINCT nullif(trim(codebrandstoftypemotor), ''))) AS engine_fuels,
    max(trim(elektromotorindicator))         = 'J'           AS has_electric_motor,
    max(trim(hybridemotorindicator))         = 'J'           AS is_hybrid,
    max(trim(externoplaadbaarindicator))     = 'J'           AS is_plug_in,
    max(trim(enkelelektrischschakelingind))  = 'J'           AS has_ev_mode
FROM raw_tgk_drivetrain
GROUP BY ALL;

-- Transmission. Gearbox type and ratio count move real consumption by several per
-- cent between otherwise identical cars, and neither appears on the licence plate.
CREATE OR REPLACE TABLE variant_gearbox AS
SELECT
    typegoedkeuringsnummer                                   AS tgk_number,
    codevarianttgk                                           AS tgk_variant,
    codeuitvoeringtgk                                        AS tgk_version,
    TRY_CAST(volgnummerrevisieuitvoering AS INTEGER)         AS tgk_revision,
    max(nullif(trim(codetypeversnellingsbak), ''))           AS gearbox_type,
    max(nullif(TRY_CAST(aantalversnellingenbovengrens AS INTEGER), 0)) AS gears
FROM raw_tgk_gearbox
GROUP BY ALL;

-- One row per version, everything joined. The spine is the union of the energy and
-- basis keys: a version can carry road load without an energy declaration, and the
-- reverse, and dropping either would silently thin the match rate.
CREATE OR REPLACE TABLE variants AS
SELECT
    coalesce(e.tgk_number, b.tgk_number)     AS tgk_number,
    coalesce(e.tgk_variant, b.tgk_variant)   AS tgk_variant,
    coalesce(e.tgk_version, b.tgk_version)   AS tgk_version,
    coalesce(e.tgk_revision, b.tgk_revision) AS tgk_revision,
    e.* EXCLUDE (tgk_number, tgk_variant, tgk_version, tgk_revision),
    b.* EXCLUDE (tgk_number, tgk_variant, tgk_version, tgk_revision),
    d.* EXCLUDE (tgk_number, tgk_variant, tgk_version, tgk_revision),
    g.* EXCLUDE (tgk_number, tgk_variant, tgk_version, tgk_revision)
FROM variant_energy e
FULL JOIN variant_basis b
       ON e.tgk_number = b.tgk_number AND e.tgk_variant = b.tgk_variant
      AND e.tgk_version = b.tgk_version AND e.tgk_revision = b.tgk_revision
LEFT JOIN variant_drivetrain d
       ON d.tgk_number = coalesce(e.tgk_number, b.tgk_number)
      AND d.tgk_variant = coalesce(e.tgk_variant, b.tgk_variant)
      AND d.tgk_version = coalesce(e.tgk_version, b.tgk_version)
      AND d.tgk_revision = coalesce(e.tgk_revision, b.tgk_revision)
LEFT JOIN variant_gearbox g
       ON g.tgk_number = coalesce(e.tgk_number, b.tgk_number)
      AND g.tgk_variant = coalesce(e.tgk_variant, b.tgk_variant)
      AND g.tgk_version = coalesce(e.tgk_version, b.tgk_version)
      AND g.tgk_revision = coalesce(e.tgk_revision, b.tgk_revision);

-- ---------------------------------------------------------------------------
-- Licence plate -> version.
--
-- 93% of versions carry only revision 0, so most matches are exact. Where the
-- registry names a revision the approval tables do not hold, the nearest earlier
-- revision is used and the row says so: an approval revision restates a version
-- rather than replacing it, so a neighbouring revision is a close description of
-- the same car, but it is not the one the car was certified against.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE vehicle_variant AS
WITH keyed AS (
    SELECT kenteken, build_year, powertrain, tgk_number, tgk_variant, tgk_version, tgk_revision
    FROM vehicles
    WHERE tgk_number IS NOT NULL AND tgk_variant IS NOT NULL AND tgk_version IS NOT NULL
),
ranked AS (
    SELECT
        k.kenteken,
        k.build_year,
        k.powertrain,
        k.tgk_revision                                       AS revision_wanted,
        v.*,
        CASE
            WHEN v.tgk_revision = k.tgk_revision THEN 'exact'
            WHEN v.tgk_revision <  k.tgk_revision THEN 'earlier revision'
            ELSE 'later revision'
        END                                                  AS match_quality,
        row_number() OVER (
            PARTITION BY k.kenteken
            ORDER BY
                CASE WHEN v.tgk_revision = k.tgk_revision THEN 0
                     WHEN v.tgk_revision <  k.tgk_revision THEN 1
                     ELSE 2 END,
                -- Within "earlier", take the latest; within "later", the earliest.
                CASE WHEN v.tgk_revision < k.tgk_revision THEN -v.tgk_revision
                     ELSE v.tgk_revision END
        )                                                    AS rn
    FROM keyed k
    JOIN variants v
      ON v.tgk_number = k.tgk_number
     AND v.tgk_variant = k.tgk_variant
     AND v.tgk_version = k.tgk_version
)
SELECT * EXCLUDE (rn) FROM ranked WHERE rn = 1;

-- How well the chain holds up, per vintage. Read this before trusting anything
-- built on the version-level figures for a given build year.
CREATE OR REPLACE TABLE variant_match_quality AS
SELECT
    v.build_year,
    count(*)                                                 AS vehicles,
    count(*) FILTER (WHERE v.tgk_number IS NOT NULL)         AS with_keys,
    count(m.kenteken)                                        AS matched,
    count(*) FILTER (WHERE m.match_quality = 'exact')        AS matched_exact,
    count(*) FILTER (WHERE m.match_quality <> 'exact')       AS matched_other_revision,
    round(100.0 * count(m.kenteken) / count(*), 1)           AS pct_matched,
    round(100.0 * count(m.l_wltp_hi) / count(*), 1)          AS pct_with_wltp_litres,
    round(100.0 * count(m.l_nedc_hi) / count(*), 1)          AS pct_with_nedc_litres,
    round(100.0 * count(m.co2_nedc_urban_hi) / count(*), 1)  AS pct_with_nedc_phases,
    round(100.0 * count(m.road_load_f0_hi) / count(*), 1)    AS pct_with_road_load
FROM vehicles v
LEFT JOIN vehicle_variant m USING (kenteken)
GROUP BY v.build_year
ORDER BY v.build_year;
