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

cat("\nZelfde auto, vijf jaar jonger\n")
cat(  "-----------------------------\n")
with(segment_facts, {
  cat(sprintf("Bouwjaar 2024 t.o.v. 2019, zelfde carrosserie en grootteklasse:\n"))
  cat(sprintf("  %.2f -> %.2f l/100km, besparing %.2f l/100km (%.1f%%)\n",
              save_2024_old, save_2024_new, save_2024, save_2024_pct))
  cat(sprintf("  beide kanten %.0f%% resp. %.0f%% gemeten op WLTP: schone vergelijking\n",
              save_2024_meas_o, save_2024_meas_n))
  cat(sprintf("  controle op werkelijke lengte: %.2f l/100km (%.1f%%)\n",
              save_2024_len, save_2024_lenpct))
  cat(sprintf("Slechtste bouwjaar om te kopen: %d (%.2f l/100km, dus duurder dan\n",
              worst_year, worst_saving))
  cat(sprintf("  de vijf jaar oudere auto van hetzelfde formaat)\n"))
  cat(sprintf("Beste vroege jaar: %d (%.2f l/100km bespaard)\n", best_early_year, best_early))
  cat(sprintf("\nSamenstellingseffect: bij de type- en grootteverdeling van 2000\n"))
  cat(sprintf("  zou 2024 op %.2f l/100km liggen i.p.v. %.2f (%.2f l/100km verschil)\n",
              fixed_2024, actual_2024, mix_2024))

  cat("\nGrootte EN aandrijving vastgehouden (benzine, middenklasse):\n")
  cat(sprintf("  %.2f (2000) -> %.2f (2013) -> %.2f l/100km (2024)\n",
              petrol_mid_2000, petrol_mid_2013, petrol_mid_2024))
  cat(sprintf("  %+.1f%% tot 2013, daarna %+.1f%%: de motor staat sinds 2013 stil\n",
              petrol_mid_early, petrol_mid_late))
  cat(sprintf("  klein sinds 2013 %+.1f%%, zeer groot %+.1f%%\n",
              petrol_small_late, petrol_big_late))

  cat("\nIs de V-vorm een artefact van de correcties?\n")
  cat(sprintf("  %-6s %10s %10s %10s\n", "jaar", "op de weg", "typegdk.", "ruwe NEDC"))
  cat(sprintf("  %-6d %10.2f %10.2f %10.2f\n", 2013, basis_2013_real, basis_2013_ta, basis_2013_raw))
  cat(sprintf("  %-6d %10.2f %10.2f %10.2f\n", 2019, basis_2019_real, basis_2019_ta, basis_2019_raw))
  cat(sprintf("  %-6d %10.2f %10.2f %10s\n", 2024, basis_2024_real, basis_2024_ta,
              sprintf("(%.0f%% dekking)", basis_2024_nedc_cov)))
  cat("  de dip zit ook in de ruwe opgave; het gat-model verdiept hem\n")
})

cat(sprintf("\nFiguren geschreven naar %s\n", FIG_DIR))
