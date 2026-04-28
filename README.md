# CRM Customer Analytics
Customer Lifecycle & Value Analytics — RFM Segmentation · Cohort Retention · CLV Prediction

---

## Overview

End-to-end CRM analytics pipeline on the [UCI Online Retail II dataset](https://archive.ics.uci.edu/dataset/502/online+retail+ii) (UK customers, Dec 2009–Dec 2011). Covers data cleaning, exploratory analysis, RFM segmentation, cohort retention, and BG/NBD + Gamma-Gamma customer lifetime value prediction.

Delivered in two dashboards with intentionally different purposes:
- **Tableau** — executive-facing broadcast dashboard for known questions and a known audience
- **Streamlit** — self-serve operational tool that lets stakeholders explore questions the analyst didn't anticipate, including per-customer lookup and segment-specific CRM recommendations

The self-serve design addresses a real industry pain point: analysts spending recurring time on one-off "can you check customer X?" or "what should we do about At Risk?" requests. Both of those are now answered by the tool itself.

---

## Key Findings

- **5,350 UK customers** across 725K transactions (Dec 2009–Dec 2011)
- **77% M0→M1 cliff** — the majority of first-time buyers never return; the critical intervention window is within 30 days
- **Champions (12% of customers)** account for **51% of predicted 12-month revenue** — protecting this segment is the single highest-ROI action
- **Can't Lose Them** segment: avg CLV comparable to Loyal Customers (£1,038) but P(alive) has dropped to 71.8% — most urgent win-back priority
- **CLV model:** MAE 39.4% better than naive baseline; top decile captures 58% of holdout revenue (5.8× lift)
- **£6.32M** predicted 12-month CLV from the existing base; Dec cohorts show lowest M1 retention (8%), confirming peak-season acquired customers are predominantly one-time buyers

---

## Dashboards

### Streamlit — Self-Serve Operational Tool

```bash
Rscript scripts/07_load_to_sqlite.R   # build SQLite DB (run once after R pipeline)
pip install -r app/requirements.txt
streamlit run app/streamlit_app.py
```

**Page 1 — Customer Lookup**

Look up any of the 5,350 customers by ID. Returns RFM scores, predicted 12-month CLV, CLV percentile rank, P(alive), purchase history chart, and a segment-specific CRM action recommendation. Hover on the segment badge or RFM bars for inline definitions.

![Customer Lookup](dashboard/screenshots/01_customer_lookup.png)
![Segment Definitions](dashboard/screenshots/02_segment_definitions.png)

**Page 2 — Segment Explorer**

Select any of the 9 RFM segments to see deep-dive KPIs (recency, frequency, AOV, CLV) and a tailored CRM recommendation. Scroll for cross-segment comparisons: customer count, avg predicted CLV, and revenue share treemap (coloured by CLV, sized by customer count).

![Segment Explorer — KPIs and charts](dashboard/screenshots/03_segment_explorer.png)
![Segment Explorer — Treemap and recommendation](dashboard/screenshots/04_segment_explorer_deepdive.png)

**Page 3 — Cohort Retention**

Monthly cohort retention heatmap across 25 cohorts. Filterable by segment. Highlights the five worst M0→M1 drops and surfaces the Q4 seasonal retention bias and acquisition quality problem.

![Cohort Retention Heatmap](dashboard/screenshots/05_cohort_retention_heatmap.png)

---

### Tableau — Executive Dashboard

Single-page dashboard built in Tableau Desktop. Core views: KPI summary, segment distribution, cohort retention heatmap, CLV by segment. Segments are clickable — selecting a segment cross-filters the heatmap and CLV chart.

![Tableau Dashboard](dashboard/screenshots/06_tableau_dashboard.png)

---

## Analytics Pipeline

| Script | Purpose |
|--------|---------|
| `01_data_cleaning.R` | Remove nulls, cancellations, non-UK rows; export cleaned RDS + CSV |
| `02_eda.R` | Revenue distribution, seasonality, Pareto concentration — saved plots |
| `03_rfm_segmentation.R` | RFM scoring (quintiles 1–5), 9-segment assignment, treemap and heatmap |
| `04_cohort_retention.R` | Monthly cohort retention matrix + heatmap; segment-level densification |
| `05_clv_prediction.R` | BG/NBD transaction model + Gamma-Gamma spend model; 12-month CLV |
| `06_export_for_tableau.R` | Flat files for Tableau: customer master, transactions, cohort, segment summary |
| `07_load_to_sqlite.R` | Load all exports into `data/processed/crm.db` for Streamlit SQL queries |

---

## AI-Assisted Development

### Dashboard scope comparison

| | Tableau | Streamlit |
|---|---|---|
| **Build time** | 1.5 hrs | 2.5 hrs |
| **Pages** | 1 | 3 |
| **Components** | 4 KPIs · treemap · 2 bar charts · heatmap | Customer lookup · segment deep-dive · cohort heatmap · CSS design system · SQLite SQL layer · hover tooltips |
| **Interaction** | Cross-filter (segment → heatmap) | Per-customer SQL queries · dropdown filters · hover definitions · segment recommendations |
| **Method** | Manual drag-and-drop | Vibe coding with Claude Code |

Streamlit took more total hours but delivered 3× the scope and a qualitatively different capability — self-serve lookup that Tableau cannot replicate without a server-side data connection and custom extensions.

### Where AI helped most
- R syntax and tidyverse boilerplate (R is not my primary language)
- CLV model diagnostics — surfacing the P(alive)=1.0 edge case, M3>M1 seasonal artifact, and naive baseline comparison
- Streamlit frontend — layout, CSS theming, Plotly configuration, SQLite integration
- Business framing — translating model outputs into segment-specific CRM recommendations

### Where I drove the work
- Analysis architecture and script sequencing
- Business interpretation — what the cohort cliff means for campaign timing, Can't Lose Them vs At Risk prioritisation, CLV decile targeting strategy
- Data quality decisions — what to filter, what to keep
- Dashboard design — what belongs in Tableau vs Streamlit, what a stakeholder actually needs to see
- All findings, recommendations, and so-what statements
