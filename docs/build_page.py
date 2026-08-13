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
    ("NEDC median CO2", "180 g/km", "2000", "119 g/km", "2019", "-34%", "down"),
    ("NEDC median consumption", "7.4 l/100km", "2000", "5.0 l/100km", "2019", "-32%", "down"),
    ("WLTP median CO2", "142 g/km", "2018", "114 g/km", "2024", "-20%", "down"),
    ("Fleet mean tailpipe CO2", "190 g/km", "2000", "71 g/km", "2024", "-62%", "down"),
    ("Petrol only, WLTP", "144 g/km", "2019", "124 g/km", "2024", "-14%", "down"),
    ("Diesel only, WLTP", "156 g/km", "2019", "253 g/km", "2024", "+62%", "up"),
    ("Mean kerb mass", "1,187 kg", "2000", "1,556 kg", "2024", "+31%", "up"),
    ("Mean power", "88 kW", "2000", "104 kW", "2024", "+18%", "up"),
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
  .headline .unit {{ font-size: var(--step-1); color: var(--ink-soft); }}
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
      and how many of each car is left on the road. Every figure is drawn from the
      full vehicle registry: 9.5 million cars joined to 16.9 million fuel and
      emissions records.
    </p>
    <div class="headline">
      <span class="from">190</span>
      <span class="arrow">&rarr;</span>
      <span class="to">71</span>
      <span class="unit">g CO2/km</span>
      <span class="gloss">
        Mean tailpipe CO2, build year 2000 against 2024 &mdash; a 62 percent fall.
        Most of the drop after 2019 is electrification rather than better engines.
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
    <h2>The numbers</h2>
    <p class="section-lede">
      Efficiency improved substantially, but the size of the improvement depends
      entirely on what you hold fixed.
    </p>
    <div class="table-scroll">
      <table>
        <caption>Type-approval figures from the RDW registry. Medians unless stated.</caption>
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
        Diesel is the row that looks wrong and is not. Its average rises because
        diesel retreated to heavy vehicles: the mean kerb mass of a new diesel went
        from 1,669 kg in 2019 to 2,538 kg in 2024. Over the same years the mean
        petrol car got <em>lighter</em>, from 1,203 kg to 1,128 kg, as the larger
        cars electrified. Neither series is a clean reading of engine development
        on its own.
      </p>
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
    Zero tailpipe emissions are zero at the tailpipe only; generation emissions sit
    outside the registry's scope.
  </footer>

</div>
"""

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(HTML)
print(f"wrote {OUT} ({OUT.stat().st_size / 1e6:.2f} MB)")
