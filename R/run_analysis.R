# Driver: runs the whole R analysis layer and prints the headline numbers.
#
#   Rscript R/run_analysis.R
#
# Expects `uv run fuelecon all` to have produced output/*.csv first.

source("R/00_setup.R")
source("R/01_fleet.R")
source("R/02_efficiency.R")

# Dutch convention: "." groups thousands, "," is the decimal separator.
fmt <- function(x) formatC(x, format = "d", big.mark = ".", decimal.mark = ",")

cat("\n")
cat("Nederlandse personenauto's, bouwjaren 2000-2024\n")
cat("===============================================\n\n")

with(fleet_facts, {
  cat(sprintf("Wagenpark            %s auto's in het huidige register\n", fmt(total)))
  cat(sprintf("Grootste bouwjaar    %d (%s auto's nog geregistreerd)\n", peak_year, fmt(peak_vehicles)))
  cat(sprintf("Bouwjaar <= 2009     %.1f%% van het park\n", share_pre_2010))
  cat(sprintf("Grootste merk        %s (%.1f%%)\n", top_make, top_make_share))
  cat(sprintf("Grootste model       %s (%s auto's)\n", top_model, fmt(top_model_n)))
  cat(sprintf("Leeggewicht          %s kg (2000) -> %s kg (2024), %+.0f%%\n",
              fmt(mass_2000), fmt(mass_2024), 100 * (mass_2024 - mass_2000) / mass_2000))
  cat(sprintf("Vermogen             %.0f kW (2000) -> %.0f kW (2024), %+.0f%%\n",
              power_2000, power_2024, 100 * (power_2024 - power_2000) / power_2000))
})

cat("\nZuinigheid\n----------\n")
with(efficiency_facts, {
  cat(sprintf("NEDC %d-%d        %.0f -> %.0f g/km mediaan (%+.1f%%)\n",
              nedc_first, nedc_last, nedc_co2_first, nedc_co2_last, nedc_change))
  cat(sprintf("                     %.1f -> %.1f l/100km mediaan\n", nedc_l_first, nedc_l_last))
  cat(sprintf("WLTP %d-2024      %.0f -> %.0f g/km mediaan (%+.1f%%)\n",
              wltp_first, wltp_co2_first, wltp_co2_2024, wltp_change))
  cat(sprintf("Uitlaat-CO2 park     %.0f (2000) -> %.0f g/km (2024), %+.1f%%\n",
              fleet_co2_2000, fleet_co2_2024, fleet_change))
  cat(sprintf("  verbrandingsmotor  %.0f (2019) -> %.0f g/km (2024)\n",
              comb_co2_2019, comb_co2_2024))
  cat(sprintf("Nul-uitstoot 2024    %.1f%% van het bouwjaar\n\n", zero_share_2024))

  # Not the same statement as the fleet line: these hold the powertrain fixed.
  cat(sprintf("Benzine WLTP         %.0f (2019) -> %.0f g/km (2024), %+.1f%%\n",
              petrol_2019, petrol_2024, petrol_change))
  cat(sprintf("  leeggewicht        %s -> %s kg: de resterende benzineauto wordt kleiner\n",
              fmt(petrol_mass_2019), fmt(petrol_mass_2024)))
  cat(sprintf("Diesel WLTP          %.0f (2019) -> %.0f g/km (2024): stijgt\n",
              diesel_2019, diesel_2024))
  cat(sprintf("  leeggewicht        %s -> %s kg: diesel trekt zich terug op zware auto's\n",
              fmt(diesel_mass_2019), fmt(diesel_mass_2024)))
})

cat(sprintf("\nFiguren geschreven naar %s\n", FIG_DIR))
