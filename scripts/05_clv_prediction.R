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

# ---- Holdout Counts + Revenue (validation only) ----

holdout_activity <- elog |>
  filter(date > cal_end, date <= holdout_end) |>
  group_by(cust) |>
  summarise(
    x.holdout       = n(),
    revenue.holdout = sum(daily_revenue),
    .groups         = "drop"
  )

cal_cbs <- cal_cbs |>
  left_join(holdout_activity, by = "cust") |>
  mutate(
    x.holdout       = replace_na(x.holdout, 0L),
    revenue.holdout = replace_na(revenue.holdout, 0)
  )

# ---- Fit BG/NBD Model ----

message("Fitting BG/NBD model...")

cbs_matrix   <- cal_cbs |> select(x, t.x, T.cal) |> as.matrix()
bgnbd_params <- bgnbd.EstimateParameters(cbs_matrix)
names(bgnbd_params) <- c("r", "alpha", "a", "b")

message(sprintf("  Params — r: %.3f, alpha: %.3f, a: %.3f, b: %.3f",
                bgnbd_params[["r"]], bgnbd_params[["alpha"]],
                bgnbd_params[["a"]], bgnbd_params[["b"]]))

cal_cbs <- cal_cbs |>
  mutate(
    p_alive = mapply(
      function(xi, tx, Tc) bgnbd.PAlive(bgnbd_params, xi, tx, Tc),
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

# ---- Plot 1: BG/NBD Validation — Actual vs Predicted by Frequency ----

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

# ---- Performance Metrics ----

mae_model  <- mean(abs(cal_cbs$pred_holdout - cal_cbs$x.holdout))
mae_naive  <- mean(abs(mean(cal_cbs$x.holdout) - cal_cbs$x.holdout))
mae_lift   <- 1 - mae_model / mae_naive
pred_cor   <- cor(cal_cbs$pred_holdout, cal_cbs$x.holdout)
agg_actual <- sum(cal_cbs$x.holdout)
agg_pred   <- sum(cal_cbs$pred_holdout)
agg_error  <- (agg_pred - agg_actual) / agg_actual

message("\n========== BG/NBD Performance Metrics ==========")
message(sprintf("  MAE — model: %.3f | naive: %.3f | lift: %.1f%%",
                mae_model, mae_naive, mae_lift * 100))
message(sprintf("  Correlation (pred vs actual):  %.3f", pred_cor))
message(sprintf("  Aggregate — predicted: %s | actual: %s | error: %+.1f%%",
                comma(round(agg_pred)), comma(agg_actual), agg_error * 100))
message("=================================================\n")

# ---- Plot 2: Calibration Frequency Distribution ----
# Compares actual distribution of repeat purchases against what the
# fitted BG/NBD model expects — a direct test of model fit on calibration data

max_x <- 7L

expected_exact <- sapply(0:(max_x - 1L), function(k) {
  sum(mapply(function(Tc) bgnbd.pmf(bgnbd_params, Tc, k), cal_cbs$T.cal))
})
expected_plus <- nrow(cal_cbs) - sum(expected_exact)

freq_dist <- bind_rows(
  cal_cbs |>
    mutate(x_cap = pmin(x, max_x)) |>
    count(x_cap) |>
    mutate(source = "Actual"),
  tibble(
    x_cap  = 0:max_x,
    n      = c(expected_exact, expected_plus),
    source = "Model Expected"
  )
) |>
  mutate(
    x_label = factor(x_cap, labels = c(as.character(0:(max_x - 1L)), paste0(max_x, "+"))),
    pct     = n / nrow(cal_cbs)
  )

p_freq_dist <- ggplot(freq_dist,
                      aes(x = x_label, y = pct, fill = source)) +
  geom_col(position = "dodge", width = 0.7, alpha = 0.9) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("Actual" = "#08519c", "Model Expected" = "#fc8d59"),
                    name = NULL) +
  labs(
    title    = "Calibration Frequency Distribution — Actual vs Model Expected",
    subtitle = "How well the fitted BG/NBD parameters reproduce the observed purchase frequency distribution",
    x        = "Number of Repeat Purchases in Calibration",
    y        = "% of Customers"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "top")

ggsave("outputs/figures/clv_02_freq_distribution.png",
       p_freq_dist, width = 9, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_02_freq_distribution.png")

# ---- Plot 3: P(alive) Calibration Check ----
# For customers with x >= 1, group by P(alive) quintile and check what
# fraction actually returned in holdout — well-calibrated model tracks diagonal

palive_cal <- cal_cbs |>
  filter(x >= 1) |>
  mutate(
    palive_bin = cut(p_alive,
                     breaks = seq(0, 1, 0.2),
                     labels = c("0–20%", "20–40%", "40–60%", "60–80%", "80–100%"),
                     include.lowest = TRUE)
  ) |>
  group_by(palive_bin) |>
  summarise(
    n             = n(),
    avg_p_alive   = mean(p_alive),
    pct_returned  = mean(x.holdout > 0),
    .groups       = "drop"
  )

p_palive_cal <- ggplot(palive_cal,
                       aes(x = avg_p_alive, y = pct_returned)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed",
              colour = "grey60", linewidth = 0.8) +
  geom_point(aes(size = n), colour = "#08519c", alpha = 0.85) +
  geom_text(aes(label = palive_bin), vjust = -1, size = 3.5) +
  scale_x_continuous(labels = percent_format(), limits = c(0, 1)) +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
  scale_size_continuous(range = c(4, 12), name = "Customers") +
  labs(
    title    = "P(Alive) Calibration Check",
    subtitle = "Repeat-purchase customers only (x ≥ 1) — dashed line = perfect calibration",
    x        = "Model P(Alive) — Group Average",
    y        = "Actual % Returning in Holdout"
  ) +
  theme_minimal(base_size = 13)

ggsave("outputs/figures/clv_03_palive_calibration.png",
       p_palive_cal, width = 8, height = 7, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_03_palive_calibration.png")

# ---- Fit Gamma-Gamma Spend Model ----
# Only customers with >= 1 repeat purchase can estimate spend parameters

message("Fitting Gamma-Gamma spend model...")

gg_data      <- cal_cbs |> filter(x >= 1)
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
exp_spend_vec              <- rep(prior_mean_spend, nrow(cal_cbs))
repeat_mask                <- cal_cbs$x >= 1
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
    exp_transactions_12m, exp_spend, clv_12m,
    revenue.holdout
  )

# ---- Plot 4: P(alive) Distribution ----

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

ggsave("outputs/figures/clv_04_p_alive_distribution.png",
       p_alive_plot, width = 9, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_04_p_alive_distribution.png")

# ---- Plot 5: CLV Distribution by RFM Segment ----

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

ggsave("outputs/figures/clv_05_clv_by_segment.png",
       p_clv_segment, width = 10, height = 7, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_05_clv_by_segment.png")

# ---- Plot 6: Top Decile Lift ----
# Rank customers by predicted CLV; check what share of actual holdout
# revenue each decile captures — measures business value of the ranking

decile_summary <- clv_output |>
  mutate(clv_decile = ntile(clv_12m, 10)) |>
  group_by(clv_decile) |>
  summarise(
    actual_revenue = sum(revenue.holdout),
    n_customers    = n(),
    .groups        = "drop"
  ) |>
  mutate(
    revenue_share    = actual_revenue / sum(actual_revenue),
    cumulative_share = cumsum(revenue_share),
    random_share     = clv_decile / 10
  )

top_decile_lift <- decile_summary |>
  filter(clv_decile == 10) |>
  pull(revenue_share)

message(sprintf("  Top decile captures %.1f%% of holdout revenue (%.1fx random chance)",
                top_decile_lift * 100, top_decile_lift * 10))

p_decile <- ggplot(decile_summary, aes(x = clv_decile)) +
  geom_col(aes(y = revenue_share), fill = "#08519c", alpha = 0.85, width = 0.7) +
  geom_line(aes(y = 1 / 10), colour = "#d94701", linetype = "dashed",
            linewidth = 0.9) +
  geom_text(aes(y = revenue_share,
                label = percent(revenue_share, accuracy = 1)),
            vjust = -0.5, size = 3.3) +
  annotate("text", x = 9.5, y = 1 / 10 + 0.005,
           label = "Random baseline (10%)", hjust = 1,
           colour = "#d94701", size = 3.3) +
  scale_x_continuous(breaks = 1:10,
                     labels = paste0(1:10 * 10, "%")) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.12))) +
  labs(
    title    = "Top Decile Lift — Predicted CLV vs Actual Holdout Revenue",
    subtitle = "Customers ranked by predicted 12-month CLV; bars show share of actual holdout revenue captured",
    x        = "Predicted CLV Percentile (bottom → top)",
    y        = "Share of Actual Holdout Revenue"
  ) +
  theme_minimal(base_size = 13) +
  theme(panel.grid.major.x = element_blank())

ggsave("outputs/figures/clv_06_top_decile_lift.png",
       p_decile, width = 10, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/clv_06_top_decile_lift.png")

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

saveRDS(clv_output,        "data/processed/clv_predictions.rds")
write_csv(clv_output,      "data/processed/clv_predictions.csv")
write_csv(segment_summary, "data/processed/clv_segment_summary.csv")

message("Saved: data/processed/clv_predictions.rds")
message("Saved: data/processed/clv_predictions.csv")
message("Saved: data/processed/clv_segment_summary.csv")

# So what: 4,609 of 5,350 registered customers modelled (those with at least
# one purchase before the Jun 2011 calibration cutoff).
#
# Model performance (plots 01–03):
# Plot 01 shows predicted holdout transactions track actual closely across all
# calibration frequency bins — MAE lift of 39.4% over the naive baseline,
# correlation of 0.832, aggregate error of only -4.4% (6,175 predicted vs
# 6,457 actual transactions). Plot 02 confirms the fitted parameters reproduce
# the observed calibration frequency distribution well. One caveat from
# plot 03: P(alive) shows systematic optimism of ~10–15pp across all bins —
# use a 60% threshold (not 50%) when selecting targets to avoid wasting budget
# on already-churned customers.
#
# Customer activity (plot 04):
# The P(alive) distribution is heavily right-skewed — the majority of repeat
# buyers show >75% probability of still being active, consistent with a 2-year
# observation window on a seasonal gift retailer.
#
# CLV by segment (plot 05):
# Champions dominate with median predicted 12-month CLV ~£2,300 and a long
# tail to £10K+; total £3.22M from 646 customers (51% of the £6.32M base).
# Can't Lose Them shows the lowest avg P(alive) (71.8%) among active segments,
# confirming disengagement despite CLV comparable to Loyal Customers — the
# most urgent retention priority.
#
# Business case (plot 06):
# Top decile lift of 5.8x — the top 10% by predicted CLV captured 58% of
# actual holdout revenue; top 20% captured ~71%. Recommended tiering: VIP
# treatment for top decile, standard nurture for deciles 7–9, reactivation
# evaluation for the rest. Combine with RFM labels for campaign design:
# high-CLV Champions get retention offers; high-CLV At Risk get win-back
# with ROI benchmarked against their £438 avg CLV.
#
# Model note: BG/NBD assigns P(alive) = 1.0 to all 1,485 customers with x=0.
# CLV predictions for New Customers, Hibernating, and Lost segments are
# population-level priors, not individual signals — treat accordingly.
