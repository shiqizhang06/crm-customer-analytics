# ============================================================
# 03_rfm_segmentation.R
# CRM Customer Analytics — RFM Segmentation
#
# Input:  data/processed/retail_clean.rds
# Output: data/processed/rfm_segments.rds
#         data/processed/rfm_segments.csv  (Tableau-ready)
#         outputs/figures/rfm_*.png
# ============================================================

library(tidyverse)
library(scales)

# ---- Load Cleaned Data ----

if (!file.exists("data/processed/retail_clean.rds")) {
  stop("Cleaned data not found. Run 01_data_cleaning.R first.")
}

df <- readRDS("data/processed/retail_clean.rds")
dir.create("outputs/figures",   recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed",    recursive = TRUE, showWarnings = FALSE)

message(sprintf("Loaded: %s rows, %s customers",
                comma(nrow(df)), comma(n_distinct(df$customer_id))))

# ---- Calculate RFM Metrics ----

analysis_date <- max(df$invoice_date_only) + 1

rfm <- df |>
  group_by(customer_id) |>
  summarise(
    recency   = as.integer(analysis_date - max(invoice_date_only)),  # days since last purchase
    frequency = n_distinct(invoice_no),                              # unique invoices
    monetary  = sum(total_amount) / n_distinct(invoice_no),          # avg spend per invoice
    .groups   = "drop"
  )

message(sprintf("Analysis date: %s", analysis_date))
message(sprintf("RFM metrics computed for %s customers", comma(nrow(rfm))))
message(sprintf("  Recency   — median %d days, range %d–%d",
                median(rfm$recency), min(rfm$recency), max(rfm$recency)))
message(sprintf("  Frequency — median %d orders, range %d–%d",
                median(rfm$frequency), min(rfm$frequency), max(rfm$frequency)))
message(sprintf("  Monetary  — median £%s, range £%s–£%s",
                comma(median(rfm$monetary), accuracy = 1),
                comma(min(rfm$monetary),    accuracy = 1),
                comma(max(rfm$monetary),    accuracy = 1)))

# ---- Score Each Dimension 1–5 (Quintiles) ----
# Recency is inverted: lower days since purchase = better = higher score

rfm <- rfm |>
  mutate(
    r_score = ntile(desc(recency),  5),
    f_score = ntile(frequency,      5),
    m_score = ntile(monetary,       5),
    rfm_score = paste0(r_score, f_score, m_score)
  )

# ---- Assign Segment Labels ----

assign_segment <- function(r, f, m) {
  case_when(
    r >= 4 & f >= 4 & m >= 4                     ~ "Champions",
    r >= 3 & f >= 3 & m >= 3                     ~ "Loyal Customers",
    r >= 4 & f <= 2                               ~ "New Customers",
    r >= 3 & f >= 2 & m >= 2                     ~ "Potential Loyalists",
    r == 3 & f >= 2 & m >= 2                     ~ "Need Attention",
    r <= 2 & f >= 4                              ~ "Can't Lose Them",
    r <= 2 & f >= 2                              ~ "At Risk",
    r <= 2 & f <= 2 & m >= 3                     ~ "Hibernating",
    r <= 2 & f <= 2                              ~ "Lost",
    TRUE                                          ~ "Promising"
  )
}

rfm <- rfm |>
  mutate(segment = assign_segment(r_score, f_score, m_score))

segment_counts <- rfm |>
  count(segment, sort = TRUE) |>
  mutate(pct = n / sum(n))

message("\nSegment distribution:")
print(segment_counts)

# ---- Plot 1: Segment Distribution Bar Chart ----

segment_order <- segment_counts |> arrange(n) |> pull(segment)

p_segments <- rfm |>
  count(segment) |>
  mutate(segment = factor(segment, levels = segment_order)) |>
  ggplot(aes(x = n, y = segment, fill = n)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = comma(n)), hjust = -0.15, size = 3.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.12)),
                     labels = comma) +
  scale_fill_gradient(low = "#bdd7e7", high = "#2171b5") +
  labs(
    title = "Customer Segment Distribution",
    x     = "Number of Customers",
    y     = NULL
  ) +
  theme_minimal(base_size = 13)

ggsave("outputs/figures/rfm_01_segment_distribution.png",
       p_segments, width = 9, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/rfm_01_segment_distribution.png")

# ---- Plot 2: Average Monetary Value by Segment ----

p_monetary <- rfm |>
  group_by(segment) |>
  summarise(avg_monetary = mean(monetary), .groups = "drop") |>
  mutate(segment = fct_reorder(segment, avg_monetary)) |>
  ggplot(aes(x = avg_monetary, y = segment, fill = avg_monetary)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = dollar(avg_monetary, prefix = "£", accuracy = 1)),
            hjust = -0.1, size = 3.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15)),
                     labels = dollar_format(prefix = "£")) +
  scale_fill_gradient(low = "#fee8c8", high = "#b30000") +
  labs(
    title = "Average Order Value by RFM Segment",
    x     = "Avg Spend per Invoice (£)",
    y     = NULL
  ) +
  theme_minimal(base_size = 13)

ggsave("outputs/figures/rfm_02_monetary_by_segment.png",
       p_monetary, width = 9, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/rfm_02_monetary_by_segment.png")

# ---- Plot 3: Treemap ----

if (requireNamespace("treemapify", quietly = TRUE)) {
  library(treemapify)

  p_treemap <- rfm |>
    group_by(segment) |>
    summarise(
      n_customers  = n(),
      total_revenue = sum(monetary * frequency),
      .groups = "drop"
    ) |>
    ggplot(aes(area = n_customers, fill = total_revenue, label = segment,
               subgroup = segment)) +
    geom_treemap() +
    geom_treemap_text(colour = "black", place = "centre", reflow = TRUE,
                      size = 12, fontface = "bold") +
    scale_fill_gradient(low = "#fee8c8", high = "#b30000",
                        labels = dollar_format(prefix = "£", scale = 1e-3, suffix = "K"),
                        name = "Est. Revenue") +
    labs(title = "RFM Segments — Area: # Customers, Colour: Est. Revenue") +
    theme_minimal(base_size = 13)

  ggsave("outputs/figures/rfm_03_treemap.png",
         p_treemap, width = 10, height = 7, dpi = 300, bg = "white")
  message("Saved: outputs/figures/rfm_03_treemap.png")
} else {
  message("treemapify not installed — skipping treemap (install with install.packages('treemapify'))")
}

# ---- Plot 4: RFM Score Heatmap (R vs F, coloured by avg M) ----

p_heatmap <- rfm |>
  group_by(r_score, f_score) |>
  summarise(avg_m = mean(m_score), .groups = "drop") |>
  ggplot(aes(x = factor(f_score), y = factor(r_score), fill = avg_m)) +
  geom_tile(colour = "white", linewidth = 0.8) +
  geom_text(aes(label = round(avg_m, 1)), size = 4) +
  scale_fill_gradient(low = "#fee8c8", high = "#b30000", name = "Avg M Score") +
  labs(
    title = "RFM Score Heatmap — Avg Monetary Score by R × F",
    x     = "Frequency Score (1 = lowest)",
    y     = "Recency Score (1 = oldest)"
  ) +
  theme_minimal(base_size = 13)

ggsave("outputs/figures/rfm_04_score_heatmap.png",
       p_heatmap, width = 7, height = 6, dpi = 300, bg = "white")
message("Saved: outputs/figures/rfm_04_score_heatmap.png")

# ---- Export ----

saveRDS(rfm, "data/processed/rfm_segments.rds")
write_csv(rfm, "data/processed/rfm_segments.csv")
message("Saved: data/processed/rfm_segments.rds")
message("Saved: data/processed/rfm_segments.csv")

# ---- Summary ----

message("\n========== RFM Summary ==========")
message(sprintf("  Analysis date:    %s", analysis_date))
message(sprintf("  Customers scored: %s", comma(nrow(rfm))))
message(sprintf("  Segments:         %s", n_distinct(rfm$segment)))
message(sprintf("  Champions:        %s (%.1f%%)",
                comma(sum(rfm$segment == "Champions")),
                100 * mean(rfm$segment == "Champions")))
message(sprintf("  At Risk + Lost:   %s (%.1f%%)",
                comma(sum(rfm$segment %in% c("At Risk", "Lost"))),
                100 * mean(rfm$segment %in% c("At Risk", "Lost"))))
message("==================================\n")

# So what: At Risk is the largest segment (1,071 customers, 20%) — a significant
# base of previously active customers now disengaging. Win-back campaigns are urgent.
# Loyal Customers (1,019) + Champions (675) + Potential Loyalists (613) = 2,307
# customers (43%) form the active, high-value core worth protecting.
# Hibernating customers have nearly the same AOV (£547) as Champions (£557),
# meaning these were once high-value buyers — targeted re-engagement could recover
# substantial revenue.
# New Customers also show strong AOV (£539); early nurture campaigns to convert
# them into Loyal/Champions should be a priority.
# The RFM heatmap confirms high-frequency buyers tend to spend more (F=5 column
# averages M score 3.4–3.6), reinforcing the value of driving repeat purchases.
# One exception: R=1, F=5 customers show low M score (2.6) — formerly frequent
# buyers who haven't returned, likely the "Can't Lose Them" segment requiring
# immediate intervention.
# Priority actions: retention programmes for Champions/Loyal; targeted reactivation
# for the 320 "Can't Lose Them" and 1,071 At Risk customers.
