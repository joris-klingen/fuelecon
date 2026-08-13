"""Generate the results page, embedding the figures as data URIs."""

import base64
import pathlib

FIG_DIR = pathlib.Path(__file__).resolve().parents[1] / "output" / "figures"
OUT = pathlib.Path(__file__).resolve().parent / "results.html"


def img(name: str) -> str:
    data = base64.b64encode((FIG_DIR / f"{name}.png").read_bytes()).decode()
    return f"data:image/png;base64,{data}"


FIGURES = [
    (
        "14_five_year_replacement_saving",
        "What five years newer is worth, same body type and size",
        "Replace your car with one five years younger and roughly the same size. "
        "Through the middle 2010s that bought you nothing \u2014 a 2019 car burned "
        "<em>more</em> than the 2014 car it replaced. By 2024 it is worth about two "
        "litres per 100 km. The second line repeats the calculation on true vehicle "
        "length rather than mass bands; the two bracket the answer at 1.7 to 2.0.",
    ),
    (
        "17_saving_by_basis",
        "The same saving computed three ways",
        "A check on whether the corrections manufactured the shape above. They did "
        "not: the dip is present in the untouched NEDC declarations, which cover "
        "almost every car on both sides up to 2019. The real-world gap ramp deepens "
        "the trough about fourfold without creating it, and the 2024 recovery is "
        "identical on both corrected bases. The raw line stops at 2020, after which "
        "NEDC declarations survive only for a small self-selected residue.",
    ),
    (
        "12_consumption_by_car_type",
        "On-road consumption by build year, one line per body type",
        "Hatchbacks and MPVs improve steadily. Sedans and coupes rise after 2012, "
        "because as the mainstream moved to other shapes those categories were left "
        "to large and fast cars.",
    ),
    (
        "13_consumption_by_size_class",
        "The same by size class",
        "The like-for-like view a buyer would face. The heaviest band dives after "
        "2020, but that is plug-in hybrids arriving rather than engines improving: "
        "by 2024, 82 percent of that band is plug-in.",
    ),
    (
        "16_petrol_by_size_class",
        "Size and powertrain both held fixed: petrol cars only",
        "The sobering figure. With the drivetrain held constant, a petrol car of a "
        "given size improved about 19 percent to 2013 and has been flat since. The "
        "smallest and largest classes now burn <em>more</em> than their 2013 "
        "equivalents. Nearly all of the headline saving is switching drivetrain, "
        "not better engines.",
    ),
    (
        "15_fixed_weight_composition",
        "Fleet consumption at the actual and at the 2000 mix of types and sizes",
        "Holding the composition of body types and size classes at its 2000 shares. "
        "The gap is what buying differently shaped cars cost: 0.44 l/100 km by 2024.",
    ),
    (
        "08_typeapproval_vs_real",
        "Combustion engines: what the test said, and what they burned",
        "Everything converted to one cycle, then corrected to on-road litres. The "
        "lines cross around 2007 and then separate. On-road consumption <em>rises</em> "
        "from 2013 to 2019 while the type-approval figure keeps falling \u2014 the "
        "laboratory-to-road gap was widening faster than the engines were improving.",
    ),
    (
        "11_fleet_constant_mass",
        "On-road consumption, actual and at constant 2000 kerb mass",
        "The gap between the lines is what heavier cars cost. By 2024 it is 0.92 "
        "l/100 km: real engineering gain that went into carrying more car rather "
        "than into using less fuel.",
    ),
    (
        "09_petrol_constant_mass",
        "The same correction within petrol cars alone",
        "Almost nothing happens, and that is the finding. Mean petrol kerb mass "
        "barely moved across the period (1,111 to 1,119 kg), because every time a "
        "larger car electrified it left the petrol category and took its mass with "
        "it. The fleet-wide mass gain is mostly composition.",
    ),
    (
        "10_fleet_real_fuel",
        "Real fuel use per build year, whole fleet against combustion only",
        "The lower line counts cars with no fuel tank as zero litres. The whole "
        "fleet is back to 4.0 l/100 km not because engines improved after 2019 but "
        "because a third of the vintage stopped burning anything.",
    ),
    (
        "01_fleet_by_year_powertrain",
        "Passenger cars in the current fleet, by build year and powertrain",
        "The shape on the left is survival, not sales. Every bar is what is still "
        "registered today, so the thin tail before 2008 is scrappage and export "
        "working backwards through the vintages. The colour shift after 2019 is the "
        "part that is real change rather than attrition.",
    ),
    (
        "02_powertrain_share_by_year",
        "Powertrain shares within each vintage",
        "The same data as proportions, which takes survival out of the picture: "
        "within a single vintage, what fraction of the survivors is electrified. "
        "Diesel peaks around 2011 and then retreats steadily.",
    ),
    (
        "04_co2_by_test_cycle",
        "Type-approval CO2 per build year, by test cycle",
        "Two series, never one. NEDC runs 2000 to 2019 and falls by a third. WLTP "
        "starts in 2018 at a level 20 percent higher for cars that are no worse — "
        "that offset is the measurement change, not the cars.",
    ),
    (
        "05_fleet_vs_combustion_co2",
        "Mean tailpipe CO2 per build year: whole fleet versus combustion only",
        "The figure the whole analysis turns on. The two lines are the same "
        "vintages, counted twice: once with zero-tailpipe cars entered at 0 g/km, "
        "once with only the cars that burn something. They track each other until "
        "2019 and then separate. That gap is electrification.",
    ),
    (
        "06_co2_by_powertrain",
        "CO2 per build year by powertrain",
        "Diesel is the line that surprises. It climbs after 2019 — not because "
        "diesel engines got worse, but because diesel retreated to heavy vehicles, "
        "taking its average with it.",
    ),
    (
        "07_co2_per_tonne_petrol",
        "Petrol cars: CO2 per kilometre and per tonne of kerb mass, NEDC",
        "Normalising by mass separates engine improvement from the cars getting "
        "bigger. Per kilometre falls faster than per tonne, which is the part of "
        "the gain that was spent on carrying more car.",
    ),
    (
        "03_top_models",
        "The twenty most numerous nameplates, build years 2000-2024",
        "Small cars dominate the surviving fleet — the Polo alone is 283 thousand "
        "cars. Model names come from a free-text registry field and are normalised "
        "conservatively, so treat the ordering as indicative at the margin.",
    ),
]

NUMBERS = [
    ("Type approval", "9.43 l/100km", "2000", "4.54 l/100km", "2024", "-52%", "down"),
    ("\u2026on the road", "8.57 l/100km", "2000", "6.09 l/100km", "2024", "-29%", "down"),
    ("\u2026at constant 2000 mass", "8.57 l/100km", "2000", "5.17 l/100km", "2024", "-40%", "down"),
    ("Fleet, electric as 0 l", "8.57 l/100km", "2000", "4.04 l/100km", "2024", "-53%", "down"),
    ("Mean kerb mass", "1,126 kg", "2000", "1,407 kg", "2024", "+25%", "up"),
]

TRAPS = [
    (
        "Stock, not sales",
        "The registry is a snapshot of what is registered today. Every count is a "
        "survival count, so the pre-2008 tail says nothing about how many cars were "
        "sold in those years.",
    ),
    (
        "NEDC is not WLTP",
        "Type approval switched cycles between September 2017 and September 2018, and "
        "WLTP returns figures 15 to 25 percent higher for a physically identical car. "
        "A single series across the switch shows an efficiency regression that never "
        "happened.",
    ),
    (
        "Electric cars have no CO2 record",
        "RDW leaves the CO2 field null for battery-electric cars rather than writing a "
        "zero. Aggregating over non-null CO2 therefore drops precisely the cars that "
        "are displacing combustion, and the fleet average stops meaning anything after "
        "about 2020.",
    ),
    (
        "Hybrids share a fuel list",
        "A plug-in hybrid and a self-charging hybrid carry identical fuel rows. Only "
        "klasse_hybride_elektrisch_voertuig separates them. Classifying on the fuel "
        "list alone moves 775 thousand self-charging hybrids into the plug-in bucket "
        "and roughly triples it.",
    ),
]


def figure_block(i, name, title, note):
    return f"""      <figure class="fig">
        <img src="{img(name)}" alt="{title}" loading="lazy" />
        <figcaption>
          <span class="fig-no">Figure {i}</span>
          <h3>{title}</h3>
          <p>{note}</p>
        </figcaption>
      </figure>"""


rows = "\n".join(
    f"""            <tr>
              <th scope="row">{label}</th>
              <td class="num">{a}</td><td class="yr">{ay}</td>
              <td class="num">{b}</td><td class="yr">{by}</td>
              <td class="num delta {d}">{chg}</td>
            </tr>"""
    for label, a, ay, b, by, chg, d in NUMBERS
)

traps = "\n".join(
    f"""        <div class="trap">
          <h3>{t}</h3>
          <p>{d}</p>
        </div>"""
    for t, d in TRAPS
)

figures = "\n".join(
    figure_block(i, name, title, note) for i, (name, title, note) in enumerate(FIGURES, 1)
)

HTML = f"""<title>Nine Million Cars</title>
<style>
  /* Palette taken from the ggcpb design tokens, so the page and the figures
     inside it are one system rather than two that happen to sit together. */
  :root {{
    --ground:      #ffffff;
    --surface:     #eef8ff;   /* cpb_bg, the ground the figures are drawn on */
    --plate:       #eef8ff;   /* figure plate; stays light in both themes */
    --ink:         #14294a;
    --ink-soft:    #51678a;
    --ink-faint:   #7d90ad;
    --blue:        #005faf;   /* cpb qualitative 6 */
    --magenta:     #e6006e;   /* cpb qualitative 2 */
    --plum:        #820050;
    --rule:        #c9d1da;   /* cpb_grid */
    --rule-soft:   #e2e9f0;

    --measure: 68ch;
    --wide: 62rem;
    --step-0: 1rem;
    --step-1: 1.1875rem;
    --step-2: 1.5rem;
    --step-3: 2.125rem;
    --step-4: 3.25rem;

    --sans: "RO Sans", "Rijksoverheid Sans Text", "Frutiger", "Segoe UI",
            "Noto Sans", system-ui, sans-serif;
    --mono: "SFMono-Regular", "JetBrains Mono", "Menlo", "Consolas", monospace;
  }}

  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{
      --ground:    #0b1a2d;
      --surface:   #122740;
      --ink:       #dfeaf6;
      --ink-soft:  #9db3cd;
      --ink-faint: #6f87a5;
      --blue:      #87d2ff;   /* cpb qualitative 5, legible on navy */
      --magenta:   #f08bb8;   /* cpb sequential 3, legible on navy */
      --plum:      #fad1e8;
      --rule:      #2c445f;
      --rule-soft: #1c3149;
    }}
  }}

  :root[data-theme="dark"] {{
    --ground:    #0b1a2d;
    --surface:   #122740;
    --ink:       #dfeaf6;
    --ink-soft:  #9db3cd;
    --ink-faint: #6f87a5;
    --blue:      #87d2ff;
    --magenta:   #f08bb8;
    --plum:      #fad1e8;
    --rule:      #2c445f;
    --rule-soft: #1c3149;
  }}

  /* The house typeface is licensed CPB tooling, so it is referenced from the
     reader's own machine rather than shipped with the page. Colleagues with it
     installed see the real face; everyone else gets a humanist fallback. */
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
    font-size: var(--step-0);
    line-height: 1.6;
    -webkit-font-smoothing: antialiased;
  }}

  .wrap {{
    max-width: var(--wide);
    margin-inline: auto;
    padding: clamp(1.5rem, 4vw, 3.5rem) clamp(1.1rem, 4vw, 2.5rem) 5rem;
    display: flex;
    flex-direction: column;
    gap: 3.5rem;
  }}

  h1, h2, h3 {{ text-wrap: balance; line-height: 1.15; }}

  /* ---- masthead ---- */
  .masthead {{ display: flex; flex-direction: column; gap: 1.5rem; }}
  .eyebrow {{
    font-size: 0.75rem;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--ink-faint);
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem 1.25rem;
  }}
  h1 {{
    font-size: var(--step-4);
    font-weight: 700;
    letter-spacing: -0.02em;
    margin: 0;
  }}
  .standfirst {{
    font-size: var(--step-1);
    color: var(--ink-soft);
    max-width: var(--measure);
    margin: 0;
  }}

  /* The headline finding, coloured with the two line colours it comes from. */
  .headline {{
    display: flex;
    align-items: baseline;
    flex-wrap: wrap;
    gap: 0.35rem 1rem;
    padding: 1.5rem 0;
    border-block: 1px solid var(--rule);
    font-variant-numeric: tabular-nums;
  }}
  .headline .from {{ font-size: var(--step-3); font-weight: 700; color: var(--magenta); }}
  .headline .arrow {{ font-size: var(--step-2); color: var(--ink-faint); }}
  .headline .to {{ font-size: var(--step-3); font-weight: 700; color: var(--blue); }}
  .headline .unit {{ font-size: var(--step-1); color: var(--ink-soft); max-width: 22ch; }}
  .headline .gloss {{ color: var(--ink-soft); flex: 1 1 18rem; min-width: 0; }}

  /* ---- prose ---- */
  section > p, .prose p {{ max-width: var(--measure); }}
  h2 {{
    font-size: var(--step-2);
    font-weight: 700;
    margin: 0 0 1rem;
    letter-spacing: -0.01em;
  }}
  .section-lede {{ color: var(--ink-soft); margin: 0 0 2rem; max-width: var(--measure); }}
  p {{ margin: 0 0 1rem; }}
  a {{ color: var(--blue); text-decoration-thickness: 1px; text-underline-offset: 2px; }}
  a:focus-visible {{ outline: 2px solid var(--magenta); outline-offset: 3px; border-radius: 2px; }}
  code {{ font-family: var(--mono); font-size: 0.9em; }}

  /* ---- numbers table ---- */
  .table-scroll {{ overflow-x: auto; }}
  table {{ border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }}
  caption {{
    text-align: left;
    color: var(--ink-faint);
    font-size: 0.8125rem;
    padding-bottom: 0.75rem;
  }}
  th, td {{ padding: 0.6rem 0.75rem; text-align: left; white-space: nowrap; }}
  thead th {{
    font-size: 0.7rem;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--ink-faint);
    font-weight: 400;
    border-bottom: 1px solid var(--rule);
  }}
  tbody th {{ font-weight: 400; padding-left: 0; }}
  tbody tr + tr th, tbody tr + tr td {{ border-top: 1px solid var(--rule-soft); }}
  .num {{ font-weight: 700; }}
  .yr {{ color: var(--ink-faint); font-size: 0.8125rem; padding-left: 0; }}
  .delta {{ text-align: right; }}
  .delta.down {{ color: var(--blue); }}
  .delta.up {{ color: var(--magenta); }}

  /* ---- figures ---- */
  .figures {{ display: flex; flex-direction: column; gap: 3rem; }}
  .fig {{ margin: 0; display: flex; flex-direction: column; gap: 1rem; }}
  .fig img {{
    display: block;
    width: 100%;
    height: auto;
    background: var(--plate);
    border: 1px solid var(--rule);
  }}
  figcaption {{ display: flex; flex-direction: column; gap: 0.4rem; }}
  .fig-no {{
    font-size: 0.7rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--magenta);
  }}
  figcaption h3 {{ font-size: var(--step-1); font-weight: 700; margin: 0; }}
  figcaption p {{ color: var(--ink-soft); max-width: var(--measure); margin: 0; }}

  /* ---- traps ---- */
  .traps {{
    display: grid;
    gap: 1.5rem;
    grid-template-columns: repeat(auto-fit, minmax(21rem, 1fr));
  }}
  .trap {{
    background: var(--surface);
    padding: 1.25rem 1.35rem;
    border-top: 2px solid var(--plum);
  }}
  .trap h3 {{ font-size: 1rem; font-weight: 700; margin: 0 0 0.5rem; }}
  .trap p {{ color: var(--ink-soft); font-size: 0.9375rem; margin: 0; }}

  /* ---- reproduce ---- */
  pre {{
    background: var(--surface);
    border-left: 2px solid var(--blue);
    padding: 1rem 1.25rem;
    overflow-x: auto;
    font-family: var(--mono);
    font-size: 0.875rem;
    line-height: 1.7;
    margin: 0 0 1rem;
  }}

  footer {{
    border-top: 1px solid var(--rule);
    padding-top: 1.5rem;
    color: var(--ink-faint);
    font-size: 0.875rem;
  }}

  @media (prefers-reduced-motion: reduce) {{
    * {{ animation: none !important; transition: none !important; }}
  }}
</style>

<div class="wrap">

  <header class="masthead">
    <div class="eyebrow">
      <span>RDW open data</span>
      <span>Build years 2000-2024</span>
      <span>9,529,597 cars</span>
    </div>
    <h1>Nine million cars</h1>
    <p class="standfirst">
      How much fuel efficiency actually improved in the Dutch passenger car fleet,
      and how many of each car is left on the road. Drawn from the full vehicle
      registry &mdash; 9.5 million cars joined to 16.9 million fuel records &mdash;
      and corrected onto a single basis so that a car from 2000 and a car from 2024
      can be compared at all.
    </p>
    <div class="headline">
      <span class="from">2.0</span>
      <span class="unit">l/100 km saved by a five-year-newer car of the same size</span>
      <span class="gloss">
        Almost none of that is a better engine. Hold the drivetrain fixed as well
        and a petrol car of a given size has not improved since 2013 &mdash; the
        saving is people buying hybrids.
      </span>
    </div>
  </header>

  <section>
    <h2>What the fleet looks like</h2>
    <p class="section-lede">
      Nine and a half million passenger cars built between 2000 and 2024 are
      registered in the Netherlands today.
    </p>
    <div class="prose">
      <p>
        The largest surviving vintage is 2019, with 581 thousand cars still on the
        road. Just over a fifth of the fleet was built in 2000-2009. Volkswagen is
        the largest make at 11.7 percent, and the Volkswagen Polo the most numerous
        single nameplate at 283 thousand cars.
      </p>
      <p>
        Across the whole 2000-2024 fleet the powertrain split is petrol 71.3
        percent, self-charging hybrid 8.1, diesel 7.7, battery-electric 6.5,
        plug-in hybrid 5.6, and LPG 0.7. Read those as the composition of what
        survives, not of what was ever sold.
      </p>
    </div>
  </section>

  <section>
    <h2>Replacing your car</h2>
    <p class="section-lede">
      Same body type, same size class &mdash; what does five years of progress buy?
    </p>
    <div class="table-scroll">
      <table>
        <caption>On-road litres per 100 km, weighted by the stock of the newer car.</caption>
        <thead>
          <tr>
            <th scope="col">Newer car</th>
            <th scope="col" colspan="2">Replaces</th>
            <th scope="col" colspan="2">Saving</th>
            <th scope="col">Basis</th>
          </tr>
        </thead>
        <tbody>
          <tr><th scope="row">2010</th><td class="num">2005</td><td class="yr"></td>
              <td class="num">0.70 l</td><td class="yr">8.7%</td>
              <td class="num delta">modelled</td></tr>
          <tr><th scope="row">2013</th><td class="num">2008</td><td class="yr"></td>
              <td class="num">1.28 l</td><td class="yr">16.0%</td>
              <td class="num delta">modelled</td></tr>
          <tr><th scope="row">2019</th><td class="num">2014</td><td class="yr"></td>
              <td class="num delta up">-0.74 l</td><td class="yr">-10.8%</td>
              <td class="num delta">modelled</td></tr>
          <tr><th scope="row">2024</th><td class="num">2019</td><td class="yr"></td>
              <td class="num delta down">2.02 l</td><td class="yr">25.1%</td>
              <td class="num delta">measured</td></tr>
        </tbody>
      </table>
    </div>
    <div class="prose" style="margin-top:2rem">
      <p>
        Only the last row is a clean comparison: both sides carry a measured WLTP
        figure, so no conversion assumption enters. Repeating it on true vehicle
        length rather than mass bands gives 1.66 l/100 km, so take the honest answer
        as <strong>roughly 1.7 to 2.0 litres per 100 km, about a fifth</strong>.
      </p>
      <p>
        Cars built through the middle 2010s were worse than the five-year-older car
        they replaced. Part of that is measured &mdash; same-size cars kept gaining
        mass and power &mdash; and part is the widening laboratory gap, which those
        rows inherit as an assumption.
      </p>
      <p>
        The uncomfortable part: hold the drivetrain fixed as well and a petrol car
        of a given size improved about 19 percent to 2013 and has been flat since,
        with the smallest and largest classes now slightly worse. Nearly all of the
        saving above is people buying hybrids rather than engines getting better.
      </p>
    </div>
  </section>

  <section>
    <h2>The numbers</h2>
    <p class="section-lede">
      All in litres per 100 km, on one cycle, for cars that burn fuel. Each row
      strips out one more distortion.
    </p>
    <div class="table-scroll">
      <table>
        <caption>Fleet means over cars that burn fuel, except the last row.
          Cycle conversion estimated from RDW; gap factors from COM(2024) 122.</caption>
        <thead>
          <tr>
            <th scope="col">Series</th>
            <th scope="col" colspan="2">From</th>
            <th scope="col" colspan="2">To</th>
            <th scope="col">Change</th>
          </tr>
        </thead>
        <tbody>
{rows}
        </tbody>
      </table>
    </div>
    <div class="prose" style="margin-top:2rem">
      <p>
        Read down the table. Type approval claims a halving. Correcting to what cars
        actually burned cuts it to 29 percent, because the laboratory-to-road gap
        widened from 9 percent to 40 percent over the NEDC era &mdash; improvement
        that existed on paper only. Holding kerb mass at its 2000 level restores it
        to 40 percent: roughly <strong>0.92 l/100 km</strong> of genuine engineering
        gain went into carrying heavier cars instead of saving fuel.
      </p>
      <p>
        The last row is the whole fleet with electric cars entered at zero litres.
        It returns to 53 percent only because 30 percent of the 2024 vintage burns
        nothing at all.
      </p>
    </div>
  </section>

  <section>
    <h2>How the corrections work</h2>
    <p class="section-lede">
      None of this is a black box. Each correction is either estimated from these
      cars or sourced to a named document.
    </p>
    <div class="traps">
      <div class="trap">
        <h3>One cycle, estimated not assumed</h3>
        <p>
          1,411,000 cars carry both an NEDC and a WLTP declaration on the same
          registry record &mdash; the same car, measured both ways. Factors are
          fitted per powertrain and kerb-mass band: petrol 1.16&ndash;1.20, diesel
          1.22&ndash;1.29. They pool to 1.204, against the European Commission's
          assumed 21 percent, an independent check the estimate was not fitted to.
        </p>
      </div>
      <div class="trap">
        <h3>Litres actually burned</h3>
        <p>
          WLTP-era gaps come from Commission report COM(2024) 122, built on on-board
          monitoring of 617,194 cars: petrol +20.4 percent, diesel +16.7 percent,
          plug-in hybrid +267 percent. The NEDC-era gap runs from about 9 percent in
          2001 to 40 percent by 2017.
        </p>
      </div>
      <div class="trap">
        <h3>Constant kerb mass</h3>
        <p>
          The consumption-per-kilogram slope is identified within build year &mdash;
          a heavy against a light car of the same vintage, so engine technology is
          held fixed. The pooled combustion slope is 0.0033 l/100 km per kg.
        </p>
      </div>
      <div class="trap">
        <h3>What is still assumed</h3>
        <p>
          Conversion factors estimated on 2018&ndash;2024 cars are applied back to
          cars built from 2000, which were never WLTP tested. A converted 2003
          figure is an estimate of what WLTP would have said, not a measurement.
          65 percent of the fleet carries a converted figure.
        </p>
      </div>
    </div>
  </section>

  <section>
    <h2>Figures</h2>
    <div class="figures">
{figures}
    </div>
  </section>

  <section>
    <h2>Four ways to get this wrong</h2>
    <p class="section-lede">
      Each of these produces a confident, plausible, incorrect answer. All four are
      handled in the transformation step and documented where they are handled.
    </p>
    <div class="traps">
{traps}
    </div>
  </section>

  <section>
    <h2>Reproduce it</h2>
    <p class="section-lede">
      Nothing here is committed as data. Both commands run from a clean checkout.
    </p>
    <pre><code>uv sync
uv run fuelecon all           # download, build the warehouse, export CSV
Rscript R/run_analysis.R      # figures and headline numbers</code></pre>
    <div class="prose">
      <p>
        The download takes about twelve minutes over the RDW API and is resumable.
        DuckDB does the row crunching once; R reads the resulting aggregate tables
        and draws the figures in CPB house style via
        <a href="https://github.com/joris-klingen/ggcpb">ggcpb</a>.
      </p>
    </div>
  </section>

  <footer>
    Source: <a href="https://opendata.rdw.nl">RDW open data</a>, datasets
    <code>m9d7-ebf2</code> and <code>8ys7-d773</code>, retrieved 13 August 2026.
    Real-world gap factors: European Commission, COM(2024) 122 final, 18.3.2024,
    Table 3. Zero tailpipe emissions are zero at the tailpipe only; generation
    emissions sit outside the registry's scope.
  </footer>

</div>
"""

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(HTML)
print(f"wrote {OUT} ({OUT.stat().st_size / 1e6:.2f} MB)")
