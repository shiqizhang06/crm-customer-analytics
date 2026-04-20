# ============================================================
# 05_clv_prediction.R
# CRM Customer Analytics — CLV Prediction (BG/NBD + Gamma-Gamma)
#
# Input:  data/processed/retail_clean.rds
#         data/processed/rfm_segments.rds
# Output: data/processed/clv_predictions.csv/.rds
#         data/processed/clv_segment_summary.csv
#         outputs/figures/clv_*.png
# ============================================================

library(tidyverse)
library(lubridate)
library(BTYD)
library(scales)

# ---- Load Data ----

if (!file.exists("data/processed/retail_clean.rds"))
  stop("Cleaned data not found. Run 01_data_cleaning.R first.")
if (!file.exists("data/processed/rfm_segments.rds"))
  stop("RFM segments not found. Run 03_rfm_segmentation.R first.")

df  <- readRDS("data/processed/retail_clean.rds")
rfm <- readRDS("data/processed/rfm_segments.rds")

dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed",  recursive = TRUE, showWarnings = FALSE)

message(sprintf("Loaded: %s rows, %s customers",
                comma(nrow(df)), comma(n_distinct(df$customer_id))))

# ---- Define Calibration / Holdout Split ----
# Calibration: Dec 2009 – Jun 2011 (~18 months)
# Holdout:     Jul 2011 – Dec 2011 (~6 months) — used for model validation only
# Forecast:    12 months ahead from end of data

cal_end        <- as.Date("2011-06-30")
holdout_end    <- as.Date("2011-12-09")
forecast_weeks <- 52
holdout_weeks  <- as.numeric(holdout_end - cal_end) / 7

message(sprintf("Calibration end: %s | Holdout end: %s | Forecast: %d weeks",
                cal_end, holdout_end, forecast_weeks))

# ---- Build Event Log ----
# Aggregate to one record per customer per day; revenue = sum across invoices

elog <- df |>
  group_by(customer_id, invoice_date_only) |>
  summarise(daily_revenue = sum(total_amount), .groups = "drop") |>
  rename(cust = customer_id, date = invoice_date_only) |>
  arrange(cust, date)

message(sprintf("Event log: %s customer-day records", comma(nrow(elog))))

# ---- Build Calibration CBS ----
# CBS columns required by BTYD:
#   x     — number of repeat transactions (first purchase excluded)
#   t.x   — weeks from first purchase to last purchase in calibration
#   T.cal — weeks from first purchase to end of calibration period
#   m.x   — average revenue per transaction day in calibration

first_dates <- elog |>
  group_by(cust) |>
  summarise(first_date = min(date), .groups = "drop")

cal_cbs <- elog |>
  left_join(first_dates, by = "cust") |>
  filter(date <= cal_end, first_date < cal_end) |>
  group_by(cust, first_date) |>
  summarise(
    x     = n() - 1L,
    t.x   = as.numeric(max(date) - first(first_date)) / 7,
    T.cal = as.numeric(cal_end   - first(first_date)) / 7,
    m.x   = mean(daily_revenue),
    .groups = "drop"
  )

message(sprintf("Calibration CBS: %s customers", comma(nrow(cal_cbs))))
message(sprintf("  With repeat purchases (x >= 1): %s (%.1f%%)",
                comma(sum(cal_cbs$x >= 1)),
                mean(cal_cbs$x >= 1) * 100))

# ---- Holdout Counts (validation only) ----

holdout_counts <- elog |>
  filter(date > cal_end, date <= holdout_end) |>
  count(cust, name = "x.holdout")

cal_cbs <- cal_cbs |>
  left_join(holdout_counts, by = "cust") |>
  mutate(x.holdout = replace_na(x.holdout, 0L))

# ---- Fit BG/NBD Model ----

message("Fitting BG/NBD model...")

cbs_matrix <- cal_cbs |> select(x, t.x, T.cal) |> as.matrix()

bgnbd_params <- bgnbd.EstimateParameters(cbs_matrix)
names(bgnbd_params) <- c("r", "alpha", "a", "b")

message(sprintf("  Params — r: %.3f, alpha: %.3f, a: %.3f, b: %.3f",
                bgnbd_params[["r"]], bgnbd_params[["alpha"]],
                bgnbd_params[["a"]], bgnbd_params[["b"]]))

cal_cbs <- cal_cbs |>
  mutate(
    p_alive = mapply(
      function(xi, tx, Tc)
        bgnbd.PAlive(bgnbd_params, xi, tx, Tc),
      x, t.x, T.cal
    ),
    pred_holdout = mapply(
      function(xi, tx, Tc)
        bgnbd.ConditionalExpectedTransactions(bgnbd_params, holdout_weeks, xi, tx, Tc),
      x, t.x, T.cal
    ),
    exp_transactions_12m = mapply(
      function(xi, tx, Tc)
        bgnbd.ConditionalExpectedTransactions(bgnbd_params, forecast_weeks, xi, tx, Tc),
      x, t.x, T.cal
    )
  )

message(sprintf("  Avg P(alive) at calibration end: %.1f%%",
                mean(cal_cbs$p_alive) * 100))

# ---- Plot 1: BG/NBD Validation ----

validation_summary <- cal_cbs |>
  mutate(freq_bucket = factor(pmin(x, 7L),
                              labels = c(as.character(0:6), "7+"))) |>
  group_by(freq_bucket) |>
  summarise(
    actual    = mean(x.holdout),
    predicted = mean(pred_holdout),
    .groups   = "drop"
  ) |>
  pivot_longer(c(actual, predicted), names_to = "type", values_to = "transactions") |>
  mutate(type = str_to_title(type))

p_validation <- ggplot(validation_summary,
                       aes(x = freq_bucket, y = transactions,
                           colour = type, group = type)) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 3) +
  scale_colour_manual(values = c("Actual" = "#08519c", "Predicted" = "#fc8d59"),
                      name = NULL) +
  labs(
    title    = "BG/NBD Model Validation — Holdout Period",
    subtitle = sprintf("Avg transactions per customer by calibration frequency (%.0f-week holdout)",
                       holdout_weeks),
    x        = "Calibration Frequency (repeat purchases)",
    y        = "Avg Transactions in Holdout"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "top")

ggsave("outputs/figures/clv_01_bgnbd_validation.png",
       p_validation, width = 9, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_01_bgnbd_validation.png")

# ---- Fit Gamma-Gamma Spend Model ----
# Only customers with >= 1 repeat purchase can estimate spend parameters

message("Fitting Gamma-Gamma spend model...")

gg_data <- cal_cbs |> filter(x >= 1)

spend_params <- spend.EstimateParameters(
  m.x.vector = gg_data$m.x,
  x.vector   = gg_data$x
)
names(spend_params) <- c("p", "q", "gamma")

message(sprintf("  Params — p: %.3f, q: %.3f, gamma: %.3f",
                spend_params[["p"]], spend_params[["q"]], spend_params[["gamma"]]))

# Prior mean spend used for x=0 customers (no repeat transaction data)
prior_mean_spend <- spend_params[["p"]] * spend_params[["gamma"]] /
  (spend_params[["q"]] - 1)

message(sprintf("  Prior mean spend (x=0 fallback): £%.2f", prior_mean_spend))

# Compute expected spend: Gamma-Gamma for x>=1, prior mean for x=0
# (evaluated separately to avoid calling spend.expected.value with x=0)
exp_spend_vec <- rep(prior_mean_spend, nrow(cal_cbs))
repeat_mask   <- cal_cbs$x >= 1
exp_spend_vec[repeat_mask] <- mapply(
  function(mx, xi) spend.expected.value(spend_params, mx, xi),
  cal_cbs$m.x[repeat_mask],
  cal_cbs$x[repeat_mask]
)

cal_cbs <- cal_cbs |>
  mutate(
    exp_spend = exp_spend_vec,
    clv_12m   = exp_transactions_12m * exp_spend
  )

stopifnot("Negative CLV values detected" = all(cal_cbs$clv_12m >= 0, na.rm = TRUE))

message(sprintf("  Median 12-month CLV: £%.0f", median(cal_cbs$clv_12m)))
message(sprintf("  Mean   12-month CLV: £%.0f", mean(cal_cbs$clv_12m)))
message(sprintf("  Total  12-month CLV: £%s",   comma(round(sum(cal_cbs$clv_12m)))))

# ---- Join with RFM Segments ----

clv_output <- cal_cbs |>
  left_join(
    rfm |> select(customer_id, segment, rfm_score, r_score, f_score, m_score),
    by = c("cust" = "customer_id")
  ) |>
  select(
    customer_id = cust, segment, rfm_score, r_score, f_score, m_score,
    x, t.x, T.cal, m.x, p_alive,
    exp_transactions_12m, exp_spend, clv_12m
  )

# ---- Plot 2: P(alive) Distribution ----

p_alive_plot <- ggplot(cal_cbs, aes(x = p_alive)) +
  geom_histogram(binwidth = 0.05, fill = "#08519c", colour = "white", alpha = 0.85) +
  geom_vline(xintercept = 0.5, linetype = "dashed", colour = "#d94701", linewidth = 0.8) +
  annotate("text", x = 0.52, y = Inf,
           label = "P(alive) = 50%", hjust = 0, vjust = 1.8,
           colour = "#d94701", size = 3.5) +
  scale_x_continuous(labels = percent_format()) +
  scale_y_continuous(labels = comma_format()) +
  labs(
    title    = "Distribution of P(Alive) — BG/NBD Model",
    subtitle = "Estimated probability each customer is still active at end of calibration period",
    x        = "P(Alive)",
    y        = "Number of Customers"
  ) +
  theme_minimal(base_size = 13)

ggsave("outputs/figures/clv_02_p_alive_distribution.png",
       p_alive_plot, width = 9, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_02_p_alive_distribution.png")

# ---- Plot 3: CLV Distribution by RFM Segment ----

segment_order <- clv_output |>
  filter(!is.na(segment)) |>
  group_by(segment) |>
  summarise(med = median(clv_12m), .groups = "drop") |>
  arrange(desc(med)) |>
  pull(segment)

p_clv_segment <- clv_output |>
  filter(!is.na(segment)) |>
  mutate(segment = factor(segment, levels = rev(segment_order))) |>
  ggplot(aes(x = clv_12m, y = segment, fill = segment)) +
  geom_boxplot(outlier.size = 0.6, outlier.alpha = 0.4, show.legend = FALSE) +
  scale_x_continuous(labels = dollar_format(prefix = "£")) +
  coord_cartesian(xlim = c(0, quantile(clv_output$clv_12m, 0.99, na.rm = TRUE))) +
  scale_fill_brewer(palette = "Blues") +
  labs(
    title    = "12-Month Predicted CLV by RFM Segment",
    subtitle = "BG/NBD × Gamma-Gamma model | Calibration: Dec 2009 – Jun 2011",
    x        = "Predicted 12-Month CLV (£)",
    y        = NULL
  ) +
  theme_minimal(base_size = 13) +
  theme(panel.grid.major.y = element_blank())

ggsave("outputs/figures/clv_03_clv_by_segment.png",
       p_clv_segment, width = 10, height = 7, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_03_clv_by_segment.png")

# ---- Segment Summary ----

segment_summary <- clv_output |>
  filter(!is.na(segment)) |>
  group_by(segment) |>
  summarise(
    n_customers  = n(),
    avg_p_alive  = mean(p_alive),
    median_clv   = median(clv_12m),
    mean_clv     = mean(clv_12m),
    total_clv    = sum(clv_12m),
    .groups      = "drop"
  ) |>
  arrange(desc(mean_clv))

message("\n========== CLV Summary by Segment ==========")
print(segment_summary, n = Inf)
message("=============================================\n")

# ---- Export ----

saveRDS(clv_output,       "data/processed/clv_predictions.rds")
write_csv(clv_output,     "data/processed/clv_predictions.csv")
write_csv(segment_summary,"data/processed/clv_segment_summary.csv")

message("Saved: data/processed/clv_predictions.rds")
message("Saved: data/processed/clv_predictions.csv")
message("Saved: data/processed/clv_segment_summary.csv")

# So what: 4,609 of 5,350 registered customers were modelled (those with at
# least one purchase before the Jun 2011 calibration cutoff). The BG/NBD model
# fit is solid — the validation plot shows predicted holdout transactions track
# actual behaviour closely across all frequency buckets.
#
# Total predicted 12-month CLV from the existing base: £6.32M.
# Champions (646 customers, 12% of base) account for £3.22M — 51% of all
# predicted revenue. This extreme concentration means losing even a small
# fraction of Champions would materially impact the business.
#
# Can't Lose Them is the segment most worth acting on urgently: avg P(alive)
# of 71.8% (vs 93.3% for Champions) confirms the model sees them actively
# disengaging, yet their avg 12-month CLV of £1,038 is comparable to Loyal
# Customers (£1,431). The revenue at risk from this segment is high relative
# to its size (320 customers).
#
# At Risk customers (1,071, 23% of base) generate only £469K in predicted CLV
# (7.4% of total) — their per-customer value (avg £438) is modest, so
# win-back investment should be evaluated carefully against cost.
#
# Model note: BG/NBD assigns P(alive) = 1.0 to all 1,485 customers with zero
# repeat purchases in calibration (x=0). This is expected model behaviour —
# with no repeat transactions, the model cannot distinguish inactive-but-alive
# from churned. CLV predictions for these customers (New Customers,
# Hibernating, Lost segments) are population-level priors, not individual
# signals, and should be treated accordingly.
#
# Implication: prioritise retention spend on Champions and Can't Lose Them;
# evaluate At Risk win-back ROI against the £438 avg CLV benchmark before
# committing budget.
