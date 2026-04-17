# ============================================================
# 01_data_cleaning.R
# CRM Customer Analytics — Data Cleaning & Preparation
#
# Input:  data/raw/online_retail_II.csv
# Output: data/processed/retail_clean.rds
#         data/processed/retail_clean.csv
# ============================================================

library(tidyverse)

# ---- Load Raw Data ----

raw_path <- "data/raw/online_retail_II.csv"

if (!file.exists(raw_path)) {
  stop("Raw data not found at: ", raw_path,
       "\nDownload from: https://archive.ics.uci.edu/dataset/502/online+retail+ii")
}

df_raw <- read_csv(
  raw_path,
  col_types = cols(
    Invoice      = col_character(),
    StockCode    = col_character(),
    Description  = col_character(),
    Quantity     = col_double(),
    InvoiceDate  = col_datetime(format = "%Y-%m-%d %H:%M:%S"),
    Price        = col_double(),
    `Customer ID` = col_double(),
    Country      = col_character()
  ),
  show_col_types = FALSE
)

n_raw <- nrow(df_raw)
message(sprintf("Raw data loaded: %s rows", scales::comma(n_raw)))

# ---- Rename Columns ----
# Standardise to snake_case; rename 'Customer ID' (has space) and 'Price'
# to match downstream script conventions (customer_id, unit_price)

df <- df_raw |>
  rename(
    invoice_no  = Invoice,
    stock_code  = StockCode,
    description = Description,
    quantity    = Quantity,
    invoice_date = InvoiceDate,
    unit_price  = Price,
    customer_id = `Customer ID`,
    country     = Country
  )

# ---- Step 1: Remove Missing CustomerID ----

df <- df |> filter(!is.na(customer_id))
message(sprintf("After removing missing CustomerID: %s rows (removed %s)",
                scales::comma(nrow(df)),
                scales::comma(n_raw - nrow(df))))

# ---- Step 2: Remove Cancellations ----
# Cancellation invoices start with 'C'

n_before <- nrow(df)
df <- df |> filter(!str_starts(invoice_no, "C"))
message(sprintf("After removing cancellations: %s rows (removed %s)",
                scales::comma(nrow(df)),
                scales::comma(n_before - nrow(df))))

# ---- Step 3: Remove Non-Positive Quantity / Price ----

n_before <- nrow(df)
df <- df |> filter(quantity > 0, unit_price > 0)
message(sprintf("After removing non-positive quantity/price: %s rows (removed %s)",
                scales::comma(nrow(df)),
                scales::comma(n_before - nrow(df))))

# ---- Step 4: Filter to UK Only ----

n_before <- nrow(df)
df <- df |> filter(country == "United Kingdom")
message(sprintf("After filtering to UK: %s rows (removed %s)",
                scales::comma(nrow(df)),
                scales::comma(n_before - nrow(df))))

# ---- Step 5: Create Derived Columns ----

df <- df |>
  mutate(
    customer_id  = as.integer(customer_id),
    invoice_date = ymd_hms(invoice_date),
    invoice_date_only = as_date(invoice_date),
    total_amount = quantity * unit_price
  )

# ---- Step 6: Sanity Checks ----

stopifnot(
  "CustomerID has NAs after cleaning"  = sum(is.na(df$customer_id)) == 0,
  "total_amount has non-positives"      = all(df$total_amount > 0),
  "invoice_date has NAs"                = sum(is.na(df$invoice_date)) == 0
)

# ---- Summary Report ----

n_clean      <- nrow(df)
n_customers  <- n_distinct(df$customer_id)
n_invoices   <- n_distinct(df$invoice_no)
date_min     <- min(df$invoice_date_only)
date_max     <- max(df$invoice_date_only)

message("\n========== Cleaning Summary ==========")
message(sprintf("  Raw rows:          %s", scales::comma(n_raw)))
message(sprintf("  Clean rows:        %s (%.1f%% retained)",
                scales::comma(n_clean), 100 * n_clean / n_raw))
message(sprintf("  Unique customers:  %s", scales::comma(n_customers)))
message(sprintf("  Unique invoices:   %s", scales::comma(n_invoices)))
message(sprintf("  Date range:        %s to %s", date_min, date_max))
message("======================================\n")

# So what: 67.9% of raw transactions (725K of 1.07M) survived cleaning, covering
# 5,350 unique UK customers across 33,541 invoices from Dec 2009 to Dec 2011.
# The largest single drop was missing CustomerIDs (23% of rows) — likely guest
# checkouts — confirming the analysis is representative of registered customers only.

# ---- Export ----

saveRDS(df, "data/processed/retail_clean.rds")
write_csv(df, "data/processed/retail_clean.csv")

message("Saved: data/processed/retail_clean.rds")
message("Saved: data/processed/retail_clean.csv")
