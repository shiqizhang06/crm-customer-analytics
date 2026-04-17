# Claude Code System Prompt — CRM Analytics Project

You are helping me build a CRM customer analytics project in R. This is a portfolio project for job applications to gaming and marketing analytics roles.

## Rules

1. **R only** — all analysis scripts must be in R using tidyverse conventions
2. **Professional code quality** — well-commented, consistent style, error handling
3. **Each script must be modular** — runnable independently after 01_data_cleaning.R
4. **Business framing** — every analysis should conclude with a "so what" statement
5. **Export everything** — every script should save its outputs (plots to outputs/figures/, data to data/processed/)

## Dataset

- UCI Online Retail II (online_retail_II.csv)
- Columns: InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country

## Key R Packages to Use

- tidyverse (dplyr, tidyr, ggplot2, readr, stringr)
- lubridate (date handling)
- BTYDplus or BTYD (CLV models: BG/NBD, Gamma-Gamma)
- scales (formatting)
- RColorBrewer or viridis (color palettes)
- treemapify (optional, for treemap visualization)

## Script Sequence

1. 01_data_cleaning.R — Clean raw data, export cleaned version
2. 02_eda.R — Exploratory analysis with saved plots
3. 03_rfm_segmentation.R — RFM scoring and segment assignment
4. 04_cohort_retention.R — Monthly cohort retention matrix + heatmap
5. 05_clv_prediction.R — BG/NBD + Gamma-Gamma CLV prediction
6. 06_export_for_tableau.R — Consolidate and export all Tableau-ready CSVs

## When writing code:

- Use pipe operator |> or %>% consistently
- Use snake_case for all variable names
- Include section headers with # ---- Section Name ----
- Print summary messages after each major step (e.g., "Cleaned data: X rows, Y customers")
- Save plots with ggsave() at 300 DPI, appropriate dimensions
- Handle edge cases (e.g., customers with only 1 transaction for BTYD)

## When I ask you to "run" or "test" something:

- Show me the expected output structure
- Flag any potential issues before they happen
- Suggest improvements if you see a better approach

## Quality Checks to Always Perform:

- No NA values in final exports
- CustomerID is never missing in analysis data
- Monetary values are positive
- Date ranges make sense
- RFM scores are 1-5
- CLV predictions are non-negative
