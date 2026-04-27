# crm-customer-analytics
Customer Lifecycle & Value Analytics | RFM Segmentation, Cohort Retention, CLV Prediction

## Project overview

End-to-end CRM analytics pipeline on the [UCI Online Retail II dataset](https://archive.ics.uci.edu/dataset/502/online+retail+ii) (UK customers, Dec 2009–Dec 2011). Covers data cleaning, exploratory analysis, RFM segmentation, cohort retention, and BG/NBD + Gamma-Gamma customer lifetime value prediction. Outputs are delivered in two dashboards: a Tableau workbook (executive-facing) and a Streamlit app (operational self-serve).

## Pipeline

| Script | Purpose |
|--------|---------|
| `01_data_cleaning.R` | Clean raw data — remove nulls, cancellations, non-UK; export RDS + CSV |
| `02_eda.R` | Exploratory analysis — revenue distribution, seasonality, Pareto concentration |
| `03_rfm_segmentation.R` | RFM scoring (1–5), segment assignment, treemap and heatmap |
| `04_cohort_retention.R` | Monthly cohort retention matrix + heatmap |
| `05_clv_prediction.R` | BG/NBD transaction model + Gamma-Gamma spend model; 12-month CLV |
| `06_export_for_tableau.R` | Build Tableau-ready flat files in `outputs/tableau/` |
| `07_load_to_sqlite.R` | Load all exports into `data/processed/crm.db` for Streamlit |

## Key findings

- **5,350 UK registered customers** across 725K transactions
- **RFM:** At Risk is the largest segment (1,071 customers, 20%); Champions + Loyal + Potential Loyalists form a 43% high-value core
- **Cohort retention:** 79% M0→M1 cliff; customers who return at M1 stabilise at ~19% through M6; Dec cohorts have 8% M1 retention (Christmas acquisition quality problem)
- **CLV model:** MAE lift 39.4% over naive baseline; correlation 0.832; top decile captures 58% of holdout revenue (5.8× lift)
- **£6.32M** predicted 12-month CLV from existing base; Champions (12% of customers) account for 51%

## Dashboards

### Tableau (manual, executive-facing)
Built manually in Tableau Desktop. Core views: KPI summary, segment distribution, cohort retention heatmap, CLV by segment.

### Streamlit (AI-assisted, operational)
```bash
# From project root
Rscript scripts/07_load_to_sqlite.R   # build the DB (run once)
pip install -r app/requirements.txt
streamlit run app/streamlit_app.py
```

Three pages:
- **Customer Lookup** — individual profile with RFM scores, CLV, purchase history chart, and segment-specific CRM recommendation
- **Segment Explorer** — KPI cards, segment comparison charts, revenue treemap, recommended action
- **Cohort Retention** — interactive heatmap with worst-drop highlights and key insight summary

The Streamlit app goes further than Tableau with a Customer Lookup tool and direct SQL queries against the SQLite DB.

## Development efficiency

Both dashboards visualise the same underlying data (5,350 UK customers, RFM segments, 24-month cohort matrix, BG/NBD + Gamma-Gamma CLV predictions). Core views — KPI summary, segment distribution, cohort retention heatmap, CLV by segment — are present in both.

| | Tableau (Manual) | Streamlit (AI-Assisted) |
|---|---|---|
| Build time | ___ hrs | ___ hrs |
| Method | Manual drag-and-drop | Vibe coding with Claude Code |
| Strength | Cross-filter interactivity | Operational lookup + SQL flexibility |

### Phase breakdown

| Phase | Description | Est. traditional time | Actual time | Speedup |
|-------|-------------|----------------------|-------------|---------|
| 01–02 | Cleaning + EDA | | | |
| 03 | RFM segmentation | | | |
| 04 | Cohort retention | | | |
| 05 | CLV prediction | | | |
| 06–07 | Exports + SQLite | | | |
| App | Streamlit build | | | |
| Tableau | Dashboard build | | | |
| README | Documentation | | | |

### Where AI helped most
- R syntax and tidyverse boilerplate (R is not my primary language)
- CLV model diagnostics iteration — quickly surfacing the P(alive)=1.0 edge case, M3>M1 seasonal artifact, and naive baseline comparison
- Streamlit frontend scaffolding — layout, CSS, Plotly theming
- Business framing of findings — translating model outputs into actionable CRM language

### Where I drove the work
- Analysis architecture and script sequencing decisions
- Business interpretation — what the cohort cliff means for campaign timing, what Can't Lose Them vs At Risk prioritisation implies
- Data quality decisions — what to filter, what to keep (Manual entries, guest checkouts)
- Dashboard design — what views belong in Tableau vs Streamlit, what a stakeholder actually needs to see
