# The same car, one year newer: a quality-adjusted efficiency index.
#
# Everything before this holds a *segment* fixed. That is not enough, because a
# segment is not a specification: inside one cell the hybrid share, the engine
# power and the diesel share all move with Dutch tax policy rather than with
# technology. This step holds the specification itself fixed, by regressing log
# fuel consumption on build-year dummies plus mass, power, fuel type and body type.
# The year coefficients are then the answer to the question asked -- a car of
# identical size, power, fuel and shape, built a year later, uses how much less?
#
# Measurement is dealt with by splitting rather than converting. Two regressions
# are run on raw declarations, one per test cycle, and chained over the years where
# both exist. No cycle factor and no real-world gap enters the trend at any point,
# which is what makes this index immune to the objection that the corrections drive
# the result.

cells    <- read_table("hedonic_cells")
coverage <- read_table("hedonic_coverage")
splice   <- read_table("hedonic_splice")

# Regime windows. NEDC declarations are near-universal to 2020 and collapse after;
# WLTP starts in earnest in 2019. The 2019-2020 overlap is what chains them.
NEDC_YEARS    <- 2000:2020
WLTP_YEARS    <- 2019:2024
OVERLAP_YEARS <- 2019:2020

#' Fit the hedonic on one measurement regime and return its year effects
#'
#' Weighted by the number of cars in the cell that carry this regime's declaration,
#' so a cell counts for exactly what it contributes.
fit_regime <- function(value_col, weight_col, years) {
  d <- cells |>
    filter(build_year %in% years,
           .data[[weight_col]] > 0,
           !is.na(.data[[value_col]]),
           !is.na(mean_log_mass), !is.na(mean_log_power)) |>
    mutate(y   = .data[[value_col]],
           w   = .data[[weight_col]],
           yr  = factor(build_year, levels = years))

  model <- lm(y ~ yr + mean_log_mass + mean_log_power + powertrain + car_type,
              data = d, weights = w)

  # Year effects relative to the first year of the window, in logs.
  co <- coef(model)
  eff <- c(0, unname(co[paste0("yr", years[-1])]))
  tibble(build_year = years, log_effect = eff, regime = value_col)
}

nedc_fit <- fit_regime("mean_log_l_nedc", "n_nedc", NEDC_YEARS)
wltp_fit <- fit_regime("mean_log_l_wltp", "n_wltp", WLTP_YEARS)

# Chain the two series over the overlap, the way a statistical agency splices an
# index: shift the WLTP series so its overlap mean matches the NEDC series'. The
# level difference between the cycles never has to be assumed -- it is absorbed.
shift <- mean(nedc_fit$log_effect[nedc_fit$build_year %in% OVERLAP_YEARS]) -
         mean(wltp_fit$log_effect[wltp_fit$build_year %in% OVERLAP_YEARS])

hedonic_index <- bind_rows(
    nedc_fit |> filter(build_year < min(OVERLAP_YEARS)),
    wltp_fit |> mutate(log_effect = log_effect + shift)
  ) |>
  arrange(build_year) |>
  mutate(
    index      = 100 * exp(log_effect),          # 2000 = 100
    yoy_pct    = c(NA, 100 * (exp(diff(log_effect)) - 1)),
    since_2000 = 100 * (exp(log_effect) - 1)
  )

# What five years of progress is worth at constant specification, year by year.
hedonic_five_year <- hedonic_index |>
  select(build_year, log_effect) |>
  inner_join(hedonic_index |>
               transmute(build_year = build_year + 5, log_old = log_effect),
             by = "build_year") |>
  mutate(saving_pct = 100 * (1 - exp(log_effect - log_old)))

# ---- figure 18: the index -----------------------------------------------------

p_index <- cpb_line(hedonic_index, x = build_year, y = index,
  index = 6,
  value_limits = c(50, 100),
  title = "Zuinigheid bij gelijke specificatie, bouwjaar 2000 = 100",
  subtitle = "gewicht, vermogen, brandstof en carrosserie constant; geen cyclusomrekening",
  ylab  = "index (lager = zuiniger)",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_index, "18_hedonic_index")

# ---- figure 19: year on year --------------------------------------------------

# Negative is an improvement: the car of that build year uses that much less fuel
# than an otherwise identical car built the year before.
p_yoy <- cpb_col(filter(hedonic_index, !is.na(yoy_pct)),
  x = build_year, y = yoy_pct,
  fill_colour = unname(cpb_cols(6)),
  title = "Jaarlijkse verbetering bij gelijke specificatie",
  subtitle = "negatief = zuiniger dan een verder identieke auto van een jaar eerder",
  ylab  = "% verandering in verbruik",
  xlab  = "bouwjaar") +
  scale_x_continuous(breaks = seq(2000, 2024, 4))

fig(p_yoy, "19_hedonic_year_on_year")

# ---- figure 20: five years newer, specification held ---------------------------

p_five <- cpb_line(hedonic_five_year, x = build_year, y = saving_pct,
  index = 6,
  points = TRUE,
  title = "Vijf jaar jonger, bij gelijke specificatie",
  subtitle = "positief = zuiniger; vergelijk figuur 14, waar de specificatie meebeweegt",
  ylab  = "% zuiniger dan vijf jaar eerder",
  xlab  = "bouwjaar van de nieuwere auto") +
  scale_x_year(from = 2005)

fig(p_five, "20_hedonic_five_year")

# ---- numbers for the write-up -------------------------------------------------

hx <- function(yr, col) hedonic_index[[col]][hedonic_index$build_year == yr]
h5 <- function(yr) hedonic_five_year$saving_pct[hedonic_five_year$build_year == yr]

hedonic_facts <- list(
  splice_ratio   = splice$ratio_wltp_nedc[1],
  splice_n       = splice$vehicles[1],
  index_2024     = hx(2024, "index"),
  total_gain     = -hx(2024, "since_2000"),
  mean_yoy       = -mean(hedonic_index$yoy_pct, na.rm = TRUE),
  mean_yoy_early = -mean(hedonic_index$yoy_pct[hedonic_index$build_year %in% 2001:2013]),
  mean_yoy_late  = -mean(hedonic_index$yoy_pct[hedonic_index$build_year %in% 2014:2024]),
  worst_year     = hedonic_index$build_year[which.max(hedonic_index$yoy_pct)],
  worst_yoy      = max(hedonic_index$yoy_pct, na.rm = TRUE),
  n_years_worse  = sum(hedonic_index$yoy_pct > 0, na.rm = TRUE),
  five_2013      = h5(2013),
  five_2019      = h5(2019),
  five_2024      = h5(2024)
)
