# Driver: runs the whole R analysis layer and prints the headline numbers.
#
#   Rscript R/run_analysis.R
#
# Expects `uv run fuelecon all` to have produced output/*.csv first.

source("R/00_setup.R")
source("R/01_fleet.R")
source("R/02_efficiency.R")
source("R/03_adjusted.R")

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

cat("\nLike-for-like: een cyclus, op de weg, gelijk gewicht\n")
cat(  "----------------------------------------------------\n")
with(adjusted_facts, {
  cat(sprintf("NEDC->WLTP factor    %.3f gepoold, geschat uit 1,41 mln gepaarde auto's\n", conv_pooled))
  cat(sprintf("  benzine %.2f-%.2f, diesel %.2f-%.2f naar massaklasse\n",
              conv_petrol_lo, conv_petrol_hi, conv_diesel_lo, conv_diesel_hi))
  cat(sprintf("Typegoedkeuring      %.2f -> %.2f l/100km (%+.1f%%)\n",
              ta_2000, ta_2024, ta_change))
  cat(sprintf("Op de weg            %.2f -> %.2f l/100km (%+.1f%%)\n",
              real_2000, real_2024, real_change))
  cat(sprintf("  piek op de weg     %.2f l/100km in %d: het testgat groeide sneller\n",
              real_peak, real_peak_year))
  cat(sprintf("Hele park (elek.= 0) %.2f -> %.2f l/100km (%+.1f%%)\n",
              real_2000, fleet_2024, fleet_change))
  cat(sprintf("\nMassa-effect benzine (beta = %.4f l/100km per kg)\n", beta_petrol))
  cat(sprintf("  gewicht            %.0f -> %.0f kg\n", petrol_mass_2000, petrol_mass_2024))
  cat(sprintf("  werkelijk 2024     %.2f l/100km (%+.1f%% t.o.v. 2000)\n",
              petrol_actual_24, petrol_change))
  cat(sprintf("  bij gewicht 2000   %.2f l/100km (%+.1f%% t.o.v. 2000)\n",
              petrol_cf_24, petrol_cf_change))
  cat(sprintf("  kosten van zwaarder worden: %.2f l/100km\n", petrol_penalty24))
  cat(sprintf("  (binnen benzine blijft het gewicht vrijwel gelijk: zware auto's\n"))
  cat(sprintf("   verdwijnen naar hybride en elektrisch, niet uit het park)\n"))

  cat(sprintf("\nMassa-effect alle verbrandingsmotoren (beta = %.4f l/100km per kg)\n", beta_fleet))
  cat(sprintf("  gewicht            %.0f -> %.0f kg\n", fleet_mass_2000, fleet_mass_2024))
  cat(sprintf("  werkelijk 2024     %.2f l/100km (%+.1f%% t.o.v. 2000)\n",
              fleet_actual_24, fleet_cm_change))
  cat(sprintf("  bij gewicht 2000   %.2f l/100km (%+.1f%% t.o.v. 2000)\n",
              fleet_cf_24, fleet_cf_change))
  cat(sprintf("  kosten van zwaarder worden: %.2f l/100km\n", fleet_penalty_24))
})

cat(sprintf("\nFiguren geschreven naar %s\n", FIG_DIR))
