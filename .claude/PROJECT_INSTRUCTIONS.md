# CRM Customer Lifecycle & Value Analytics Project

## Context
I am building a portfolio project for job applications to EA (CRM Analyst) and similar marketing analytics roles. This project must be completed in 2-3 days using R as the primary language, with a Tableau dashboard as the final deliverable. The project uses the UCI Online Retail II dataset.

## Objective
Build an end-to-end CRM analytics pipeline that demonstrates:
1. Data cleaning and preparation skills
2. RFM (Recency, Frequency, Monetary) customer segmentation
3. Customer Lifetime Value (CLV) prediction using probabilistic models
4. Cohort retention analysis
5. Tableau-ready data exports for dashboard creation

## Technical Stack
- **Language:** R (primary) — this is intentional because a target job requires R experience
- **Key R packages:** dplyr, tidyr, lubridate, BTYDplus (or BTYD), ggplot2
- **Dashboard:** Tableau (built separately from exported CSVs)
- **Version Control:** Git/GitHub

## Dataset
- UCI Online Retail II (online_retail_II.csv)
- UK-based online gift retailer, transactions from 2009-2011
- ~500K+ records with InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country

## Project Structure
```
crm-customer-analytics/
├── data/
│   ├── raw/                    # Original dataset
│   └── processed/              # Cleaned + exported data for Tableau
├── scripts/
│   ├── 01_data_cleaning.R
│   ├── 02_eda.R
│   ├── 03_rfm_segmentation.R
│   ├── 04_cohort_retention.R
│   ├── 05_clv_prediction.R
│   └── 06_export_for_tableau.R
├── outputs/
│   ├── figures/                # EDA and analysis plots
│   └── tableau_exports/        # CSVs for Tableau
├── dashboard/
│   └── screenshots/            # Tableau dashboard screenshots
├── README.md
└── .gitignore
```

## Detailed Requirements per Script

### 01_data_cleaning.R
- Remove rows where CustomerID is NA
- Remove cancellation transactions (InvoiceNo starting with 'C')
- Remove rows where Quantity <= 0 or UnitPrice <= 0
- Create TotalAmount = Quantity * UnitPrice
- Parse InvoiceDate properly
- Filter to UK customers only (simplify for cleaner analysis)
- Report: total records before/after cleaning, unique customers, date range

### 02_eda.R
- Revenue distribution (histogram, summary stats)
- Purchases per customer distribution
- Revenue by month (time series)
- Top 10 products by revenue
- Customer concentration: what % of customers drive what % of revenue (Pareto)
- Save all plots to outputs/figures/

### 03_rfm_segmentation.R
- Set analysis date as max(InvoiceDate) + 1 day
- Calculate per customer:
  - Recency: days since last purchase
  - Frequency: number of unique invoices
  - Monetary: average spend per invoice
- Score each dimension 1-5 using quintiles
- Create RFM_Score = paste(R_score, F_score, M_score)
- Define segments using standard RFM mapping:
  - Champions: R>=4, F>=4, M>=4
  - Loyal Customers: F>=3, M>=3
  - At Risk: R<=2, F>=2
  - Lost: R<=2, F<=2
  - (and other standard segments)
- Visualize: segment distribution bar chart, segment by avg monetary, treemap
- Export: customer-level RFM data with segments

### 04_cohort_retention.R
- Define cohort by first purchase month
- Calculate retention rate for each cohort at month+1, month+2, etc.
- Create cohort retention matrix
- Visualize as heatmap
- Export cohort matrix for Tableau

### 05_clv_prediction.R
- Prepare data in BTYD format:
  - x = number of repeat transactions
  - t.x = time of last transaction (recency in weeks)
  - T.cal = total observation time per customer (in weeks)
- Fit BG/NBD model (predicted future transactions)
- Fit Gamma-Gamma model (predicted average monetary value)
- Calculate predicted CLV = predicted_transactions * predicted_monetary
- Merge CLV predictions with RFM segments
- Visualize: CLV distribution, CLV by RFM segment, top customers
- Export: customer-level CLV predictions

### 06_export_for_tableau.R
- Consolidate all customer-level data:
  - CustomerID, RFM scores, segment label, CLV prediction, cohort
- Export as clean CSVs:
  - customer_master.csv (one row per customer with all metrics)
  - cohort_retention.csv (retention matrix)
  - monthly_revenue.csv (for time series in Tableau)

## Quality Standards
- All scripts should be well-commented
- Use consistent tidyverse style
- Each script should be runnable independently after 01 is complete
- Include error handling for data edge cases
- README should explain the project clearly for a hiring manager audience

## Important Notes
- This is a REAL project that will go on my resume and GitHub
- Code quality matters — it should look professional
- Analysis should lead to actionable CRM recommendations
- The README should frame this as a business analytics project, not a school assignment
