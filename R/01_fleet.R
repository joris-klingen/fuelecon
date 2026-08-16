# Fleet composition: how many cars of each vintage, powertrain and nameplate are
# registered in the Netherlands today.
#
# Read every count here as a stock, not as sales. The RDW registry is a snapshot of
# what is on the road now, so the thin tail before ~2008 is survival and export, not
# a small market in those years.

fleet_by_year       <- read_table("fleet_by_year")
fleet_by_powertrain <- read_table("fleet_by_year_powertrain")
fleet_by_make       <- read_table("fleet_by_make")
fleet_by_model      <- read_table("fleet_by_model")

fleet_total <- sum(fleet_by_year$vehicles)

# ---- figure 1: the age structure of the fleet, split by powertrain ------------

stack_df <- fleet_by_powertrain |>
  filter(powertrain %in% MAIN_POWERTRAINS) |>
  mutate(powertrain_label = label_powertrain(powertrain),
         cars_k          = vehicles / 1000)

p_age <- cpb_col(stack_df, x = build_year, y = cars_k, fill = powertrain_label,
  index = c(6, 5, 4, 2, 1),
  title = "Dutch passenger cars by build year and powertrain",
  ylab  = "thousand cars",
  xlab  = "build year") +
  scale_x_year()

fig(p_age, "01_fleet_by_year_powertrain")

# ---- figure 2: powertrain shares within each vintage --------------------------

# The same data as a share removes the survival effect from the picture: within a
# vintage, what fraction of the survivors is electrified.
p_share <- cpb_col(stack_df, x = build_year, y = cars_k, fill = powertrain_label,
  position = "fill",
  pct_axis = TRUE,
  index = c(6, 5, 4, 2, 1),
  title = "Powertrain shares within each build year",
  ylab  = "share of surviving cars",
  xlab  = "build year") +
  scale_x_year()

fig(p_share, "02_powertrain_share_by_year")

# ---- figure 3: the twenty most numerous nameplates ----------------------------

top_models <- fleet_by_model |>
  slice_max(vehicles, n = 20) |>
  mutate(name = paste(
           # Title-case the shouty registry strings for the axis.
           tools::toTitleCase(tolower(make)), tools::toTitleCase(tolower(model))
         ),
         cars_k = vehicles / 1000) |>
  arrange(vehicles) |>
  mutate(name = factor(name, levels = name))

p_models <- cpb_col(top_models, x = name, y = cars_k,
  orientation = "horizontal",
  fill_colour = unname(cpb_cols(6)),
  width = 0.7,
  title = "Twenty most common models, build years 2000-2024",
  ylab  = "model",
  xlab  = "thousand cars")

fig(p_models, "03_top_models", height = 4.2)

# ---- numbers for the write-up -------------------------------------------------

peak <- fleet_by_year |> slice_max(vehicles, n = 1)
oldest_decade <- fleet_by_year |> filter(build_year <= 2009) |> summarise(n = sum(vehicles))

fleet_facts <- list(
  total             = fleet_total,
  peak_year         = peak$build_year,
  peak_vehicles     = peak$vehicles,
  share_pre_2010    = round(100 * oldest_decade$n / fleet_total, 1),
  n_makes           = nrow(fleet_by_make),
  top_make          = fleet_by_make$make[1],
  top_make_share    = fleet_by_make$pct_of_fleet[1],
  top_model         = paste(fleet_by_model$make[1], fleet_by_model$model[1]),
  top_model_n       = fleet_by_model$vehicles[1],
  mass_2000         = fleet_by_year$mean_kerb_mass_kg[fleet_by_year$build_year == 2000],
  mass_2024         = fleet_by_year$mean_kerb_mass_kg[fleet_by_year$build_year == 2024],
  power_2000        = fleet_by_year$mean_power_kw[fleet_by_year$build_year == 2000],
  power_2024        = fleet_by_year$mean_power_kw[fleet_by_year$build_year == 2024]
)
