# ============================================================
# 07_load_to_sqlite.R
# CRM Customer Analytics — Load Exports to SQLite
#
# Reads all Tableau-ready CSVs from outputs/tableau/ and the
# cleaned transaction data from its RDS, then loads everything
# into data/processed/crm.db for Streamlit SQL queries.
#
# DB is dropped and rebuilt each run (idempotent).
#
# Input:  outputs/tableau/*.csv
#         data/processed/retail_clean.rds  (transactions source)
# Output: data/processed/crm.db
#
# Tables created:
#   customer_master   — one row per customer, all dimensions + CLV
#   cohort_retention  — cohort × period retention matrix
#   segment_summary   — RFM + CLV aggregates per segment
#   retail_clean      — full transaction-level data
# ============================================================

library(tidyverse)
library(DBI)
library(RSQLite)
library(scales)

# ---- Validate Inputs ----

tableau_dir <- "outputs/tableau"
rds_path    <- "data/processed/retail_clean.rds"

required_csvs <- c(
  "customer_master.csv",
  "cohort_retention.csv",
  "segment_summary.csv"
)

missing <- required_csvs[!file.exists(file.path(tableau_dir, required_csvs))]
if (length(missing) > 0)
  stop("Missing Tableau exports — run 06_export_for_tableau.R first:\n  ",
       paste(missing, collapse = "\n  "))

if (!file.exists(rds_path))
  stop("retail_clean.rds not found — run 01_data_cleaning.R first.")

# ---- Connect & Rebuild DB ----

db_path <- "data/processed/crm.db"
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

if (file.exists(db_path)) {
  file.remove(db_path)
  message("Dropped existing DB: ", db_path)
}

con <- dbConnect(RSQLite::SQLite(), db_path)
message("Connected: ", db_path)

# ---- Load CSV Tables ----

load_csv <- function(filename, table_name) {
  path <- file.path(tableau_dir, filename)
  # read_csv auto-parses YYYY-MM-DD strings as Date; RSQLite would convert
  # those back to R's integer day-count. Convert all Date columns to character
  # so they are stored as TEXT in SQLite and read back correctly by Python.
  df   <- read_csv(path, show_col_types = FALSE) |>
    mutate(across(where(is.Date), as.character))
  dbWriteTable(con, table_name, df, overwrite = TRUE)
  message(sprintf("  Loaded %-20s — %s rows, %s cols",
                  table_name, comma(nrow(df)), ncol(df)))
  invisible(df)
}

message("\nLoading Tableau CSVs...")
load_csv("customer_master.csv",  "customer_master")
load_csv("cohort_retention.csv", "cohort_retention")
load_csv("segment_summary.csv",  "segment_summary")

# transactions.csv is Tableau-only and not queried by the Streamlit app.
# Excluded from the SQLite DB to keep file size small enough to commit.

# ---- Load Customer Monthly Revenue (pre-aggregated from retail_clean) ----
# Full retail_clean (400K rows) is too large to commit to the repo.
# The Streamlit app only needs monthly revenue per customer for the
# purchase history chart — pre-aggregate here to keep the DB small.

message("\nBuilding customer_monthly_revenue from RDS...")
customer_monthly_revenue <- readRDS(rds_path) |>
  mutate(
    customer_id = as.integer(customer_id),
    month       = format(invoice_date_only, "%Y-%m")
  ) |>
  group_by(customer_id, month) |>
  summarise(revenue = sum(total_amount), .groups = "drop")

dbWriteTable(con, "customer_monthly_revenue", customer_monthly_revenue, overwrite = TRUE)
message(sprintf("  Loaded %-20s — %s rows, %s cols",
                "customer_monthly_revenue",
                comma(nrow(customer_monthly_revenue)),
                ncol(customer_monthly_revenue)))

# ---- Create Indexes ----

message("\nCreating indexes...")

indexes <- list(
  "idx_cm_customer_id"  = "CREATE INDEX idx_cm_customer_id  ON customer_master(customer_id)",
  "idx_cm_segment"      = "CREATE INDEX idx_cm_segment      ON customer_master(segment)",
  "idx_cm_clv_decile"   = "CREATE INDEX idx_cm_clv_decile   ON customer_master(clv_decile)",
  "idx_cmr_customer_id" = "CREATE INDEX idx_cmr_customer_id ON customer_monthly_revenue(customer_id)"
)

for (name in names(indexes)) {
  dbExecute(con, indexes[[name]])
  message("  Created index: ", name)
}

# ---- Verification Summary ----

message("\n========== SQLite DB Summary ==========")
tables <- dbListTables(con)
for (tbl in sort(tables)) {
  n <- dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM [%s]", tbl))$n
  message(sprintf("  %-22s %s rows", tbl, comma(n)))
}

db_size_mb <- file.size(db_path) / 1e6
message(sprintf("\n  DB size: %.1f MB", db_size_mb))
message(sprintf("  Path:    %s", db_path))
message("========================================\n")

dbDisconnect(con)
