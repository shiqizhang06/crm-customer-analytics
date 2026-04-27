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
on.exit(dbDisconnect(con), add = TRUE)

message("Connected: ", db_path)

# ---- Load CSV Tables ----

load_csv <- function(filename, table_name) {
  path <- file.path(tableau_dir, filename)
  df   <- read_csv(path, show_col_types = FALSE)
  dbWriteTable(con, table_name, df, overwrite = TRUE)
  message(sprintf("  Loaded %-20s — %s rows, %s cols",
                  table_name, comma(nrow(df)), ncol(df)))
  invisible(df)
}

message("\nLoading Tableau CSVs...")
load_csv("customer_master.csv",  "customer_master")
load_csv("cohort_retention.csv", "cohort_retention")
load_csv("segment_summary.csv",  "segment_summary")

# transactions.csv is large and gitignored; load if present locally
trans_path <- file.path(tableau_dir, "transactions.csv")
if (file.exists(trans_path)) {
  load_csv("transactions.csv", "transactions")
} else {
  message("  transactions.csv not found locally — skipping (gitignored)")
}

# ---- Load Retail Clean (transactions source for Streamlit) ----

message("\nLoading retail_clean from RDS...")
retail_clean <- readRDS(rds_path) |>
  select(invoice_no, invoice_date = invoice_date_only,
         customer_id, stock_code, description,
         quantity, unit_price, total_amount, country)

dbWriteTable(con, "retail_clean", retail_clean, overwrite = TRUE)
message(sprintf("  Loaded %-20s — %s rows, %s cols",
                "retail_clean", comma(nrow(retail_clean)), ncol(retail_clean)))

# ---- Create Indexes ----

message("\nCreating indexes...")

indexes <- list(
  "idx_cm_customer_id" = "CREATE INDEX idx_cm_customer_id ON customer_master(customer_id)",
  "idx_cm_segment"     = "CREATE INDEX idx_cm_segment     ON customer_master(segment)",
  "idx_cm_clv_decile"  = "CREATE INDEX idx_cm_clv_decile  ON customer_master(clv_decile)",
  "idx_rc_customer_id" = "CREATE INDEX idx_rc_customer_id ON retail_clean(customer_id)",
  "idx_rc_date"        = "CREATE INDEX idx_rc_date        ON retail_clean(invoice_date)"
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
