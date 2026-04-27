# ============================================================
# 06_export_for_tableau.R
# CRM Customer Analytics — Tableau-Ready Exports
#
# Builds four clean, flat tables for Tableau:
#   1. customer_master.csv     — one row per customer, all dimensions
#   2. transactions.csv        — transaction-level data for time series
#   3. cohort_retention.csv    — cohort × period matrix (pass-through)
#   4. segment_summary.csv     — RFM + CLV aggregates per segment
#
# Input:  data/processed/retail_clean.rds
#         data/processed/rfm_segments.rds
#         data/processed/clv_predictions.rds
#         data/processed/cohort_retention.rds
#         data/processed/clv_segment_summary.csv
# Output: outputs/tableau/*.csv
# ============================================================

library(tidyverse)
library(lubridate)
library(scales)

# ---- Load Inputs ----

required <- c(
  "data/processed/retail_clean.rds",
  "data/processed/rfm_segments.rds",
  "data/processed/clv_predictions.rds",
  "data/processed/cohort_retention.rds",
  "data/processed/clv_segment_summary.csv"
)
missing <- required[!file.exists(required)]
if (length(missing) > 0)
  stop("Missing inputs — run scripts 01–05 first:\n  ", paste(missing, collapse = "\n  "))

df      <- readRDS("data/processed/retail_clean.rds")
rfm     <- readRDS("data/processed/rfm_segments.rds")
clv     <- readRDS("data/processed/clv_predictions.rds")
cohort  <- readRDS("data/processed/cohort_retention.rds")
clv_seg <- read_csv("data/processed/clv_segment_summary.csv", show_col_types = FALSE)

dir.create("outputs/tableau", recursive = TRUE, showWarnings = FALSE)

message(sprintf("Loaded: %s customers (RFM), %s customers (CLV), %s transactions",
                comma(nrow(rfm)), comma(nrow(clv)), comma(nrow(df))))

# ---- Table 1: Customer Master ----
# One row per customer — all 5,350 customers.
# CLV columns are NA for the 741 customers acquired after the Jun 2011
# calibration cutoff (they have RFM scores but no CLV model history).

customer_base <- df |>
  group_by(customer_id) |>
  summarise(
    first_purchase_date = min(invoice_date_only),
    last_purchase_date  = max(invoice_date_only),
    total_revenue       = sum(total_amount),
    total_orders        = n_distinct(invoice_no),
    .groups             = "drop"
  ) |>
  mutate(cohort_month = floor_date(first_purchase_date, "month"))

clv_clean <- clv |>
  select(
    customer_id,
    cal_frequency      = x,
    p_alive,
    exp_transactions_12m,
    exp_spend,
    clv_12m
  ) |>
  mutate(
    clv_decile = ntile(clv_12m, 10)
  )

customer_master <- customer_base |>
  left_join(
    rfm |> select(customer_id, recency, frequency, monetary,
                  r_score, f_score, m_score, rfm_score, segment),
    by = "customer_id"
  ) |>
  left_join(clv_clean, by = "customer_id") |>
  select(
    customer_id,
    segment, rfm_score, r_score, f_score, m_score,
    recency, frequency, monetary,
    first_purchase_date, last_purchase_date, cohort_month,
    total_revenue, total_orders,
    p_alive, exp_transactions_12m, exp_spend, clv_12m, clv_decile,
    cal_frequency
  ) |>
  mutate(
    customer_id         = as.integer(customer_id),
    first_purchase_date = format(first_purchase_date, "%Y-%m-%d"),
    last_purchase_date  = format(last_purchase_date,  "%Y-%m-%d"),
    cohort_month        = format(cohort_month,         "%Y-%m-%d")
  )

# Quality checks
stopifnot("Duplicate customers in master" = !anyDuplicated(customer_master$customer_id))
stopifnot("Missing customer_id"           = !anyNA(customer_master$customer_id))
stopifnot("Missing segment"               = !anyNA(customer_master$segment))
stopifnot("Negative revenue"              = all(customer_master$total_revenue > 0))
stopifnot("CLV decile out of range"       = all(customer_master$clv_decile %in% c(1:10, NA)))

n_with_clv    <- sum(!is.na(customer_master$clv_12m))
n_without_clv <- sum( is.na(customer_master$clv_12m))

message(sprintf("Customer master: %s rows | %s with CLV | %s without (post-cutoff)",
                comma(nrow(customer_master)), comma(n_with_clv), comma(n_without_clv)))

write_csv(customer_master, "outputs/tableau/customer_master.csv")
message("Saved: outputs/tableau/customer_master.csv")

# ---- Table 2: Transactions ----
# Clean transaction-level data for time series, product, and geographic views.
# Joining segment and CLV decile enables customer-tier filtering in Tableau.

transactions <- df |>
  select(
    invoice_no, invoice_date = invoice_date_only,
    customer_id, stock_code, description,
    quantity, unit_price, total_amount, country
  ) |>
  left_join(
    customer_master |> select(customer_id, segment, clv_decile, cohort_month),
    by = "customer_id"
  ) |>
  mutate(
    customer_id  = as.integer(customer_id),
    invoice_date = format(invoice_date, "%Y-%m-%d")
    # cohort_month already character from customer_master
  )

stopifnot("Missing customer_id in transactions" = !anyNA(transactions$customer_id))

message(sprintf("Transactions: %s rows", comma(nrow(transactions))))

write_csv(transactions, "outputs/tableau/transactions.csv")
message("Saved: outputs/tableau/transactions.csv")

# ---- Table 3: Cohort Retention ----
# Pass-through with human-readable cohort labels added for Tableau display.

cohort_tableau <- cohort |>
  select(cohort_month, segment, cohort_label, period_number,
         cohort_size, n_active, retention_rate)

message(sprintf("Cohort retention: %s rows (%s cohorts × periods)",
                comma(nrow(cohort_tableau)),
                n_distinct(cohort_tableau$cohort_month)))

write_csv(cohort_tableau, "outputs/tableau/cohort_retention.csv")
message("Saved: outputs/tableau/cohort_retention.csv")

# ---- Table 4: Segment Summary ----
# RFM counts + CLV aggregates joined into one segment-level table.

rfm_summary <- rfm |>
  group_by(segment) |>
  summarise(
    n_customers   = n(),
    avg_recency   = mean(recency),
    avg_frequency = mean(frequency),
    avg_monetary  = mean(monetary),
    .groups       = "drop"
  )

segment_summary <- rfm_summary |>
  left_join(
    clv_seg |> select(segment, avg_p_alive, median_clv, mean_clv, total_clv),
    by = "segment"
  ) |>
  arrange(desc(mean_clv))

message(sprintf("Segment summary: %s segments", nrow(segment_summary)))

write_csv(segment_summary, "outputs/tableau/segment_summary.csv")
message("Saved: outputs/tableau/segment_summary.csv")

# ---- Final Checklist ----

message("\n========== Tableau Export Summary ==========")
message(sprintf("  customer_master.csv  — %s rows, %s cols",
                comma(nrow(customer_master)), ncol(customer_master)))
message(sprintf("  transactions.csv     — %s rows, %s cols",
                comma(nrow(transactions)), ncol(transactions)))
message(sprintf("  cohort_retention.csv — %s rows, %s cols",
                comma(nrow(cohort_tableau)), ncol(cohort_tableau)))
message(sprintf("  segment_summary.csv  — %s rows, %s cols",
                comma(nrow(segment_summary)), ncol(segment_summary)))
message("=============================================\n")

# So what: Four flat files ready for Tableau. The customer_master is the
# central dimension table — join everything else to it via customer_id.
# Suggested Tableau data model:
#   transactions (fact) → customer_master (dim) via customer_id
#   customer_master     → cohort_retention via cohort_month
#   segment_summary     → standalone for exec-level segment dashboards
#
# Key fields added beyond raw script outputs:
#   cohort_month   — enables cohort slicing on any customer-level view
#   clv_decile     — pre-computed ranking for targeting tier filters
#   segment joined onto transactions — enables revenue by segment over time
#
# 741 customers have NA CLV (acquired Jul–Dec 2011, outside calibration
# window) — filter to clv_12m IS NOT NULL for CLV-specific views.
