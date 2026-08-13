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
    order_by: str = "kenteken"
    where: str | None = None
    # True when ``order_by`` is not unique (several rows share one key). The last
    # key group of every page is dropped and re-requested, so no row is split
    # across a page boundary.
    duplicate_keys: bool = False

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
        "massa_ledig_voertuig",
        "massa_rijklaar",
        "cilinderinhoud",
        "aantal_cilinders",
        "aantal_zitplaatsen",
        "aantal_deuren",
        "lengte",
        "breedte",
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
        # WLTP declarations (phased in 2017-2021, mandatory after).
        "brandstof_verbruik_gecombineerd_wltp",
        "brandstof_verbruik_gewogen_gecombineerd_wltp",
        "emissie_co2_gecombineerd_wltp",
        "emis_co2_gewogen_gecombineerd_wltp",
        "elektrisch_verbruik_enkel_elektrisch_wltp",
        "elektrisch_verbruik_extern_opladen_wltp",
        "actie_radius_enkel_elektrisch_wltp",
        "elektriciteitsverbruik_volledig_elektrisch",
        "nettomaximumvermogen",
        "netto_max_vermogen_elektrisch",
        "klasse_hybride_elektrisch_voertuig",
        "uitlaatemissieniveau",
    ),
    order_by="kenteken",
    duplicate_keys=True,
)

DATASETS: dict[str, Dataset] = {d.key: d for d in (VEHICLES, FUEL)}


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
