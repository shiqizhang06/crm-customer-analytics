# ============================================================
# 04_cohort_retention.R
# CRM Customer Analytics — Cohort Retention Analysis
#
# Input:  data/processed/retail_clean.rds
# Output: data/processed/cohort_retention.rds
#         data/processed/cohort_retention.csv  (Tableau-ready)
#         outputs/figures/cohort_*.png
# ============================================================

library(tidyverse)
library(scales)
library(lubridate)

# ---- Load Cleaned Data ----

if (!file.exists("data/processed/retail_clean.rds"))
  stop("Cleaned data not found. Run 01_data_cleaning.R first.")
if (!file.exists("data/processed/rfm_segments.rds"))
  stop("RFM segments not found. Run 03_rfm_segmentation.R first.")

df       <- readRDS("data/processed/retail_clean.rds")
segments <- readRDS("data/processed/rfm_segments.rds") |>
  select(customer_id, segment)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed",  recursive = TRUE, showWarnings = FALSE)

message(sprintf("Loaded: %s rows, %s customers",
                comma(nrow(df)), comma(n_distinct(df$customer_id))))

# ---- Build Cohort Base ----
# Cohort = month of first purchase; period = months since cohort month

customer_activity <- df |>
  mutate(activity_month = floor_date(invoice_date_only, "month")) |>
  group_by(customer_id, activity_month) |>
  summarise(.groups = "drop")

cohort_map <- customer_activity |>
  group_by(customer_id) |>
  summarise(cohort_month = min(activity_month), .groups = "drop")

cohort_data <- customer_activity |>
  left_join(cohort_map, by = "customer_id") |>
  mutate(
    period_number = interval(cohort_month, activity_month) %/% months(1)
  )

message(sprintf("Cohorts defined: %s unique cohort months",
                n_distinct(cohort_data$cohort_month)))

# ---- Build Retention Matrix ----

cohort_sizes <- cohort_map |>
  count(cohort_month, name = "cohort_size")

retention_counts <- cohort_data |>
  group_by(cohort_month, period_number) |>
  summarise(n_active = n_distinct(customer_id), .groups = "drop")

retention_matrix <- retention_counts |>
  left_join(cohort_sizes, by = "cohort_month") |>
  mutate(retention_rate = n_active / cohort_size) |>
  arrange(cohort_month, period_number)

# Sanity check: period 0 retention should always be 100%
period_0_check <- retention_matrix |>
  filter(period_number == 0) |>
  pull(retention_rate)

stopifnot("Period 0 retention is not 100% for all cohorts" =
            all(abs(period_0_check - 1) < 1e-9))

message(sprintf("Retention matrix: %s cohorts × up to %s periods",
                n_distinct(retention_matrix$cohort_month),
                max(retention_matrix$period_number)))

# ---- Plot 1: Cohort Retention Heatmap ----

# Limit to cohorts with at least 6 months of follow-up for readability
max_date    <- max(df$invoice_date_only)
valid_cohorts <- cohort_sizes |>
  filter(cohort_month <= floor_date(max_date, "month") - months(5)) |>
  pull(cohort_month)

heatmap_data <- retention_matrix |>
  filter(cohort_month %in% valid_cohorts, period_number <= 11) |>
  mutate(
    cohort_label = format(cohort_month, "%b %Y"),
    cohort_label = fct_rev(factor(cohort_label,
                                  levels = format(sort(valid_cohorts), "%b %Y")))
  )

p_heatmap <- ggplot(heatmap_data,
                    aes(x = period_number, y = cohort_label, fill = retention_rate)) +
  geom_tile(colour = "white", linewidth = 0.5) +
  geom_text(aes(label = ifelse(retention_rate >= 0.01,
                               percent(retention_rate, accuracy = 1), "")),
            size = 2.8, colour = "white", fontface = "bold") +
  scale_x_continuous(breaks = 0:11,
                     labels = c("0\n(cohort)", as.character(1:11))) +
  scale_fill_gradient(low = "#deebf7", high = "#08519c",
                      labels = percent_format(),
                      name = "Retention\nRate",
                      limits = c(0, 1)) +
  labs(
    title    = "Monthly Cohort Retention — UK Customers",
    subtitle = "Each row is the cohort of customers who made their first purchase in that month",
    x        = "Months Since First Purchase",
    y        = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid = element_blank(),
        axis.text.y = element_text(size = 9))

ggsave("outputs/figures/cohort_01_retention_heatmap.png",
       p_heatmap, width = 13, height = 9, dpi = 300, bg = "white")
message("Saved: outputs/figures/cohort_01_retention_heatmap.png")

# ---- Plot 2: Average Retention Curve ----

avg_retention <- retention_matrix |>
  filter(period_number <= 11) |>
  group_by(period_number) |>
  summarise(avg_retention = mean(retention_rate), .groups = "drop")

p_curve <- ggplot(avg_retention, aes(x = period_number, y = avg_retention)) +
  geom_line(colour = "#08519c", linewidth = 1.2) +
  geom_point(colour = "#08519c", size = 3) +
  geom_text(aes(label = percent(avg_retention, accuracy = 1)),
            vjust = -0.9, size = 3.5) +
  scale_x_continuous(breaks = 0:11) +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1.05)) +
  labs(
    title    = "Average Retention Curve Across All Cohorts",
    subtitle = "Average % of customers still active N months after first purchase",
    x        = "Months Since First Purchase",
    y        = "Average Retention Rate"
  ) +
  theme_minimal(base_size = 13)

ggsave("outputs/figures/cohort_02_avg_retention_curve.png",
       p_curve, width = 10, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/cohort_02_avg_retention_curve.png")

# ---- Summary Stats ----

m1_retention <- avg_retention |> filter(period_number == 1) |> pull(avg_retention)
m3_retention <- avg_retention |> filter(period_number == 3) |> pull(avg_retention)
m6_retention <- avg_retention |> filter(period_number == 6) |> pull(avg_retention)

message("\n========== Cohort Summary ==========")
message(sprintf("  Cohorts tracked:   %s", n_distinct(retention_matrix$cohort_month)))
message(sprintf("  Avg M1 retention:  %.1f%%", m1_retention * 100))
message(sprintf("  Avg M3 retention:  %.1f%%", m3_retention * 100))
message(sprintf("  Avg M6 retention:  %.1f%%", m6_retention * 100))
message("=====================================\n")

# ---- Build Segment-Level Retention Matrix ----
# Each customer's current RFM segment is projected back onto their cohort
# activity, enabling cohort × segment cross-filtering in Tableau / Streamlit.

cohort_sizes_seg <- cohort_map |>
  left_join(segments, by = "customer_id") |>
  count(cohort_month, segment, name = "cohort_size")

retention_counts_seg <- cohort_data |>
  left_join(segments, by = "customer_id") |>
  group_by(cohort_month, segment, period_number) |>
  summarise(n_active = n_distinct(customer_id), .groups = "drop")

# Densify: build a complete grid of cohort × segment × period so that
# zero-activity periods are explicit rows (n_active=0) rather than missing.
# Without this, downstream aggregations see a shrinking denominator.
max_period_by_cohort <- retention_matrix |>
  group_by(cohort_month) |>
  summarise(max_period = max(period_number), .groups = "drop")

all_segments <- sort(unique(segments$segment))

complete_grid <- cohort_sizes_seg |>
  select(cohort_month, segment) |>
  left_join(max_period_by_cohort, by = "cohort_month") |>
  rowwise() |>
  mutate(period_number = list(seq(0L, max_period))) |>
  unnest(period_number) |>
  select(-max_period)

retention_by_segment <- complete_grid |>
  left_join(retention_counts_seg, by = c("cohort_month", "segment", "period_number")) |>
  left_join(cohort_sizes_seg,     by = c("cohort_month", "segment")) |>
  mutate(
    n_active       = coalesce(n_active, 0L),
    retention_rate = n_active / cohort_size,
    cohort_label   = format(cohort_month, "%b %Y")
  ) |>
  select(cohort_month, segment, cohort_label, period_number,
         cohort_size, n_active, retention_rate) |>
  arrange(cohort_month, segment, period_number)

message(sprintf("Segment retention: %s cohort × segment pairs, %s total rows (dense)",
                n_distinct(paste(retention_by_segment$cohort_month,
                                 retention_by_segment$segment)),
                nrow(retention_by_segment)))

# ---- Export ----

# Wide format for Tableau (cohort × period, global — unchanged)
retention_wide <- retention_matrix |>
  select(cohort_month, period_number, retention_rate) |>
  pivot_wider(names_from = period_number,
              names_prefix = "month_",
              values_from = retention_rate)

# cohort_retention.rds / .csv now use segment-level matrix
# (global retention_matrix kept in memory for the plots above)
saveRDS(retention_by_segment, "data/processed/cohort_retention.rds")
write_csv(retention_by_segment, "data/processed/cohort_retention.csv")
write_csv(retention_wide,        "data/processed/cohort_retention_wide.csv")

message("Saved: data/processed/cohort_retention.rds")
message("Saved: data/processed/cohort_retention.csv")
message("Saved: data/processed/cohort_retention_wide.csv")

# So what: Cohorts tracked: 25
# 
# The biggest retention challenge is the M0→M1 cliff — on average 79%
# of customers never return after their first purchase month. However, customers
# who do return at M1 (~21%) show a remarkably stable plateau through M6 (~19%),
# only gradually declining to ~15% by M9+. This suggests the critical intervention
# window is within 30 days of first purchase.
#
# The heatmap reveals a strong seasonal re-activation pattern: a visible diagonal
# band of elevated retention (~25–35%) aligns with Q4 (Oct–Nov) each year across
# cohorts, consistent with Christmas-driven repurchase at this gift retailer.
# This means some "retained" customers are actually seasonally reactivated, not
# continuously engaged — an important distinction for campaign planning.
#
# Dec 2010 cohort shows the lowest M1 retention (8%), indicating that customers
# acquired during peak Christmas season are predominantly one-time buyers.
# Acquisition during Q4 is high-volume but low-quality.
#
# Implications:
# - Invest in post-first-purchase nurture campaigns (e.g. 7-day and 21-day
#   follow-ups) to convert the M1 cliff into a gentler slope.
# - Don't count on Q4 seasonal spikes as true retention — build year-round
#   engagement strategies for customers acquired in peak season.
# - The stable 15–20% long-term retention represents a loyal core; focus on
#   expanding this base through the Potential Loyalists and Promising segments
#   identified in the RFM analysis.
