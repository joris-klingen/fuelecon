# Fuel economy on a like-for-like basis: one measurement cycle, on-road litres,
# and constant kerb mass.
#
# Three corrections stack, and each answers a different question:
#
#  1. Cycle. Historic NEDC figures are converted to WLTP-equivalent using factors
#     estimated in sql/040 from 1.41M cars that carry both declarations. This makes
#     2000 and 2024 comparable at all.
#  2. On-road. Type approval is a laboratory number; the divergence from it grew
#     through the NEDC era and reset under WLTP (sql/050, sourced to COM(2024) 122).
#     This turns a test result into litres actually burned.
#  3. Mass. Cars gained 31% kerb mass over the period, so part of the remaining
#     improvement was spent carrying more car. The counterfactual below holds mass
#     at its 2000 level to separate engine technology from vehicle growth.

fuel_trend  <- read_table("fuel_economy_trend")
fleet_fuel  <- read_table("fleet_fuel_trend")
mass_stats  <- read_table("mass_regression_stats")
conversion  <- read_table("cycle_conversion")
mass_fleet  <- read_table("mass_regression_stats_fleet")

# ---- the mass slope -----------------------------------------------------------

# Consumption per kilogram, identified within build year so that engine technology
# is held fixed: a heavy and a light car of the same vintage, not of any vintage.
# DuckDB supplied the per-cell moments; this assembles the fixed-effects estimate
#     beta = sum_y n_y cov_y(l, mass) / sum_y n_y var_y(mass)
# which is algebraically the within estimator, without 9.5M rows ever entering R.
mass_slope <- function(stats, cov_col) {
  stats |>
    summarise(
      beta = sum(n * .data[[cov_col]]) / sum(n * var_mass),
      .by = powertrain
    )
}

slopes_real <- mass_slope(mass_stats, "cov_mass_l_real")
slopes_ta   <- mass_slope(mass_stats, "cov_mass_l_typeapproval")

# ---- constant-mass counterfactual ---------------------------------------------

#' What each vintage would consume at the kerb mass of the 2000 vintage
constant_mass <- function(stats, slopes, mean_col, cov_col) {
  base <- stats |>
    filter(build_year == 2000) |>
    select(powertrain, mass_2000 = mean_mass)

  stats |>
    inner_join(slopes, by = "powertrain") |>
    inner_join(base, by = "powertrain") |>
    mutate(
      actual       = .data[[mean_col]],
      counterfact  = actual - beta * (mean_mass - mass_2000),
      mass_penalty = actual - counterfact
    ) |>
    select(build_year, powertrain, n, mean_mass, mass_2000, beta,
           actual, counterfact, mass_penalty)
}

cm_real <- constant_mass(mass_stats, slopes_real, "mean_l_real", "cov_mass_l_real")

# Pooled over combustion powertrains. This is the correction that matters: within
# petrol alone mean kerb mass barely moves across the period, because every time a
# larger car electrified it left the petrol category and took its mass with it. The
# fleet-wide 31% mass gain is largely that composition shift, and only appears once
# the powertrains sit in one pool.
beta_fleet <- with(mass_fleet, sum(n * cov_mass_l_real) / sum(n * var_mass))
mass_2000_fleet <- mass_fleet$mean_mass[mass_fleet$build_year == 2000]

cm_fleet <- mass_fleet |>
  mutate(
    beta         = beta_fleet,
    actual       = mean_l_real,
    counterfact  = mean_l_real - beta_fleet * (mean_mass - mass_2000_fleet),
    mass_penalty = actual - counterfact
  )

# ---- figure 8: type approval versus on road -----------------------------------

# The two lines diverge and then cross. Type approval keeps falling; what cars
# actually burned rose through the mid-2010s, because the gap between laboratory
# and road was widening faster than the engines were improving.
gap_long <- fleet_fuel |>
  select(build_year,
         `typegoedkeuring (WLTP-equivalent)` = mean_l_typeapproval,
         `op de weg`                          = mean_l_real_combustion) |>
  pivot_longer(-build_year, names_to = "reeks", values_to = "l")

p_gap <- cpb_line(gap_long, x = build_year, y = l, colour = reeks,
  index = c(6, 2),
  title = "Verbruik van verbrandingsmotoren: test versus weg",
  subtitle = "alles omgerekend naar WLTP-equivalent; bron gat: COM(2024) 122",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_gap, "08_typeapproval_vs_real")

# ---- figure 9: petrol, actual versus constant mass -----------------------------

petrol_cm <- cm_real |>
  filter(powertrain == "Petrol") |>
  select(build_year,
         `werkelijk verbruik` = actual,
         `bij gewicht van 2000` = counterfact) |>
  pivot_longer(-build_year, names_to = "reeks", values_to = "l")

p_mass <- cpb_line(petrol_cm, x = build_year, y = l, colour = reeks,
  index = c(6, 2),
  title = "Benzineauto's op de weg, werkelijk en bij gelijkblijvend gewicht",
  subtitle = "binnen benzine alleen blijft het gewicht vrijwel gelijk: nauwelijks effect",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_mass, "09_petrol_constant_mass")

# The fleet-level version, where the mass gain is real.
fleet_cm <- cm_fleet |>
  select(build_year,
         `werkelijk verbruik` = actual,
         `bij gewicht van 2000` = counterfact) |>
  pivot_longer(-build_year, names_to = "reeks", values_to = "l")

p_mass_fleet <- cpb_line(fleet_cm, x = build_year, y = l, colour = reeks,
  index = c(6, 2),
  title = "Verbrandingsmotoren op de weg, bij werkelijk en bij gelijkblijvend gewicht",
  subtitle = "verschil tussen de lijnen is wat het zwaarder worden heeft gekost",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_mass_fleet, "11_fleet_constant_mass")

# ---- figure 10: the fleet, including cars that burn nothing --------------------

fleet_long <- fleet_fuel |>
  select(build_year,
         `alle auto's (elektrisch = 0 l)` = mean_l_real_fleet,
         `alleen verbrandingsmotoren`     = mean_l_real_combustion) |>
  pivot_longer(-build_year, names_to = "reeks", values_to = "l")

p_fleet_fuel <- cpb_line(fleet_long, x = build_year, y = l, colour = reeks,
  index = c(6, 2),
  title = "Werkelijk brandstofverbruik per bouwjaar",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_fleet_fuel, "10_fleet_real_fuel")

# ---- numbers for the write-up -------------------------------------------------

atc <- function(df, yr, col, pt = NULL) {
  d <- if (is.null(pt)) df else df[df$powertrain == pt, ]
  d[[col]][d$build_year == yr]
}

pt_beta <- function(pt) slopes_real$beta[slopes_real$powertrain == pt]

adjusted_facts <- list(
  # Cycle conversion, estimated rather than assumed.
  conv_pooled      = round(stats::weighted.mean(conversion$ratio_co2_applied,
                                                conversion$n), 3),
  conv_petrol_lo   = min(conversion$ratio_co2_cell[conversion$powertrain == "Petrol"]),
  conv_petrol_hi   = max(conversion$ratio_co2_cell[conversion$powertrain == "Petrol"]),
  conv_diesel_lo   = min(conversion$ratio_co2_cell[conversion$powertrain == "Diesel"]),
  conv_diesel_hi   = max(conversion$ratio_co2_cell[conversion$powertrain == "Diesel"]),

  # Type approval versus on road, whole combustion fleet.
  ta_2000          = atc(fleet_fuel, 2000, "mean_l_typeapproval"),
  ta_2024          = atc(fleet_fuel, 2024, "mean_l_typeapproval"),
  ta_change        = pct_change(atc(fleet_fuel, 2000, "mean_l_typeapproval"),
                                atc(fleet_fuel, 2024, "mean_l_typeapproval")),
  real_2000        = atc(fleet_fuel, 2000, "mean_l_real_combustion"),
  real_2024        = atc(fleet_fuel, 2024, "mean_l_real_combustion"),
  real_change      = pct_change(atc(fleet_fuel, 2000, "mean_l_real_combustion"),
                                atc(fleet_fuel, 2024, "mean_l_real_combustion")),
  real_peak_year   = fleet_fuel$build_year[which.max(
                       ifelse(fleet_fuel$build_year >= 2010,
                              fleet_fuel$mean_l_real_combustion, -Inf))],
  real_peak        = max(fleet_fuel$mean_l_real_combustion[fleet_fuel$build_year >= 2010]),

  # Fleet including zero-fuel cars.
  fleet_2024       = atc(fleet_fuel, 2024, "mean_l_real_fleet"),
  fleet_change     = pct_change(atc(fleet_fuel, 2000, "mean_l_real_fleet"),
                                atc(fleet_fuel, 2024, "mean_l_real_fleet")),

  # Mass.
  beta_petrol      = pt_beta("Petrol"),
  beta_diesel      = pt_beta("Diesel"),
  petrol_mass_2000 = atc(cm_real, 2000, "mean_mass", "Petrol"),
  petrol_mass_2024 = atc(cm_real, 2024, "mean_mass", "Petrol"),
  petrol_actual_24 = atc(cm_real, 2024, "actual", "Petrol"),
  petrol_cf_24     = atc(cm_real, 2024, "counterfact", "Petrol"),
  petrol_penalty24 = atc(cm_real, 2024, "mass_penalty", "Petrol"),
  petrol_actual_00 = atc(cm_real, 2000, "actual", "Petrol"),
  petrol_change    = pct_change(atc(cm_real, 2000, "actual", "Petrol"),
                                atc(cm_real, 2024, "actual", "Petrol")),
  petrol_cf_change = pct_change(atc(cm_real, 2000, "actual", "Petrol"),
                                atc(cm_real, 2024, "counterfact", "Petrol")),

  # Pooled over combustion powertrains, where the mass gain is not a composition
  # artefact of one category.
  beta_fleet       = beta_fleet,
  fleet_mass_2000  = atc(cm_fleet, 2000, "mean_mass"),
  fleet_mass_2024  = atc(cm_fleet, 2024, "mean_mass"),
  fleet_actual_24  = atc(cm_fleet, 2024, "actual"),
  fleet_cf_24      = atc(cm_fleet, 2024, "counterfact"),
  fleet_penalty_24 = atc(cm_fleet, 2024, "mass_penalty"),
  fleet_cm_change  = pct_change(atc(cm_fleet, 2000, "actual"),
                                atc(cm_fleet, 2024, "actual")),
  fleet_cf_change  = pct_change(atc(cm_fleet, 2000, "actual"),
                                atc(cm_fleet, 2024, "counterfact"))
)
