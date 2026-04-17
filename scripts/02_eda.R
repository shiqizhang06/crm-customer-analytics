# ============================================================
# 02_eda.R
# CRM Customer Analytics — Exploratory Data Analysis
#
# Input:  data/processed/retail_clean.rds
# Output: outputs/figures/eda_*.png
# ============================================================

library(tidyverse)
library(scales)
library(lubridate)

# ---- Load Cleaned Data ----

clean_path <- "data/processed/retail_clean.rds"

if (!file.exists(clean_path)) {
  stop("Cleaned data not found. Run 01_data_cleaning.R first.")
}

df <- readRDS(clean_path)
message(sprintf("Loaded clean data: %s rows, %s customers",
                comma(nrow(df)), comma(n_distinct(df$customer_id))))

dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

# ---- Helper: Save Plot ----

save_plot <- function(plot, filename, width = 10, height = 6) {
  path <- file.path("outputs/figures", filename)
  ggsave(path, plot = plot, width = width, height = height,
         dpi = 300, bg = "white")
  message(sprintf("Saved: %s", path))
}

# ---- 1. Revenue Distribution ----

invoice_revenue <- df |>
  group_by(invoice_no) |>
  summarise(invoice_total = sum(total_amount), .groups = "drop")

rev_p95 <- quantile(invoice_revenue$invoice_total, 0.95)

p_rev_dist <- ggplot(
  invoice_revenue |> filter(invoice_total <= rev_p95),
  aes(x = invoice_total)
) +
  geom_histogram(bins = 60, fill = "#2166ac", colour = "white", linewidth = 0.2) +
  scale_x_continuous(labels = dollar_format(prefix = "£")) +
  scale_y_continuous(labels = comma) +
  labs(
    title    = "Invoice Revenue Distribution (UK Customers, ≤95th percentile)",
    subtitle = sprintf("Median: £%s  |  Mean: £%s  |  P95 cap: £%s",
                       comma(median(invoice_revenue$invoice_total), accuracy = 1),
                       comma(mean(invoice_revenue$invoice_total),   accuracy = 1),
                       comma(rev_p95, accuracy = 1)),
    x = "Invoice Total (£)",
    y = "Number of Invoices"
  ) +
  theme_minimal(base_size = 13)

save_plot(p_rev_dist, "eda_01_revenue_distribution.png")

message("Revenue summary:")
print(summary(invoice_revenue$invoice_total))

# ---- 2. Purchases per Customer Distribution ----

customer_invoices <- df |>
  group_by(customer_id) |>
  summarise(n_invoices = n_distinct(invoice_no), .groups = "drop")

p_purchases <- ggplot(
  customer_invoices |> filter(n_invoices <= quantile(n_invoices, 0.95)),
  aes(x = n_invoices)
) +
  geom_histogram(binwidth = 1, fill = "#4dac26", colour = "white", linewidth = 0.2) +
  scale_y_continuous(labels = comma) +
  labs(
    title    = "Purchases per Customer Distribution (≤95th percentile)",
    subtitle = sprintf("Median: %s orders  |  Mean: %.1f orders",
                       median(customer_invoices$n_invoices),
                       mean(customer_invoices$n_invoices)),
    x = "Number of Invoices (Orders)",
    y = "Number of Customers"
  ) +
  theme_minimal(base_size = 13)

save_plot(p_purchases, "eda_02_purchases_per_customer.png")

# ---- 3. Monthly Revenue Time Series ----

monthly_revenue <- df |>
  mutate(month = floor_date(invoice_date_only, "month")) |>
  group_by(month) |>
  summarise(revenue = sum(total_amount), .groups = "drop")

p_monthly <- ggplot(monthly_revenue, aes(x = month, y = revenue)) +
  geom_line(colour = "#2166ac", linewidth = 1) +
  geom_point(colour = "#2166ac", size = 2) +
  scale_x_date(date_breaks = "3 months", date_labels = "%b %Y") +
  scale_y_continuous(labels = dollar_format(prefix = "£", scale = 1e-3, suffix = "K")) +
  labs(
    title = "Monthly Revenue — UK Customers",
    x     = NULL,
    y     = "Revenue (£K)"
  ) +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

save_plot(p_monthly, "eda_03_monthly_revenue.png", width = 12, height = 5)

message(sprintf("Monthly revenue range: £%s – £%s",
                comma(min(monthly_revenue$revenue), accuracy = 1),
                comma(max(monthly_revenue$revenue), accuracy = 1)))

# ---- 4. Top 10 Products by Revenue ----

top_products <- df |>
  group_by(stock_code, description) |>
  summarise(revenue = sum(total_amount), .groups = "drop") |>
  slice_max(revenue, n = 10) |>
  mutate(description = str_trunc(description, 40),
         description = fct_reorder(description, revenue))

p_products <- ggplot(top_products, aes(x = revenue, y = description)) +
  geom_col(fill = "#d6604d") +
  scale_x_continuous(labels = dollar_format(prefix = "£", scale = 1e-3, suffix = "K")) +
  labs(
    title = "Top 10 Products by Revenue",
    x     = "Total Revenue (£K)",
    y     = NULL
  ) +
  theme_minimal(base_size = 13)

save_plot(p_products, "eda_04_top10_products.png", height = 5)

# ---- 5. Customer Concentration (Pareto) ----

customer_revenue <- df |>
  group_by(customer_id) |>
  summarise(revenue = sum(total_amount), .groups = "drop") |>
  arrange(desc(revenue)) |>
  mutate(
    rank_pct    = row_number() / n(),
    cum_rev_pct = cumsum(revenue) / sum(revenue)
  )

# Find threshold: % of customers driving 80% of revenue
pct_customers_80 <- customer_revenue |>
  filter(cum_rev_pct >= 0.80) |>
  slice(1) |>
  pull(rank_pct)

p_pareto <- ggplot(customer_revenue, aes(x = rank_pct, y = cum_rev_pct)) +
  geom_line(colour = "#2166ac", linewidth = 1) +
  geom_hline(yintercept = 0.80, linetype = "dashed", colour = "grey50") +
  geom_vline(xintercept = pct_customers_80, linetype = "dashed", colour = "#d6604d") +
  annotate("text",
           x = pct_customers_80 + 0.03, y = 0.60,
           label = sprintf("Top %.0f%% of customers\ndrive 80%% of revenue",
                           pct_customers_80 * 100),
           colour = "#d6604d", size = 4, hjust = 0) +
  scale_x_continuous(labels = percent_format()) +
  scale_y_continuous(labels = percent_format()) +
  labs(
    title = "Customer Revenue Concentration (Pareto Curve)",
    x     = "Cumulative % of Customers (ranked by revenue, high → low)",
    y     = "Cumulative % of Revenue"
  ) +
  theme_minimal(base_size = 13)

save_plot(p_pareto, "eda_05_pareto_concentration.png")

message(sprintf("Pareto insight: top %.0f%% of customers generate 80%% of revenue",
                pct_customers_80 * 100))

# ---- EDA Summary ----

message("\n========== EDA Summary ==========")
message(sprintf("  Date range:          %s to %s",
                min(df$invoice_date_only), max(df$invoice_date_only)))
message(sprintf("  Total revenue:       £%s", comma(sum(df$total_amount), accuracy = 1)))
message(sprintf("  Unique customers:    %s", comma(n_distinct(df$customer_id))))
message(sprintf("  Unique invoices:     %s", comma(n_distinct(df$invoice_no))))
message(sprintf("  Unique products:     %s", comma(n_distinct(df$stock_code))))
message(sprintf("  Avg revenue/invoice: £%s",
                comma(sum(df$total_amount) / n_distinct(df$invoice_no), accuracy = 0.01)))
message("==================================\n")

# So what: revenue is heavily right-skewed and concentrated — a small share of
# customers accounts for the majority of revenue. Retention and CLV efforts
# should prioritise this high-value segment.
