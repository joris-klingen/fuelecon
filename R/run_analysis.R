# Driver: runs the whole R analysis layer and prints the headline numbers.
#
#   Rscript R/run_analysis.R
#
# Expects `uv run fuelecon all` to have produced output/*.csv first.

source("R/00_setup.R")
source("R/01_fleet.R")
source("R/02_efficiency.R")
source("R/03_adjusted.R")
source("R/04_segments.R")
source("R/05_hedonic.R")
source("R/06_model_index.R")

fmt <- function(x) formatC(x, format = "d", big.mark = ",")

rule <- function(title) {
  cat("\n", title, "\n", strrep("-", nchar(title)), "\n", sep = "")
}

cat("\nDutch passenger cars, build years 2000-2024\n")
cat("===========================================\n")

rule("Fleet")
with(fleet_facts, {
  cat(sprintf("Registered now       %s cars\n", fmt(total)))
  cat(sprintf("Largest vintage      %d (%s still registered)\n", peak_year, fmt(peak_vehicles)))
  cat(sprintf("Built 2000-2009      %.1f%% of the fleet\n", share_pre_2010))
  cat(sprintf("Largest make         %s (%.1f%%)\n", top_make, top_make_share))
  cat(sprintf("Largest model        %s (%s cars)\n", top_model, fmt(top_model_n)))
  cat(sprintf("Kerb mass            %s -> %s kg (%+.0f%%)\n",
              fmt(mass_2000), fmt(mass_2024), 100 * (mass_2024 - mass_2000) / mass_2000))
  cat(sprintf("Power                %.0f -> %.0f kW (%+.0f%%)\n",
              power_2000, power_2024, 100 * (power_2024 - power_2000) / power_2000))
})

rule("Type-approval CO2")
with(efficiency_facts, {
  cat(sprintf("NEDC %d-%d       %.0f -> %.0f g/km median (%+.1f%%)\n",
              nedc_first, nedc_last, nedc_co2_first, nedc_co2_last, nedc_change))
  cat(sprintf("WLTP %d-2024       %.0f -> %.0f g/km median (%+.1f%%)\n",
              wltp_first, wltp_co2_first, wltp_co2_2024, wltp_change))
  cat(sprintf("Fleet tailpipe CO2   %.0f -> %.0f g/km (%+.1f%%)\n",
              fleet_co2_2000, fleet_co2_2024, fleet_change))
  cat(sprintf("Zero-tailpipe 2024   %.1f%% of the vintage\n", zero_share_2024))
})

rule("Fuel economy, corrected")
with(adjusted_facts, {
  cat(sprintf("NEDC->WLTP factor    %.3f pooled, from 1.41M paired cars\n", conv_pooled))
  cat(sprintf("Type approval        %.2f -> %.2f l/100km (%+.1f%%)\n", ta_2000, ta_2024, ta_change))
  cat(sprintf("On the road          %.2f -> %.2f l/100km (%+.1f%%)\n",
              real_2000, real_2024, real_change))
  cat(sprintf("  peak on the road   %.2f l/100km in %d: the test gap grew faster\n",
              real_peak, real_peak_year))
  cat(sprintf("Fleet (electric = 0) %.2f -> %.2f l/100km (%+.1f%%)\n",
              real_2000, fleet_2024, fleet_change))
  cat(sprintf("At 2000 kerb mass    %.2f l/100km (%+.1f%%); mass cost %.2f l/100km\n",
              fleet_cf_24, fleet_cf_change, fleet_penalty_24))
})

rule("Replacing a car with one five years newer")
with(segment_facts, {
  cat(sprintf("2024 against 2019    %.2f -> %.2f l/100km, saving %.2f (%.1f%%)\n",
              save_2024_old, save_2024_new, save_2024, save_2024_pct))
  cat(sprintf("  length-based check %.2f l/100km (%.1f%%)\n", save_2024_len, save_2024_lenpct))
  cat(sprintf("Worst year to buy    %d (%.2f l/100km)\n", worst_year, worst_saving))
  cat(sprintf("Petrol, same size    %+.1f%% (small) and %+.1f%% (very large) since 2013\n",
              petrol_small_late, petrol_big_late))
})

rule("Quality-adjusted indices, 2000 = 100")
cat(sprintf("Same specification   %.1f  (%.1f%% more efficient, %.2f%%/year)\n",
            hedonic_facts$index_2024, hedonic_facts$total_gain, hedonic_facts$mean_yoy))
cat(sprintf("Same model           %.1f  (%.1f%% more efficient)\n",
            model_facts$index_2024, model_facts$total_gain))
cat(sprintf("  alternative cut    %.1f\n", model_facts$alt_2024))
cat(sprintf("Years that got worse %d of 24 (specification), %s (models)\n",
            hedonic_facts$n_years_worse, model_facts$worst_run))
cat(sprintf("Five years newer     %.1f%% (2013), %.1f%% (2019), %.1f%% (2024)\n",
            hedonic_facts$five_2013, hedonic_facts$five_2019, hedonic_facts$five_2024))

cat(sprintf("\nFigures written to %s\n", FIG_DIR))
