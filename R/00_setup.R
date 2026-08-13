# Shared setup for the R analysis layer.
#
# The heavy lifting -- 9.5M vehicle rows, the join, the powertrain classification --
# happens once in DuckDB (see sql/). R reads the small aggregate tables that step
# writes to output/ and does the interpretation and the figures. That split keeps
# R working on tables of tens to thousands of rows instead of millions.

suppressPackageStartupMessages({
  library(ggcpb)
  library(ggplot2)
  library(dplyr)
  library(readr)
  library(tidyr)
  library(tibble)
})

project_root <- function() {
  # Works whether the script is sourced from the project root or from R/.
  if (dir.exists("output") && dir.exists("sql")) return(normalizePath("."))
  if (dir.exists("../output")) return(normalizePath(".."))
  stop("run from the project root (output/ and sql/ must be visible)")
}

ROOT     <- project_root()
OUT_DIR  <- file.path(ROOT, "output")
FIG_DIR  <- file.path(OUT_DIR, "figures")
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

#' Read one aggregate table written by `fuelecon export`
read_table <- function(name) {
  path <- file.path(OUT_DIR, paste0(name, ".csv"))
  if (!file.exists(path)) {
    stop("missing ", path, "\nrun: uv run fuelecon all", call. = FALSE)
  }
  read_csv(path, show_col_types = FALSE, progress = FALSE)
}

# Dutch labels for the powertrain codes the SQL layer emits, in the order they
# should stack and appear in legends: combustion first, electrified last.
POWERTRAIN_LEVELS <- c("Petrol", "Diesel", "LPG", "CNG", "HEV", "PHEV", "BEV",
                       "FCEV", "Other", "Unknown")
POWERTRAIN_NL <- c(
  Petrol = "benzine", Diesel = "diesel", LPG = "lpg", CNG = "cng",
  HEV = "hybride", PHEV = "plug-in hybride", BEV = "elektrisch",
  FCEV = "waterstof", Other = "overig", Unknown = "onbekend"
)

label_powertrain <- function(x) {
  factor(unname(POWERTRAIN_NL[x]),
         levels = unname(POWERTRAIN_NL[POWERTRAIN_LEVELS]))
}

# Powertrains with enough of a presence to carry their own line; the rest are
# real but too thin to read on a chart (cng and waterstof are together <0.1%).
MAIN_POWERTRAINS <- c("Petrol", "Diesel", "HEV", "PHEV", "BEV")

# A year axis in the house style: labelled every four years, minor ticks between.
scale_x_year <- function(from = 2000, to = 2024, by = 4) {
  scale_x_continuous(
    breaks       = seq(from, to, by),
    minor_breaks = from:to,
    guide        = guide_axis(minor.ticks = TRUE)
  )
}

#' Export a figure at a CPB page width and report it
fig <- function(plot, name, page = "full", height = 3.4) {
  path <- file.path(FIG_DIR, paste0(name, ".png"))
  save_cpb(path, plot = plot, page = page, height = height)
  invisible(path)
}

# Rounded percentage change between the first and last value of a series.
pct_change <- function(from, to) round(100 * (to - from) / from, 1)
