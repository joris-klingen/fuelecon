# Fuel economy within a fixed kind of car.
#
# The fleet-wide trend mixes engines improving with people buying differently
# shaped cars. Everything here holds the kind of car fixed, so what is left is
# closer to what a buyer would actually experience when replacing one car with
# another of the same sort.
#
# Size is proxied by kerb mass, because RDW records a length for only about half
# the cars built before 2016 and the missing half is systematically lighter. See
# the header of sql/060_segments.sql; the length-based robustness check is plotted
# alongside the headline series below.

by_type    <- read_table("consumption_by_type")
by_size    <- read_table("consumption_by_size")
saving     <- read_table("segment_saving_summary")
saving_len <- read_table("segment_saving_length")
fixed_w    <- read_table("fixed_weight_index")
basis      <- read_table("segment_saving_basis")

CAR_TYPE_LEVELS <- c("hatchback", "stationwagen", "MPV", "sedan", "coupe/cabriolet")

# ---- figure 12: consumption per build year, one line per car type -------------

type_series <- by_type |>
  filter(car_type %in% CAR_TYPE_LEVELS) |>
  mutate(carrosserie = factor(car_type, levels = CAR_TYPE_LEVELS))

p_type <- cpb_line(type_series, x = build_year, y = mean_l_real, colour = carrosserie,
  index = c(6, 5, 4, 2, 1),
  # Sedans reach 5.6 l/100km in 2024 and coupes 11.2; without explicit limits the
  # panel clips the bottom of the sedan line.
  value_limits = c(5, 11.5),
  title = "Werkelijk verbruik per bouwjaar, naar carrosserie",
  subtitle = "alleen verbrandingsmotoren; op de weg, niet de testwaarde",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_type, "12_consumption_by_car_type")

# ---- figure 13: the same held at constant size --------------------------------

# This is the "same size specs" view: within a mass band, what a car of that size
# consumed depending on when it was built. The lines are what someone comparing
# like with like would actually face.
size_series <- by_size |>
  mutate(grootteklasse = factor(size_class,
                                levels = unique(by_size$size_class[order(by_size$size_id)])))

p_size <- cpb_line(size_series, x = build_year, y = mean_l_real, colour = grootteklasse,
  index = c(1, 4, 6, 5, 2),
  value_limits = c(5, 13.6),
  title = "Werkelijk verbruik per bouwjaar, naar grootteklasse",
  subtitle = "zwaarste klasse duikt na 2020: dat is de komst van plug-in hybrides",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_size, "13_consumption_by_size_class")

# The same size classes with the powertrain held fixed as well. By 2024 the
# heaviest band is 82% plug-in hybrid, consuming 4.3 l/100 km on the Commission's
# utility-factor correction against 12.2 for a petrol car of the same mass -- so
# the dive in the line above is the powertrain mix arriving, not engines improving.
# Restricting to petrol removes that and leaves engine progress alone.
size_petrol <- by_size |>
  filter(!is.na(mean_l_petrol)) |>
  mutate(grootteklasse = factor(size_class,
                                levels = unique(by_size$size_class[order(by_size$size_id)])))

p_size_petrol <- cpb_line(size_petrol, x = build_year, y = mean_l_petrol,
  colour = grootteklasse,
  index = c(1, 4, 6, 5, 2),
  title = "Alleen benzineauto's: werkelijk verbruik naar grootteklasse",
  subtitle = "aandrijving vastgehouden, zodat alleen motortechniek overblijft",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_size_petrol, "16_petrol_by_size_class")

# ---- figure 14: what five years newer is worth --------------------------------

# The direct answer to the replacement question, and the least comfortable figure
# in the set: for cars built through the middle of the 2010s the saving is zero or
# negative. Two things drive that. The measured part is that same-size cars really
# did get heavier and more powerful. The modelled part is the NEDC gap ramp -- a
# 2018 car with the same laboratory figure as a 2013 car burned more on the road,
# because the laboratory figure had drifted further from reality. Comparisons
# whose older side is a converted NEDC figure inherit that assumption.
saving_plot <- saving |>
  transmute(build_year = year_new,
            reeks = "zelfde type en grootte (gewichtsklasse)",
            l = saving_l_100km) |>
  bind_rows(
    saving_len |>
      summarise(l = sum(saving_l_100km * vehicles_new) / sum(vehicles_new),
                .by = year_new) |>
      transmute(build_year = year_new,
                reeks = "controle op werkelijke lengte",
                l = round(l, 3))
  )

p_saving <- cpb_line(saving_plot, x = build_year, y = l, colour = reeks,
  index = c(6, 2),
  points = TRUE,
  title = "Besparing bij vervanging door een vijf jaar jongere auto",
  subtitle = "zelfde carrosserie en grootte; positief = de nieuwere auto is zuiniger",
  ylab  = "liter per 100 km bespaard",
  xlab  = "bouwjaar van de nieuwere auto") +
  scale_x_year(from = 2005)

fig(p_saving, "14_five_year_replacement_saving")

# ---- figure 17: is the V-shape an artefact of the corrections? ----------------

# The same five-year saving on three bases. The dip into negative territory is
# present in the untouched NEDC declarations, so it is not manufactured by the
# corrections; what the real-world gap ramp does is push the whole NEDC-era curve
# down, because the newer car in every pair carries a larger assumed gap.
#
# The raw series is cut at 2020: after that NEDC declarations survive for a small
# self-selected residue (5.9% of 2024 cars) and the column stops being informative.
basis_long <- basis |>
  transmute(build_year = year_new,
            `op de weg (gat toegepast)`   = saving_realworld,
            `typegoedkeuring, zonder gat` = saving_typeapproval,
            `onbewerkte NEDC-opgave`      = ifelse(year_new <= 2020, saving_raw_nedc, NA)) |>
  pivot_longer(-build_year, names_to = "reeks", values_to = "l") |>
  filter(!is.na(l))

p_basis <- cpb_line(basis_long, x = build_year, y = l, colour = reeks,
  index = c(6, 2, 4),
  value_limits = c(-0.9, 2.1),
  title = "Dezelfde besparing, op drie grondslagen",
  subtitle = "de dip zit ook in de onbewerkte opgave: de correcties maken hem dieper, niet echt",
  ylab  = "liter per 100 km bespaard",
  xlab  = "bouwjaar van de nieuwere auto") +
  scale_x_year(from = 2005)

fig(p_basis, "17_saving_by_basis")

# ---- figure 15: how much of the fleet trend is the mix ------------------------

# Holding the composition of types and sizes at its 2000 shares separates engine
# progress from people buying different cars.
mix <- fixed_w |>
  select(build_year,
         `werkelijke samenstelling` = l_actual,
         `samenstelling van 2000`   = l_fixed_weight_2000) |>
  pivot_longer(-build_year, names_to = "reeks", values_to = "l")

p_mix <- cpb_line(mix, x = build_year, y = l, colour = reeks,
  index = c(6, 2),
  title = "Verbruik bij werkelijke en bij vastgehouden samenstelling",
  subtitle = "vastgehouden op de type- en grootteverdeling van bouwjaar 2000",
  ylab  = "liter per 100 km",
  xlab  = "bouwjaar") +
  scale_x_year()

fig(p_mix, "15_fixed_weight_composition")

# ---- numbers for the write-up -------------------------------------------------

sv <- function(yr, col) saving[[col]][saving$year_new == yr]
bs <- function(yr, col) basis[[col]][basis$year_new == yr]
pl <- function(yr, sid) by_size$mean_l_petrol[by_size$build_year == yr & by_size$size_id == sid]
len_saving <- saving_len |>
  summarise(l = sum(saving_l_100km * vehicles_new) / sum(vehicles_new),
            pct = 100 * sum(saving_l_100km * vehicles_new) / sum(l_old * vehicles_new),
            .by = year_new)

segment_facts <- list(
  # The clean comparison: both sides measured on WLTP, no conversion assumption.
  save_2024        = sv(2024, "saving_l_100km"),
  save_2024_pct    = sv(2024, "saving_pct"),
  save_2024_old    = sv(2024, "l_old_weighted"),
  save_2024_new    = sv(2024, "l_new_weighted"),
  save_2024_meas_o = sv(2024, "pct_measured_old"),
  save_2024_meas_n = sv(2024, "pct_measured_new"),
  save_2024_len    = round(len_saving$l[len_saving$year_new == 2024], 2),
  save_2024_lenpct = round(len_saving$pct[len_saving$year_new == 2024], 1),

  # The worst vintage to have bought.
  worst_year       = saving$year_new[which.min(saving$saving_l_100km)],
  worst_saving     = min(saving$saving_l_100km),
  best_early       = max(saving$saving_l_100km[saving$year_new <= 2015]),
  best_early_year  = saving$year_new[which.max(
                       ifelse(saving$year_new <= 2015, saving$saving_l_100km, -Inf))],

  # Spread across car types in the latest clean comparison.
  type_min_2024    = min(by_type$mean_l_real[by_type$build_year == 2024 &
                                             by_type$car_type %in% CAR_TYPE_LEVELS]),
  type_max_2024    = max(by_type$mean_l_real[by_type$build_year == 2024 &
                                             by_type$car_type %in% CAR_TYPE_LEVELS]),

  # Composition effect.
  mix_2024         = fixed_w$mix_effect[fixed_w$build_year == 2024],
  fixed_2024       = fixed_w$l_fixed_weight_2000[fixed_w$build_year == 2024],
  actual_2024      = fixed_w$l_actual[fixed_w$build_year == 2024],
  fixed_change     = pct_change(fixed_w$l_fixed_weight_2000[fixed_w$build_year == 2000],
                                fixed_w$l_fixed_weight_2000[fixed_w$build_year == 2024]),
  actual_change    = pct_change(fixed_w$l_actual[fixed_w$build_year == 2000],
                                fixed_w$l_actual[fixed_w$build_year == 2024]),

  # Size and powertrain both held fixed: what is left is engine technology alone.
  # The middle size class is the readable one, and it stops improving after 2013.
  petrol_mid_2000  = pl(2000, 3),
  petrol_mid_2013  = pl(2013, 3),
  petrol_mid_2024  = pl(2024, 3),
  petrol_mid_early = pct_change(pl(2000, 3), pl(2013, 3)),
  petrol_mid_late  = pct_change(pl(2013, 3), pl(2024, 3)),
  petrol_small_late = pct_change(pl(2013, 1), pl(2024, 1)),
  petrol_big_late  = pct_change(pl(2013, 5), pl(2024, 5)),

  # Does the correction create the V? Compare bases at the turning points.
  basis_2013_real  = bs(2013, "saving_realworld"),
  basis_2013_ta    = bs(2013, "saving_typeapproval"),
  basis_2013_raw   = bs(2013, "saving_raw_nedc"),
  basis_2019_real  = bs(2019, "saving_realworld"),
  basis_2019_ta    = bs(2019, "saving_typeapproval"),
  basis_2019_raw   = bs(2019, "saving_raw_nedc"),
  basis_2024_real  = bs(2024, "saving_realworld"),
  basis_2024_ta    = bs(2024, "saving_typeapproval"),
  basis_2024_nedc_cov = bs(2024, "pct_with_nedc_new")
)
