# The same nameplate, one year newer: a matched-model index.
#
# 070 holds the specification fixed. This holds the *model* fixed: a Golf against a
# Golf, a Clio against a Clio. The difference between the two indices is the wedge
# this file exists to show -- a 2024 Golf is a much larger and more powerful car
# than a 2000 Golf, so what a loyal buyer experienced is not what a constant
# specification would have delivered.
#
# The index is chained from year-on-year links, and each link compares one model in
# two adjacent years on the same declaration. No link straddles the cycle switch,
# so unlike every earlier step this index needs no cycle factor, no splice constant
# and no gap assumption. Model renaming is handled by the chaining: Peugeot's 206,
# 207 and 208 overlap in the registry, so each is matched against itself and the
# chain passes through the renaming without a break.

links     <- read_table("model_index_links")
basket    <- read_table("model_basket")
histories <- read_table("model_histories")

# Which declaration to trust for each link.
#
# The two bases can both produce a link for 2019-2024, and they disagree in every
# one of those years, with NEDC showing systematically less improvement (+3.3%
# against -0.8% in 2019; -1.4% against -8.7% in 2021). Two things explain that and
# both discredit the NEDC side: figures declared for cars built after 2018 are
# back-conversions from WLTP rather than fresh tests, and the population still
# carrying one shrinks to 17 models by 2024, self-selected toward type approvals
# carried over unchanged. So WLTP is preferred from 2019, the first year it has
# real coverage. The alternative cut is carried below as a sensitivity.
PRIMARY_SWITCH   <- 2019
ALTERNATIVE_SWITCH <- 2021

build_index <- function(switch_year, label) {
  chosen <- links |>
    filter((basis == "NEDC" & build_year <  switch_year) |
           (basis == "WLTP" & build_year >= switch_year)) |>
    arrange(build_year)

  tibble(
    build_year = c(2000, chosen$build_year),
    log_level  = cumsum(c(0, chosen$log_link)),
    variant    = label
  ) |>
    mutate(index = 100 * exp(log_level))
}

model_index <- bind_rows(
  build_index(PRIMARY_SWITCH,     "WLTP from 2019"),
  build_index(ALTERNATIVE_SWITCH, "WLTP from 2021")
)

primary <- filter(model_index, variant == "WLTP from 2019")

# ---- figure 21: the matched-model index ---------------------------------------

p_model <- cpb_line(model_index, x = build_year, y = index, colour = variant,
  index = c(6, 4),
  value_limits = c(40, 105),
  title = "Consumption of the same models, build year 2000 = 100",
  subtitle = "chained per model; no cycle conversion and no gap assumption",
  ylab  = "index (lower is more economical)",
  xlab  = "build year") +
  scale_x_year()

fig(p_model, "21_matched_model_index")

# ---- figure 22: individual nameplates ------------------------------------------

# The raw material, for a reader who would rather see cars than an index. NEDC
# throughout so the series are internally comparable; they stop where the
# declaration does.
PICK <- tribble(
  ~make,        ~model,
  "VOLKSWAGEN", "GOLF",
  "VOLKSWAGEN", "POLO",
  "RENAULT",    "CLIO",
  "FORD",       "FIESTA",
  "TOYOTA",     "YARIS"
)

hist_plot <- histories |>
  inner_join(PICK, by = c("make", "model")) |>
  filter(!is.na(l_100km_nedc), build_year <= 2020) |>
  mutate(name = paste(tools::toTitleCase(tolower(make)),
                      tools::toTitleCase(tolower(model))))

p_hist <- cpb_line(hist_plot, x = build_year, y = l_100km_nedc, colour = name,
  index = c(6, 5, 4, 2, 1),
  title = "Five models through time, NEDC declaration",
  subtitle = "each model against itself; series ends where the NEDC declaration does",
  ylab  = "litres per 100 km",
  xlab  = "build year") +
  scale_x_year(to = 2020)

fig(p_hist, "22_model_histories")

# ---- figure 23: model index against the hedonic index --------------------------

# The two cross, and both halves are informative. Until about 2020 the nameplate
# line sits above the specification line: following a Golf delivered less than a
# constant specification would have, because the Golf itself kept growing. After
# 2020 it dips below, because powertrain is a control in the hedonic and so
# hybridisation is stripped out there, while a nameplate that goes hybrid keeps
# the benefit. They finish within a point of each other.
comparison <- bind_rows(
  primary |> transmute(build_year, index, series = "same model"),
  hedonic_index |> transmute(build_year, index, series = "same specification")
)

p_compare <- cpb_line(comparison, x = build_year, y = index, colour = series,
  index = c(6, 2),
  value_limits = c(40, 105),
  title = "Same model versus same specification",
  subtitle = "model growth cost gains until 2020; after that the model gains by going hybrid",
  ylab  = "index, 2000 = 100 (lower is more economical)",
  xlab  = "build year") +
  scale_x_year()

fig(p_compare, "23_model_vs_hedonic")

# ---- numbers for the write-up -------------------------------------------------

mi  <- function(yr) primary$index[primary$build_year == yr]
alt <- function(yr) model_index$index[model_index$variant == "WLTP from 2021" &
                                      model_index$build_year == yr]
lk  <- function(b, yr) links$pct_change[links$basis == b & links$build_year == yr]

model_facts <- list(
  n_links_min    = min(links$models[links$basis == "NEDC" & links$build_year <= 2018]),
  n_links_max    = max(links$models),
  index_2024     = mi(2024),
  total_gain     = 100 - mi(2024),
  alt_2024       = alt(2024),
  hedonic_2024   = hedonic_index$index[hedonic_index$build_year == 2024],
  wedge          = mi(2024) - hedonic_index$index[hedonic_index$build_year == 2024],
  worst_run      = paste(links$build_year[links$basis == "NEDC" &
                                          links$build_year %in% 2016:2019 &
                                          links$pct_change > 0], collapse = ", "),
  mass_2019      = links$mean_mass_change_kg[links$basis == "NEDC" &
                                             links$build_year == 2019],
  power_2019     = links$mean_power_change_kw[links$basis == "NEDC" &
                                              links$build_year == 2019],
  disagree_2019  = c(lk("NEDC", 2019), lk("WLTP", 2019)),
  disagree_2021  = c(lk("NEDC", 2021), lk("WLTP", 2021)),
  basket_models  = max(basket$models),
  basket_2000    = basket$mean_l_nedc[basket$build_year == 2000],
  basket_2018    = basket$mean_l_nedc[basket$build_year == 2018]
)
