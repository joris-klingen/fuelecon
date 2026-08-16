"""Generate the results page, embedding the figures as data URIs.

Deliberately short. The page carries the five figures that bear on the question it
was written for -- how the marginal cost of driving changes when a household
replaces its car -- and leaves the rest of the analysis to the README and the
warehouse.
"""

import base64
import pathlib

FIG_DIR = pathlib.Path(__file__).resolve().parents[1] / "output" / "figures"
OUT = pathlib.Path(__file__).resolve().parent / "results.html"

TITLE = "Developments in car fuel efficiency from 2000 till 2024"


def img(name: str) -> str:
    data = base64.b64encode((FIG_DIR / f"{name}.png").read_bytes()).decode()
    return f"data:image/png;base64,{data}"


# The five figures, in the order the argument runs.
FIGURES = [
    (
        "08_typeapproval_vs_real",
        "Type-approval and on-road fuel consumption, combustion engines",
        "Running cost depends on litres actually burned, not on the declared figure. "
        "The two series cross around 2007 and separate thereafter. On-road "
        "consumption <em>rises</em> between 2013 and 2019 while the declared figure "
        "continues to fall, because the divergence between laboratory and road was "
        "widening faster than engines were improving.",
    ),
    (
        "14_five_year_replacement_saving",
        "Saving from replacing a car with one five years newer, same body type and size",
        "The direct estimate. Through the middle 2010s the replacement bought "
        "nothing: a household moving to a 2019 car from a 2014 car of the same type "
        "and size increased its fuel use. By 2024 the same move is worth about two "
        "litres per 100 km. The second series repeats the calculation on measured "
        "vehicle length rather than mass bands; the two bracket the estimate at 1.7 "
        "to 2.0 litres.",
    ),
    (
        "13_consumption_by_size_class",
        "On-road consumption by build year and size class",
        "Heterogeneity across the choices a household actually faces. The decline in "
        "the heaviest class after 2020 is compositional rather than technical: by "
        "2024 that class is 82% plug-in hybrid, declaring 4.3 l/100 km against 12.2 "
        "for a petrol car of the same mass.",
    ),
    (
        "10_fleet_real_fuel",
        "Real-world fuel use per build year, whole fleet and combustion only",
        "For marginal cost the powertrain switch dominates everything else. The lower "
        "series enters battery-electric cars at zero litres; 30% of the 2024 vintage "
        "consumes no liquid fuel at all, which moves a household's marginal cost to "
        "the electricity tariff rather than reducing it at the pump.",
    ),
    (
        "23_model_vs_hedonic",
        "Quality-adjusted efficiency indices, 2000 = 100",
        "Two indices with different identifying variation. One holds the "
        "specification fixed (mass, power, fuel, body) through a hedonic regression; "
        "the other follows the same nameplate across its generations and uses no "
        "conversion, splice or gap assumption at all. They agree to within one index "
        "point, at 45.3% and 46.4%.",
    ),
]

RESULTS = [
    ("Type approval", "9.43", "4.54", "-51.8"),
    ("On the road", "8.57", "6.09", "-29.0"),
    ("On the road, at 2000 kerb mass", "8.57", "5.17", "-39.7"),
    ("Whole fleet, electric at zero litres", "8.57", "4.04", "-52.9"),
]

INDICES = [
    ("Same specification (hedonic)", "54.7", "45.3", "2.47"),
    ("Same model (matched-model)", "53.6", "46.4", "&mdash;"),
    ("Same model, alternative cycle cut", "57.9", "42.1", "&mdash;"),
]


def figure_block(i, name, title, note):
    return f"""      <figure class="fig">
        <img src="{img(name)}" alt="{title}" loading="lazy" />
        <figcaption>
          <p class="fig-no">Figure {i}</p>
          <p class="fig-title">{title}</p>
          <p>{note}</p>
        </figcaption>
      </figure>"""


figures = "\n".join(
    figure_block(i, name, title, note) for i, (name, title, note) in enumerate(FIGURES, 1)
)

results_rows = "\n".join(
    f"""            <tr><th scope="row">{label}</th>
              <td class="num">{a}</td><td class="num">{b}</td>
              <td class="num delta">{d}%</td></tr>"""
    for label, a, b, d in RESULTS
)

index_rows = "\n".join(
    f"""            <tr><th scope="row">{label}</th>
              <td class="num">{lvl}</td><td class="num">{gain}%</td>
              <td class="num">{yr}</td></tr>"""
    for label, lvl, gain, yr in INDICES
)

HTML = f"""<title>{TITLE}</title>
<style>
  /* Palette from the ggcpb design tokens, so page and figures are one system. */
  :root {{
    --ground:    #ffffff;
    --surface:   #eef8ff;   /* cpb_bg, the ground the figures are drawn on */
    --ink:       #14294a;
    --ink-soft:  #4c6285;
    --ink-faint: #7d90ad;
    --blue:      #005faf;
    --magenta:   #e6006e;
    --rule:      #c9d1da;
    --rule-soft: #e2e9f0;

    --measure: 34rem;
    --page: 46rem;
    --sans: "RO Sans", "Rijksoverheid Sans Text", "Frutiger", "Segoe UI",
            "Noto Sans", system-ui, sans-serif;
    --mono: "SFMono-Regular", "Menlo", "Consolas", monospace;
  }}

  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{
      --ground:    #0b1a2d;
      --surface:   #122740;
      --ink:       #dfeaf6;
      --ink-soft:  #a3b7cf;
      --ink-faint: #6f87a5;
      --blue:      #87d2ff;
      --magenta:   #f08bb8;
      --rule:      #2c445f;
      --rule-soft: #1c3149;
    }}
  }}

  :root[data-theme="dark"] {{
    --ground:    #0b1a2d;
    --surface:   #122740;
    --ink:       #dfeaf6;
    --ink-soft:  #a3b7cf;
    --ink-faint: #6f87a5;
    --blue:      #87d2ff;
    --magenta:   #f08bb8;
    --rule:      #2c445f;
    --rule-soft: #1c3149;
  }}

  /* The house typeface is licensed CPB tooling, so it is referenced from the
     reader's own machine rather than shipped with the page. */
  @font-face {{
    font-family: "RO Sans";
    src: local("RijksoverheidSansText"), local("Rijksoverheid Sans Text"),
         local("RijksoverheidSansText-Regular");
    font-weight: 400;
    font-display: swap;
  }}
  @font-face {{
    font-family: "RO Sans";
    src: local("RijksoverheidSansText-Bold"), local("Rijksoverheid Sans Text Bold");
    font-weight: 700;
    font-display: swap;
  }}

  body {{
    background: var(--ground);
    color: var(--ink);
    font-family: var(--sans);
    font-size: 1rem;
    line-height: 1.62;
    -webkit-font-smoothing: antialiased;
  }}

  .wrap {{
    max-width: var(--page);
    margin-inline: auto;
    padding: clamp(2rem, 5vw, 4rem) clamp(1.1rem, 4vw, 2rem) 5rem;
    display: flex;
    flex-direction: column;
    gap: 2.75rem;
  }}

  h1, h2 {{ text-wrap: balance; line-height: 1.2; }}
  h1 {{
    font-size: clamp(1.6rem, 4vw, 2.1rem);
    font-weight: 700;
    letter-spacing: -0.015em;
    margin: 0 0 0.75rem;
  }}
  h2 {{
    font-size: 1.0625rem;
    font-weight: 700;
    margin: 0 0 0.75rem;
  }}
  p {{ margin: 0 0 0.9rem; max-width: var(--measure); }}
  p:last-child {{ margin-bottom: 0; }}

  .meta {{
    font-size: 0.75rem;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--ink-faint);
    margin: 0 0 1.25rem;
  }}

  .abstract {{
    border-left: 2px solid var(--magenta);
    padding-left: 1.1rem;
    color: var(--ink-soft);
  }}
  .abstract p {{ max-width: var(--measure); }}

  a {{ color: var(--blue); text-underline-offset: 2px; }}
  a:focus-visible {{ outline: 2px solid var(--magenta); outline-offset: 3px; }}
  code {{ font-family: var(--mono); font-size: 0.875em; }}

  /* ---- tables ---- */
  .table-scroll {{ overflow-x: auto; }}
  table {{
    border-collapse: collapse;
    width: 100%;
    font-variant-numeric: tabular-nums;
    font-size: 0.9375rem;
  }}
  caption {{
    text-align: left;
    color: var(--ink-faint);
    font-size: 0.8125rem;
    padding-bottom: 0.6rem;
  }}
  th, td {{ padding: 0.45rem 0.7rem; text-align: left; white-space: nowrap; }}
  thead th {{
    font-size: 0.7rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--ink-faint);
    font-weight: 400;
    border-bottom: 1px solid var(--rule);
  }}
  tbody th {{ font-weight: 400; padding-left: 0; white-space: normal; }}
  tbody tr + tr th, tbody tr + tr td {{ border-top: 1px solid var(--rule-soft); }}
  td.num {{ text-align: right; font-weight: 700; }}
  td.delta {{ color: var(--blue); }}

  /* ---- figures ---- */
  .figures {{ display: flex; flex-direction: column; gap: 2.5rem; }}
  .fig {{ margin: 0; display: flex; flex-direction: column; gap: 0.75rem; }}
  .fig img {{
    display: block;
    width: 100%;
    height: auto;
    background: #eef8ff;      /* the figures carry their own light ground */
    border: 1px solid var(--rule);
  }}
  figcaption p {{ margin: 0; font-size: 0.9375rem; color: var(--ink-soft); }}
  .fig-no {{
    font-size: 0.7rem;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--magenta);
  }}
  .fig-title {{ font-weight: 700; color: var(--ink); margin-bottom: 0.25rem !important; }}

  footer {{
    border-top: 1px solid var(--rule);
    padding-top: 1.25rem;
    color: var(--ink-faint);
    font-size: 0.8125rem;
  }}
  footer p {{ max-width: none; }}

  @media (prefers-reduced-motion: reduce) {{
    * {{ animation: none !important; transition: none !important; }}
  }}
</style>

<div class="wrap">

  <header>
    <p class="meta">RDW open data &middot; 9,529,597 cars &middot; build years 2000-2024</p>
    <h1>{TITLE}</h1>
    <div class="abstract">
      <p>
        This note asks how the marginal cost of driving changes when a household
        replaces its car, new or second hand. The relevant quantity is fuel actually
        consumed per kilometre, which the declared type-approval figure does not
        measure. Using the complete Dutch vehicle registry &mdash; 9.5 million
        passenger cars matched to 16.9 million fuel records &mdash; consumption is
        placed on a single measurement basis, corrected to on-road conditions, and
        held constant for vehicle size, specification and model.
      </p>
      <p>
        Fuel efficiency improved by about 45% at constant specification over the
        period, roughly 2.5% a year, with a plateau between 2014 and 2019. A
        household replacing its car today with one five years newer and of the same
        size reduces fuel use by 1.7 to 2.0 litres per 100 km, about a fifth; the
        same replacement made in 2019 delivered nothing. Most of the recent gain
        comes from a change of drivetrain rather than from engine efficiency.
      </p>
    </div>
  </header>

  <section>
    <h2>Data and method</h2>
    <p>
      The registry is a stock: it records vehicles registered today, not sales, so
      counts by build year reflect survival and export. Three adjustments make
      vintages comparable.
    </p>
    <p>
      <strong>Measurement basis.</strong> Type approval moved from NEDC to WLTP over
      2017&ndash;18, and WLTP returns figures some 20% higher for the same vehicle.
      The registry records both declarations for 1.41 million vehicles, so the
      conversion is estimated from paired within-vehicle observations by powertrain
      and mass band rather than assumed. The pooled estimate, 1.204, reproduces the
      European Commission's assumed 21% without being fitted to it.
    </p>
    <p>
      <strong>On-road divergence.</strong> Declared figures are corrected to
      real-world consumption using gap factors from COM(2024) 122: 20.4% for petrol,
      16.7% for diesel and 267% for plug-in hybrids under WLTP, and a divergence
      rising from about 9% in 2001 to 40% by 2017 under NEDC.
    </p>
    <p>
      <strong>Composition.</strong> Kerb mass rose 31% over the period, and the
      powertrain mix within any segment moves with Dutch tax policy rather than with
      technology. Two quality-adjusted indices control for this: a hedonic
      regression on build-year dummies with mass, power, fuel and body as controls,
      and a chained matched-model index that follows each nameplate against itself.
      The matched-model index requires no conversion, splice or gap assumption,
      since every link compares one model in two adjacent years on the same
      declaration.
    </p>
  </section>

  <section>
    <h2>Results</h2>
    <div class="table-scroll">
      <table>
        <caption>
          Table 1. Mean consumption of combustion-engine vehicles, litres per 100 km,
          on a WLTP-equivalent basis.
        </caption>
        <thead>
          <tr>
            <th scope="col">Basis</th>
            <th scope="col">2000</th>
            <th scope="col">2024</th>
            <th scope="col">Change</th>
          </tr>
        </thead>
        <tbody>
{results_rows}
        </tbody>
      </table>
    </div>
    <p style="margin-top:1.5rem">
      The declared figure implies a halving. Correcting to on-road consumption
      reduces the improvement to 29%, since the laboratory-to-road divergence widened
      over the NEDC era; holding kerb mass at its 2000 level restores it to 40%, so
      roughly 0.92 l/100 km of engineering gain was absorbed by heavier vehicles.
    </p>
    <div class="table-scroll" style="margin-top:1.5rem">
      <table>
        <caption>Table 2. Quality-adjusted efficiency indices, build year 2000 = 100.</caption>
        <thead>
          <tr>
            <th scope="col">Index</th>
            <th scope="col">2024</th>
            <th scope="col">Improvement</th>
            <th scope="col">Per year</th>
          </tr>
        </thead>
        <tbody>
{index_rows}
        </tbody>
      </table>
    </div>
    <p style="margin-top:1.5rem">
      Efficiency at constant specification improved in 22 of 24 years, so the
      apparent deterioration in unadjusted series is compositional and not a
      regression in engine technology. The plateau between 2014 and 2019 survives
      every control: five years of progress was worth 18.8% in 2013, 1.5% in 2019,
      and 15.4% again by 2024.
    </p>
  </section>

  <section>
    <h2>Figures</h2>
    <div class="figures">
{figures}
    </div>
  </section>

  <section>
    <h2>Limitations</h2>
    <p>
      Conversion factors are estimated on vehicles built 2018&ndash;2024 and applied
      to earlier vintages never tested under WLTP; 65% of the fleet carries a
      converted rather than a measured figure. The NEDC-era on-road divergence is
      interpolated between two published anchors. The plug-in hybrid correction is
      the single most influential assumption, and holds only if owners charge as
      often as the monitoring sample did. Size is proxied by kerb mass because
      length is recorded for only 53% of pre-2016 vehicles and the missing half is
      systematically lighter; the length-based estimate is reported alongside.
      Finally, NEDC figures declared after 2018 are back-conversions rather than
      fresh tests, and the population carrying one falls to 5.9% of 2024 vehicles.
    </p>
  </section>

  <footer>
    <p>
      Sources: RDW open data, datasets <code>m9d7-ebf2</code> and
      <code>8ys7-d773</code>, retrieved 13 August 2026. Real-world divergence:
      European Commission, COM(2024) 122 final, 18 March 2024, Table 3. Zero-emission
      figures are zero at the tailpipe only. Code and full results:
      <a href="https://github.com/joris-klingen/fuelecon">joris-klingen/fuelecon</a>.
    </p>
  </footer>

</div>
"""

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(HTML)
print(f"wrote {OUT} ({OUT.stat().st_size / 1e6:.2f} MB)")
