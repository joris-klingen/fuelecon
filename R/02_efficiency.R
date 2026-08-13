# Fuel efficiency across build years 2000-2024.
#
# Two things have to be kept apart or the trend is meaningless:
#
#  1. Test cycle. Type-approval figures were measured on NEDC until the WLTP
#     switchover (new types Sep 2017, all new registrations Sep 2018). WLTP returns
#     15-25% higher numbers for a physically identical car, so a single series
#     across the switch shows a fake regression in 2018-2019.
#  2. Population. RDW records no CO2 for battery-electric cars, so a median over
#     non-null CO2 quietly drops exactly the cars that are displacing combustion.
#     The tailpipe series enters them at 0 g/km and stays on a constant population.

efficiency_trend <- read_table("efficiency_trend")
fleet_co2        <- read_table("fleet_co2_trend")
eff_powertrain   <- read_table("efficiency_by_powertrain")
eff_normalised   <- read_table("efficiency_normalised")

# Cycle cells outside their era are contamination, not signal: a handful of cars
# per year, mostly heavy imports re-declared under the other cycle (the 2020-2024
# "NEDC" rows average 2.9 tonnes). Require a cell to be a real part of its vintage.
cycle_series <- efficiency_trend |>
  group_by(build_year) |>
  mutate(share = vehicles / sum(vehicles)) |>
  ungroup() |>
  filter(share >= 0.02, vehicles >= 1000) |>
  mutate(cyclus = factor(test_cycle, levels = c("NEDC", "WLTP")))

# ---- figure 4: the headline CO2 trend, cycle-split ----------------------------

p_cycle <- cpb_line(cycle_series, x = build_year, y = median_co2_g_km, colour = cyclus,
  index = c(6, 2),
  points = TRUE,
  title = "Type-keuring CO2 per bouwjaar, per testcyclus",
  ylab  = "gram CO2 per km (mediaan)",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_cycle, "04_co2_by_test_cycle")

# ---- figure 5: fleet tailpipe CO2 versus combustion-only ----------------------

# The gap between these two lines is electrification: the same vintages, once with
# zero-tailpipe cars counted in and once with only the cars that burn fuel.
fleet_long <- fleet_co2 |>
  select(build_year,
         `alle auto's (elektrisch = 0)` = mean_co2_tailpipe,
         `alleen verbrandingsmotoren`   = mean_co2_combustion_only) |>
  pivot_longer(-build_year, names_to = "reeks", values_to = "co2")

p_fleet <- cpb_line(fleet_long, x = build_year, y = co2, colour = reeks,
  index = c(6, 2),
  title = "Gemiddelde uitlaat-CO2 per bouwjaar",
  subtitle = "piek in 2019 is de overgang van NEDC naar WLTP, geen echte verslechtering",
  ylab  = "gram CO2 per km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_fleet, "05_fleet_vs_combustion_co2")

# ---- figure 6: CO2 by powertrain ----------------------------------------------

pt_series <- eff_powertrain |>
  filter(powertrain %in% c("Petrol", "Diesel", "HEV", "PHEV"),
         vehicles >= 1000) |>
  # One row per powertrain-year: keep the cycle that dominates that vintage.
  group_by(build_year, powertrain) |>
  slice_max(vehicles, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(aandrijving = label_powertrain(powertrain))

p_pt <- cpb_line(pt_series, x = build_year, y = median_co2_g_km, colour = aandrijving,
  index = c(6, 5, 4, 2),
  title = "CO2 per bouwjaar naar aandrijving",
  subtitle = "breuk rond 2018 is de overgang van NEDC naar WLTP",
  ylab  = "gram CO2 per km (mediaan)",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_pt, "06_co2_by_powertrain")

# ---- figure 7: what the engine gained, the kerb weight spent ------------------

# Cars got steadily heavier and more powerful over the period, so part of the
# per-kilometre gain went into carrying more car rather than into less fuel. CO2
# per tonne isolates the part of the improvement that is not explained by mass.
norm <- eff_normalised |>
  filter(powertrain %in% c("Petrol", "Diesel"), vehicles >= 1000) |>
  group_by(build_year, powertrain) |>
  slice_max(vehicles, n = 1, with_ties = FALSE) |>
  ungroup() |>
  filter(test_cycle == "NEDC") |>
  select(build_year, powertrain, median_co2_g_km, median_co2_per_tonne) |>
  pivot_longer(c(median_co2_g_km, median_co2_per_tonne),
               names_to = "maat", values_to = "waarde") |>
  mutate(maat = recode(maat,
           median_co2_g_km      = "CO2 per km",
           median_co2_per_tonne = "CO2 per km per ton ledig gewicht"),
         aandrijving = label_powertrain(powertrain))

p_norm <- cpb_line(filter(norm, powertrain == "Petrol"),
  x = build_year, y = waarde, colour = maat,
  index = c(6, 2),
  title = "Benzineauto's: CO2 per km en per ton, NEDC",
  ylab  = "gram CO2",
  xlab  = "bouwjaar") +
  scale_x_year(to = 2018)

fig(p_norm, "07_co2_per_tonne_petrol")

# ---- numbers for the write-up -------------------------------------------------

nedc <- cycle_series |> filter(test_cycle == "NEDC")
wltp <- cycle_series |> filter(test_cycle == "WLTP")

at <- function(df, yr, col) df[[col]][df$build_year == yr]

# Same lookup on the WLTP powertrain series, so petrol and diesel can be read
# after the cycle switch without the hybrids folded in.
wltp_pt <- eff_powertrain |> filter(test_cycle == "WLTP")
pt_at <- function(pt, yr, col) {
  wltp_pt[[col]][wltp_pt$powertrain == pt & wltp_pt$build_year == yr]
}

efficiency_facts <- list(
  nedc_first        = min(nedc$build_year),
  nedc_last         = max(nedc$build_year),
  nedc_co2_first    = at(nedc, min(nedc$build_year), "median_co2_g_km"),
  nedc_co2_last     = at(nedc, max(nedc$build_year), "median_co2_g_km"),
  nedc_change       = pct_change(at(nedc, min(nedc$build_year), "median_co2_g_km"),
                                 at(nedc, max(nedc$build_year), "median_co2_g_km")),
  nedc_l_first      = at(nedc, min(nedc$build_year), "median_l_100km"),
  nedc_l_last       = at(nedc, max(nedc$build_year), "median_l_100km"),
  wltp_first        = min(wltp$build_year),
  wltp_co2_first    = at(wltp, min(wltp$build_year), "median_co2_g_km"),
  wltp_co2_2024     = at(wltp, 2024, "median_co2_g_km"),
  wltp_change       = pct_change(at(wltp, min(wltp$build_year), "median_co2_g_km"),
                                 at(wltp, 2024, "median_co2_g_km")),
  fleet_co2_2000    = at(fleet_co2, 2000, "mean_co2_tailpipe"),
  fleet_co2_2024    = at(fleet_co2, 2024, "mean_co2_tailpipe"),
  fleet_change      = pct_change(at(fleet_co2, 2000, "mean_co2_tailpipe"),
                                 at(fleet_co2, 2024, "mean_co2_tailpipe")),
  comb_co2_2019     = at(fleet_co2, 2019, "mean_co2_combustion_only"),
  comb_co2_2024     = at(fleet_co2, 2024, "mean_co2_combustion_only"),
  zero_share_2024   = at(fleet_co2, 2024, "pct_zero_tailpipe"),

  # The combustion-only line still contains hybrids, so it is not a clean read on
  # engine development either. These are the two pure-combustion series after the
  # cycle switch, on WLTP throughout.
  petrol_2019       = pt_at("Petrol", 2019, "median_co2_g_km"),
  petrol_2024       = pt_at("Petrol", 2024, "median_co2_g_km"),
  petrol_change     = pct_change(pt_at("Petrol", 2019, "median_co2_g_km"),
                                 pt_at("Petrol", 2024, "median_co2_g_km")),
  petrol_mass_2019  = pt_at("Petrol", 2019, "mean_kerb_mass_kg"),
  petrol_mass_2024  = pt_at("Petrol", 2024, "mean_kerb_mass_kg"),
  diesel_2019       = pt_at("Diesel", 2019, "median_co2_g_km"),
  diesel_2024       = pt_at("Diesel", 2024, "median_co2_g_km"),
  diesel_mass_2019  = pt_at("Diesel", 2019, "mean_kerb_mass_kg"),
  diesel_mass_2024  = pt_at("Diesel", 2024, "mean_kerb_mass_kg")
)
