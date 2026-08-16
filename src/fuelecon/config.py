"""Project-wide configuration: paths, RDW dataset definitions, analysis scope."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = Path(os.environ.get("FUELECON_DATA_DIR", PROJECT_ROOT / "data"))
RAW_DIR = DATA_DIR / "raw"
PARQUET_DIR = DATA_DIR / "parquet"
WAREHOUSE = DATA_DIR / "fuelecon.duckdb"
OUTPUT_DIR = Path(os.environ.get("FUELECON_OUTPUT_DIR", PROJECT_ROOT / "output"))
SQL_DIR = PROJECT_ROOT / "sql"

# Scope of the study: passenger cars first admitted (worldwide) in these years.
BUILD_YEAR_MIN = 2000
BUILD_YEAR_MAX = 2024

SOCRATA_DOMAIN = "https://opendata.rdw.nl"

# Socrata caps a single response at 50k rows unless you ask for more; 50k keeps
# each request around 2 seconds and each page well under 100 MB.
PAGE_SIZE = 50_000


@dataclass(frozen=True)
class Dataset:
    """One RDW Socrata dataset we pull into the local warehouse.

    Pagination is keyset-based on ``order_by``: every page asks for rows strictly
    after the last key seen. Socrata's ``$offset`` degrades badly at depth (12 s at
    offset 9M versus 1.6 s for a keyset page), so we never use it.
    """

    key: str
    resource_id: str
    title: str
    columns: tuple[str, ...]
    # Ordering key, as one or more columns. The type-approval tables have no single
    # column with small enough key groups -- ``typegoedkeuringsnummer`` alone runs to
    # 69k rows for one approval, more than a page -- so their key is the triple that
    # identifies a version, whose groups top out at 28 rows.
    order_by: tuple[str, ...] = ("kenteken",)
    where: str | None = None
    # True when ``order_by`` is not unique (several rows share one key). The last
    # key group of every page is dropped and re-requested, so no row is split
    # across a page boundary.
    duplicate_keys: bool = False

    def __post_init__(self) -> None:
        # The downloader reads the key back out of the CSV by position, so the key
        # columns have to be the leading ones in the projection.
        if tuple(self.columns[: len(self.order_by)]) != tuple(self.order_by):
            raise ValueError(
                f"{self.key}: order_by {self.order_by} must be the leading columns of "
                f"columns, which start {self.columns[: len(self.order_by)]}"
            )

    @property
    def csv_url(self) -> str:
        return f"{SOCRATA_DOMAIN}/resource/{self.resource_id}.csv"

    @property
    def landing_page(self) -> str:
        return f"{SOCRATA_DOMAIN}/dataset/{self.resource_id}"

    @property
    def raw_path(self) -> Path:
        return RAW_DIR / f"{self.key}.csv"

    @property
    def state_path(self) -> Path:
        return RAW_DIR / f"{self.key}.state.json"

    @property
    def parquet_path(self) -> Path:
        return PARQUET_DIR / f"{self.key}.parquet"


# The registry table is the *current* fleet: one row per licence plate that is
# registered in the Netherlands today. Filtering it server-side to passenger cars
# in the build-year window cuts ~16M rows down to ~9.5M.
VEHICLES = Dataset(
    key="vehicles",
    resource_id="m9d7-ebf2",
    title="Gekentekende voertuigen (vehicle registry)",
    columns=(
        "kenteken",
        "merk",
        "handelsbenaming",
        "inrichting",
        "europese_voertuigcategorie",
        "datum_eerste_toelating",
        "datum_eerste_tenaamstelling_in_nederland",
        "datum_tenaamstelling",
        # Keys into the type-approval tables below. A licence plate names a
        # version ("uitvoering") of a variant of one approval, which is a far
        # finer object than make + model: it is the exact drivetrain and body
        # combination the consumption figures were certified for.
        "typegoedkeuringsnummer",
        "type",
        "variant",
        "uitvoering",
        "volgnummer_wijziging_eu_typegoedkeuring",
        "massa_ledig_voertuig",
        "massa_rijklaar",
        "cilinderinhoud",
        "aantal_cilinders",
        "aantal_zitplaatsen",
        "aantal_deuren",
        "lengte",
        "breedte",
        "hoogte_voertuig",
        "wielbasis",
        "catalogusprijs",
        "vermogen_massarijklaar",
        "zuinigheidsclassificatie",
        "export_indicator",
        "taxi_indicator",
        "tenaamstellen_mogelijk",
        "wam_verzekerd",
    ),
    where=(
        "voertuigsoort='Personenauto' "
        f"AND datum_eerste_toelating_dt >= '{BUILD_YEAR_MIN}-01-01T00:00:00' "
        f"AND datum_eerste_toelating_dt < '{BUILD_YEAR_MAX + 1}-01-01T00:00:00'"
    ),
)

# The fuel table cannot be filtered to our vehicles server-side (Socrata has no
# cross-dataset joins), so we take it whole and join locally. One vehicle has one
# row per fuel it can run on, hence duplicate_keys.
FUEL = Dataset(
    key="fuel",
    resource_id="8ys7-d773",
    title="Gekentekende voertuigen brandstof (fuel and emissions)",
    columns=(
        "kenteken",
        "brandstof_volgnummer",
        "brandstof_omschrijving",
        # NEDC-era declarations (dominant up to ~2018).
        "brandstofverbruik_gecombineerd",
        "co2_uitstoot_gecombineerd",
        "co2_uitstoot_gewogen",
        # The NEDC-era *weighted* pair, which is what a pre-2018 plug-in hybrid was
        # certified on. Without them a 2015 PHEV falls back to its unweighted figure
        # and its litres per kilometre come out far too low.
        "brandstofverbruik_gewogen_gecombineerd",
        "elektriciteitsverbruik_gewogen_gecombineerd",
        # WLTP declarations (phased in 2017-2021, mandatory after).
        "brandstof_verbruik_gecombineerd_wltp",
        "brandstof_verbruik_gewogen_gecombineerd_wltp",
        "emissie_co2_gecombineerd_wltp",
        "emis_co2_gewogen_gecombineerd_wltp",
        "elektrisch_verbruik_enkel_elektrisch_wltp",
        "elektrisch_verbruik_extern_opladen_wltp",
        "actie_radius_enkel_elektrisch_wltp",
        "elektriciteitsverbruik_volledig_elektrisch",
        # Electric range, which is the denominator of any utility factor: how much
        # of a plug-in hybrid's driving is electric is the whole of its running
        # cost, and it cannot be recovered from the weighted figure alone.
        "actie_radius_extern_opladen_wltp",
        "actieradius_extern_oplaadbaar",
        "actieradius",
        "nettomaximumvermogen",
        "netto_max_vermogen_elektrisch",
        "klasse_hybride_elektrisch_voertuig",
        "uitlaatemissieniveau",
        "co2_emissieklasse",
    ),
    order_by=("kenteken",),
    duplicate_keys=True,
)

# ---------------------------------------------------------------------------
# Type approval (TGK). One row per version of a variant of an approval, keyed by
# (typegoedkeuringsnummer, codevarianttgk, codeuitvoeringtgk) plus a revision
# number. The registry carries those keys per licence plate, so these tables
# attach to a car -- 90.4% of 2000 vintages rising to 99.2% of 2024 ones.
#
# They are worth the download because they carry things the per-plate fuel table
# does not: the urban/extra-urban split of the NEDC figure, both bounds of every
# declaration, and the road-load coefficients that describe what it actually
# takes to move the car.
#
# None of them can be filtered to our vehicles server-side, so they come whole.
# Only the basis table carries a vehicle category to filter on.
# ---------------------------------------------------------------------------

_TGK_KEY = ("typegoedkeuringsnummer", "codevarianttgk", "codeuitvoeringtgk")

TGK_ENERGY = Dataset(
    key="tgk_energy",
    resource_id="gr7t-qfnb",
    title="TGK Energiebron Uitvoering (type-approval energy per version)",
    columns=(
        *_TGK_KEY,
        "volgnummerrevisieuitvoering",
        "volgnummeraandrijving",
        "volgnummerenergiebron",
        "codeenergiebron",
        "uitlaatemissieniveau",
        "maximumnettovermogenogr",
        "maximumnettovermogenbgr",
        # WLTP, plain and utility-factor weighted, each with both bounds.
        "brandstofverbruikgecombwltpogr",
        "brandstofverbruikgecombwltpbgr",
        "brandstverbrgewogencombwltpogr",
        "brandstverbrgewogencombwltpbgr",
        "co2emisgecombineerdwltpogr",
        "co2emisgecombineerdwltpbgr",
        "co2emisgewogengecombwltpogr",
        "co2emisgewogengecombwltpbgr",
        "verbruikvolledigelekwltpogr",
        "verbruikvolledigelekwltpbgr",
        "elekverbrexternoplaadbwltpogr",
        "elekverbrexternoplaadbwltpbgr",
        "actieradiusvolledigelekwltpogr",
        "actieradiusvolledigelekwltpbgr",
        "actieradiusexternoplaadwltpogr",
        "actieradiusexternoplaadwltpbgr",
        # NEDC, including the urban / extra-urban split that the per-plate table
        # collapses away. A car driven only in town and one driven only on the
        # motorway differ by a third on the same certificate.
        "verbruikgecombineerdnedclaag",
        "verbruikgecombineerdnedchoog",
        "verbrgewogengecombnedclaag",
        "verbrgewogengecombnedchoog",
        "elekverbruikgecombineerdnedc",
        "elekverbruikgewgecombverbrnedc",
        "elektrischeactieradiusnedc",
        "elekactieradiusextoplaadbnedc",
        "co2emissiestadnedclaag",
        "co2emissiestadnedchoog",
        "co2emissiebuitennedclaag",
        "co2emissiebuitennedchoog",
        "co2emisgecombineerdnedclaag",
        "co2emisgecombineerdnedchoog",
        "co2emisgewgecombnedclaag",
        "co2emisgewgecombnedchoog",
    ),
    order_by=_TGK_KEY,
    duplicate_keys=True,
)

TGK_BASIS = Dataset(
    key="tgk_basis",
    resource_id="byxc-wwua",
    title="TGK Basis Uitvoering (masses, dimensions, road load)",
    columns=(
        *_TGK_KEY,
        "volgnummerrevisieuitvoering",
        "begindatumrevisieuitvoering",
        "einddatumrevisieuitvoering",
        "voertuigcategorie",
        "massaledigondergrens",
        "massaledigbovengrens",
        "massarijklaarondergrens",
        "massarijklaarbovengrens",
        "wielbasisondergrens",
        "wielbasisbovengrens",
        "breedteondergrens",
        "breedtebovengrens",
        "hoogteondergrens",
        "hoogtebovengrens",
        # Road load: the coast-down polynomial F = f0 + f1*v + f2*v^2 that the
        # dynamometer was set to. f0 is rolling resistance, f2 is aerodynamic drag.
        # These are the physical inputs to an energy model, as against a scalar
        # correction applied to somebody else's laboratory number.
        "paramrijweerstandf0ondergrens",
        "paramrijweerstandf0bovengrens",
        "paramrijweerstandf1ondergrens",
        "paramrijweerstandf1bovengrens",
        "paramrijweerstandf2ondergrens",
        "paramrijweerstandf2bovengrens",
    ),
    order_by=_TGK_KEY,
    where="voertuigcategorie LIKE 'M1%'",
    duplicate_keys=True,
)

TGK_DRIVETRAIN = Dataset(
    key="tgk_drivetrain",
    resource_id="4by9-ammk",
    title="TGK Aandrijving Uitvoering (engine and drive)",
    columns=(
        *_TGK_KEY,
        "volgnummerrevisieuitvoering",
        "volgnummeraandrijving",
        "motorcode",
        "codewerkingmotor",
        "aantalcilinders",
        "cilinderinhoud",
        "codebrandstoftypemotor",
        "elektromotorindicator",
        "hybridemotorindicator",
        "enkelelektrischschakelingind",
        # An approval-level plug-in flag, independent of the registry's
        # klasse_hybride_elektrisch_voertuig. Two sources disagreeing about which
        # hybrids plug in is worth knowing about.
        "externoplaadbaarindicator",
    ),
    order_by=_TGK_KEY,
    duplicate_keys=True,
)

TGK_GEARBOX = Dataset(
    key="tgk_gearbox",
    resource_id="7rjk-eycs",
    title="TGK Versnelling Uitvoering (transmission)",
    columns=(
        *_TGK_KEY,
        "volgnummerrevisieuitvoering",
        "volgnummerversnelling",
        "codetypeversnellingsbak",
        "aantalversnellingenondergrens",
        "aantalversnellingenbovengrens",
    ),
    order_by=_TGK_KEY,
    duplicate_keys=True,
)

TGK_DATASETS = (TGK_ENERGY, TGK_BASIS, TGK_DRIVETRAIN, TGK_GEARBOX)

DATASETS: dict[str, Dataset] = {d.key: d for d in (VEHICLES, FUEL, *TGK_DATASETS)}


@dataclass(frozen=True)
class Paths:
    """Convenience bundle so callers do not import module-level globals."""

    data: Path = DATA_DIR
    raw: Path = RAW_DIR
    parquet: Path = PARQUET_DIR
    warehouse: Path = WAREHOUSE
    output: Path = OUTPUT_DIR
    sql: Path = SQL_DIR
    created: tuple[Path, ...] = field(default_factory=tuple)

    def ensure(self) -> None:
        for path in (self.raw, self.parquet, self.output):
            path.mkdir(parents=True, exist_ok=True)


PATHS = Paths()
