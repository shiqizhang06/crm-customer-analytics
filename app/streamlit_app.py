import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import sqlite3
from pathlib import Path

# ── Page config ──────────────────────────────────────────────────────────────

st.set_page_config(
    page_title="CRM Analytics",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Design tokens ─────────────────────────────────────────────────────────────
# Direction: Precision & Density / Data & Analysis
# Foundation: Deep navy + amber accent  |  Font: Space Grotesk
# Depth: Bordered cards, 2px top accent strip — no shadows
# Base colours also declared in .streamlit/config.toml (Streamlit theming wins
# over CSS injection for body/text colours, so both layers are needed).

COLORS = {
    "bg":           "#0A1628",
    "surface":      "#112240",
    "surface_2":    "#1A3560",
    "border":       "#1E3A5F",
    "primary":      "#3D8EF0",
    "accent":       "#F59E0B",
    "text":         "#E2E8F0",
    "text_muted":   "#8B9EC4",
    "success":      "#34D399",
    "danger":       "#F87171",
    "warning":      "#FBBF24",
}

FONT = "Space Grotesk"

# Business-value order for all segment dropdowns (high → low engagement tier)
SEGMENT_ORDER = [
    "Champions", "Loyal Customers", "Potential Loyalists", "Promising",
    "New Customers", "At Risk", "Can't Lose Them", "Hibernating", "Lost",
]

# ── CSS injection ─────────────────────────────────────────────────────────────
# Inject font <link> and <style> in separate calls — combining them causes the
# CSS to render as visible text in some Streamlit versions.

st.markdown(
    '<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk'
    ':wght@300;400;500;600;700&display=swap" rel="stylesheet">',
    unsafe_allow_html=True,
)

_CSS = f"""
  html, body, [class*="css"] {{
    font-family: '{FONT}', sans-serif !important;
    background-color: {COLORS["bg"]} !important;
    color: {COLORS["text"]} !important;
  }}
  .stApp, [data-testid="stAppViewContainer"],
  [data-testid="stMain"], [data-testid="stVerticalBlock"] {{
    background-color: {COLORS["bg"]} !important;
  }}
  p, li {{ color: {COLORS["text"]} !important; }}

  [data-testid="stSidebar"] {{
    background-color: {COLORS["surface"]} !important;
    border-right: 1px solid {COLORS["border"]};
  }}
  [data-testid="stSidebar"] .stRadio [aria-checked="true"] + div {{
    color: {COLORS["accent"]} !important;
    font-weight: 600 !important;
  }}

  h1 {{ color: {COLORS["text"]} !important; font-weight: 700; font-size: 1.6rem; }}
  h2 {{ color: {COLORS["text"]} !important; font-weight: 600; font-size: 1.2rem; }}
  h3 {{ color: {COLORS["text_muted"]} !important; font-weight: 500; font-size: 1rem; }}

  /* ── KPI cards ── */
  .kpi-card {{
    background: {COLORS["surface"]};
    border: 1px solid {COLORS["border"]};
    border-radius: 8px;
    padding: 20px 24px;
    min-height: 90px;
    position: relative;
    overflow: hidden;
  }}
  .kpi-card::before {{
    content: "";
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 2px;
    background: {COLORS["primary"]};
  }}
  .kpi-label {{
    font-size: 11px !important;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: {COLORS["text_muted"]} !important;
    margin-bottom: 8px;
  }}
  .kpi-value {{
    font-size: 28px;
    font-weight: 700;
    color: {COLORS["text"]} !important;
    line-height: 1;
  }}
  .kpi-sub {{
    font-size: 12px;
    color: {COLORS["text_muted"]} !important;
    margin-top: 6px;
  }}
  .kpi-accent::before {{ background: {COLORS["accent"]}; }}

  .seg-badge {{
    display: inline-block;
    background: {COLORS["surface_2"]};
    border: 1px solid {COLORS["primary"]};
    border-radius: 20px;
    padding: 4px 14px;
    font-size: 13px;
    font-weight: 600;
    color: {COLORS["primary"]} !important;
    letter-spacing: 0.03em;
  }}

  .rfm-row {{
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 10px;
  }}
  .rfm-label {{
    width: 24px;
    font-size: 12px;
    font-weight: 600;
    color: {COLORS["text_muted"]} !important;
  }}
  .rfm-track {{
    flex: 1;
    height: 8px;
    background: {COLORS["surface_2"]};
    border-radius: 4px;
    overflow: hidden;
  }}
  .rfm-fill {{
    height: 100%;
    border-radius: 4px;
    background: linear-gradient(90deg, {COLORS["primary"]}, {COLORS["accent"]});
  }}
  .rfm-score {{
    width: 20px;
    font-size: 13px;
    font-weight: 700;
    color: {COLORS["text"]} !important;
    text-align: right;
  }}

  .rec-box {{
    background: {COLORS["surface"]};
    border: 1px solid {COLORS["border"]};
    border-left: 3px solid {COLORS["accent"]};
    border-radius: 0 8px 8px 0;
    padding: 14px 18px;
    margin-top: 16px;
    font-size: 13px;
    color: {COLORS["text_muted"]} !important;
    line-height: 1.6;
  }}
  .rec-box strong {{ color: {COLORS["accent"]} !important; }}

  .insight-box {{
    background: {COLORS["surface"]};
    border: 1px solid {COLORS["border"]};
    border-left: 3px solid {COLORS["primary"]};
    border-radius: 0 8px 8px 0;
    padding: 14px 18px;
    margin-bottom: 12px;
    font-size: 13px;
    color: {COLORS["text_muted"]} !important;
    line-height: 1.6;
  }}
  .insight-box strong {{ color: {COLORS["text"]} !important; }}

  .alert-box {{
    background: rgba(248,113,113,0.08);
    border: 1px solid {COLORS["danger"]};
    border-radius: 8px;
    padding: 14px 18px;
    font-size: 13px;
    color: {COLORS["danger"]} !important;
  }}

  /* ── Selectbox — primary blue border signals interactivity ── */
  [data-testid="stSelectbox"] label {{
    color: {COLORS["text_muted"]} !important;
    font-size: 11px !important;
    font-weight: 600 !important;
    letter-spacing: 0.06em !important;
    text-transform: uppercase !important;
  }}
  [data-testid="stSelectbox"] > div > div {{
    background-color: {COLORS["surface_2"]} !important;
    border: 1px solid {COLORS["primary"]} !important;
    border-radius: 6px !important;
    color: {COLORS["text"]} !important;
    font-weight: 500 !important;
  }}
  [data-testid="stSelectbox"] > div > div:hover {{
    border-color: {COLORS["accent"]} !important;
  }}
  [data-testid="stSelectbox"] svg {{
    fill: {COLORS["primary"]} !important;
  }}

  hr {{ border-color: {COLORS["border"]}; margin: 24px 0; }}
  #MainMenu, footer, header {{ visibility: hidden; }}
  .block-container {{ padding-top: 2rem; }}
"""

st.markdown(f"<style>{_CSS}</style>", unsafe_allow_html=True)

# ── Plotly base theme ─────────────────────────────────────────────────────────
# margin and coloraxis_colorbar are excluded — passing them here AND in
# update_layout() raises a duplicate-keyword crash. Use plot_layout(**overrides).

PLOTLY_BASE = dict(
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    font=dict(family=f"{FONT}, sans-serif", color=COLORS["text"], size=13),
    hoverlabel=dict(
        bgcolor=COLORS["surface_2"],
        bordercolor=COLORS["border"],
        font=dict(family=f"{FONT}, sans-serif", color=COLORS["text"], size=12),
    ),
)

_DEFAULT_MARGIN = dict(l=16, r=16, t=40, b=16)

def plot_layout(**overrides):
    """Merge PLOTLY_BASE + default margin with per-chart overrides."""
    return {**PLOTLY_BASE, "margin": _DEFAULT_MARGIN, **overrides}

# ── Database ──────────────────────────────────────────────────────────────────

DB_PATH = Path(__file__).parent.parent / "data" / "processed" / "crm.db"

SEGMENT_ACTIONS = {
    "Champions": (
        "VIP retention priority. This segment (646 customers) drives 51% of predicted "
        "12-month revenue — losing even a small fraction has material impact. "
        "<strong>Action:</strong> exclusive VIP perks, referral programme, early product access. "
        "The top CLV decile captures 58% of holdout revenue; protect it at all costs."
    ),
    "Loyal Customers": (
        "Deepen engagement to protect frequency and spend. Strong P(alive) of 90.6% means "
        "they're active — the goal is preventing migration into At Risk. "
        "<strong>Action:</strong> loyalty rewards, cross-sell adjacent categories, "
        "tier-upgrade messaging toward Champions."
    ),
    "Potential Loyalists": (
        "Highest conversion efficiency. P(alive) of 93% and growing spend signal these "
        "customers are on an upward trajectory. "
        "<strong>Action:</strong> introduce loyalty programme post-2nd purchase, "
        "targeted follow-up to accelerate to Loyal tier."
    ),
    "Promising": (
        "Early-stage, high-engagement customers. P(alive) 92.8% but low frequency. "
        "<strong>Action:</strong> post-purchase nurture sequence (7-day, 21-day follow-ups) "
        "to overcome the M1 retention cliff — 77% of first-time buyers never return. "
        "Push toward second purchase before month 1 ends."
    ),
    "New Customers": (
        "Critical intervention window: the first 30 days. AOV of £539 is strong but 77% "
        "of first-time buyers never return. "
        "<strong>Action:</strong> 7-day and 21-day post-purchase nurture, welcome series, "
        "introduce product discovery to drive a second order."
    ),
    "At Risk": (
        "Largest segment by count (1,071 customers) but modest avg CLV of £438. "
        "Win-back ROI must be evaluated carefully. "
        "<strong>Action:</strong> personalised re-engagement offer; benchmark campaign cost "
        "against the £438 CLV ceiling. Prioritise the higher-CLV customers within this segment."
    ),
    "Can't Lose Them": (
        "Most urgent retention priority. Avg CLV of £1,038 is comparable to Loyal Customers, "
        "but P(alive) has dropped to 71.8% — the lowest among active segments. "
        "<strong>Action:</strong> immediate win-back outreach, premium incentive, "
        "direct account manager contact for top spenders within this group."
    ),
    "Hibernating": (
        "Previously high-value buyers (AOV £547, nearly matching Champions at £557). "
        "Standard campaign ROI is low, but seasonal reactivation is worth attempting. "
        "<strong>Action:</strong> suppress from regular campaigns; include in Q4 "
        "Christmas blasts only. A targeted seasonal offer may reactivate a portion."
    ),
    "Lost": (
        "Cost of reactivation likely exceeds expected CLV for most customers in this group. "
        "<strong>Action:</strong> suppress from active campaigns. Include in annual "
        "deep-discount win-back only; do not invest recurring budget here."
    ),
}

def get_conn():
    if not DB_PATH.exists():
        st.markdown(f"""
        <div class="alert-box">
          <strong>Database not found</strong> at <code>{DB_PATH}</code><br><br>
          Run <code>Rscript scripts/07_load_to_sqlite.R</code> from the project root.
        </div>
        """, unsafe_allow_html=True)
        st.stop()
    return sqlite3.connect(DB_PATH, check_same_thread=False)

@st.cache_data(ttl=300)
def query(sql, params=None):
    with get_conn() as conn:
        return pd.read_sql_query(sql, conn, params=params or [])

def sort_segments(seg_list):
    """Return segments sorted in business-value order (Champions → Lost)."""
    order = {s: i for i, s in enumerate(SEGMENT_ORDER)}
    return sorted(seg_list, key=lambda s: order.get(s, 99))

def kpi_card(label, value, sub=None, accent=False):
    cls = "kpi-card kpi-accent" if accent else "kpi-card"
    sub_html = f'<div class="kpi-sub">{sub}</div>' if sub else ""
    return f"""
    <div class="{cls}">
      <div class="kpi-label">{label}</div>
      <div class="kpi-value">{value}</div>
      {sub_html}
    </div>"""

def rfm_bar(label, score):
    pct = score / 5 * 100
    return f"""
    <div class="rfm-row">
      <div class="rfm-label">{label}</div>
      <div class="rfm-track"><div class="rfm-fill" style="width:{pct}%"></div></div>
      <div class="rfm-score">{score}</div>
    </div>"""

def fmt_gbp(v):
    if pd.isna(v): return "N/A"
    return f"£{v:,.0f}"

def fmt_pct(v):
    if pd.isna(v): return "N/A"
    return f"{v:.1%}"

def clv_decile_label(decile_n):
    """Convert ntile(1–10) to human label. ntile 10 = highest CLV = Top 10%."""
    top_pct = (11 - int(decile_n)) * 10
    if top_pct <= 50:
        return f"Top {top_pct}%"
    else:
        return f"Bottom {int(decile_n) * 10}%"

# ── Sidebar ───────────────────────────────────────────────────────────────────

with st.sidebar:
    st.markdown(f"""
    <div style="padding:8px 0 24px">
      <div style="font-size:18px;font-weight:700;color:{COLORS['text']}">CRM Analytics</div>
      <div style="font-size:11px;color:{COLORS['text_muted']};margin-top:4px">
        UCI Online Retail II · UK Customers
      </div>
    </div>
    """, unsafe_allow_html=True)

    page = st.radio(
        "Navigation",
        ["Customer Lookup", "Segment Explorer", "Cohort Retention"],
        label_visibility="collapsed",
    )

    st.markdown("<hr>", unsafe_allow_html=True)
    st.markdown(f"""
    <div style="font-size:11px;color:{COLORS['text_muted']};line-height:1.7">
      5,350 UK customers<br>
      Dec 2009 – Dec 2011<br>
      BG/NBD + Gamma-Gamma CLV
    </div>
    """, unsafe_allow_html=True)

# ── Page 1: Customer Lookup ───────────────────────────────────────────────────

if page == "Customer Lookup":
    st.markdown("## Customer Lookup")
    st.markdown(f'<div style="color:{COLORS["text_muted"]};font-size:13px;margin-bottom:24px">'
                "Individual customer profile — RFM scores, predicted CLV, and purchase history.</div>",
                unsafe_allow_html=True)

    customer_ids = (
        query("SELECT CAST(customer_id AS INTEGER) AS customer_id "
              "FROM customer_master ORDER BY customer_id")
        ["customer_id"].astype(int).tolist()
    )

    selected_id = st.selectbox("Customer ID", options=customer_ids, index=0)

    customer = query(
        "SELECT * FROM customer_master WHERE CAST(customer_id AS INTEGER) = ?",
        params=[int(selected_id)],
    )

    if customer.empty:
        st.markdown('<div class="alert-box">Customer not found.</div>', unsafe_allow_html=True)
        st.stop()

    c = customer.iloc[0]
    segment = c["segment"]

    col_id, col_seg = st.columns([1, 3])
    with col_id:
        st.markdown(f"""
        <div style="font-size:13px;color:{COLORS['text_muted']};margin-bottom:4px">Customer ID</div>
        <div style="font-size:28px;font-weight:700;color:{COLORS['text']}">{int(c['customer_id'])}</div>
        """, unsafe_allow_html=True)
    with col_seg:
        st.markdown(f"""
        <div style="font-size:13px;color:{COLORS['text_muted']};margin-bottom:4px">Segment</div>
        <div class="seg-badge">{segment}</div>
        """, unsafe_allow_html=True)

    st.markdown("<hr>", unsafe_allow_html=True)

    # CLV decile: R ntile(10) assigns 1=lowest, 10=highest CLV
    decile_label = clv_decile_label(c["clv_decile"]) if pd.notna(c["clv_decile"]) else "N/A"

    # P(alive): BG/NBD assigns 1.0 to customers with 0 repeat transactions —
    # the model can't infer churn probability without repeat-purchase evidence.
    if pd.isna(c["p_alive"]):
        palive     = "N/A"
        palive_sub = "No CLV model data"
    elif pd.notna(c["cal_frequency"]) and int(c["cal_frequency"]) == 0:
        palive     = "—"
        palive_sub = "Single transaction — model n/a"
    else:
        palive     = fmt_pct(c["p_alive"])
        palive_sub = "Probability still active"

    col1, col2, col3, col4 = st.columns(4)
    col1.markdown(kpi_card("Total Revenue", fmt_gbp(c["total_revenue"]),
                           f"{int(c['total_orders'])} orders"), unsafe_allow_html=True)
    # Accent (amber top-strip) marks the single primary metric on this page
    col2.markdown(kpi_card("Predicted 12M CLV", fmt_gbp(c["clv_12m"]),
                           "12-month BG/NBD model", accent=True), unsafe_allow_html=True)
    col3.markdown(kpi_card("CLV Decile", decile_label,
                           "vs all customers (10 = highest)"), unsafe_allow_html=True)
    col4.markdown(kpi_card("P(Alive)", palive, palive_sub), unsafe_allow_html=True)

    st.markdown("<br>", unsafe_allow_html=True)

    col_rfm, col_chart = st.columns([1, 2])

    with col_rfm:
        st.markdown(f'<div style="font-size:12px;font-weight:600;letter-spacing:.06em;'
                    f'text-transform:uppercase;color:{COLORS["text_muted"]};margin-bottom:12px">'
                    "RFM Scores</div>", unsafe_allow_html=True)
        st.markdown(
            rfm_bar("R", int(c["r_score"])) +
            rfm_bar("F", int(c["f_score"])) +
            rfm_bar("M", int(c["m_score"])),
            unsafe_allow_html=True,
        )
        st.markdown(f"""
        <div style="margin-top:16px;font-size:12px;color:{COLORS['text_muted']}">
          <div style="margin-bottom:4px">First purchase:
            <strong style="color:{COLORS['text']}">{c['first_purchase_date']}</strong></div>
          <div style="margin-bottom:4px">Last purchase:
            <strong style="color:{COLORS['text']}">{c['last_purchase_date']}</strong></div>
          <div>Recency:
            <strong style="color:{COLORS['text']}">{int(c['recency'])} days</strong></div>
        </div>
        """, unsafe_allow_html=True)

    with col_chart:
        # invoice_date is stored as R's integer day-count (days since 1970-01-01).
        # SQLite strftime() on a bare integer treats it as a Julian Day Number,
        # producing dates like -4672. Convert via date('1970-01-01', '+N days').
        history = query("""
            SELECT strftime('%Y-%m',
                       date('1970-01-01',
                            '+' || CAST(invoice_date AS INTEGER) || ' days')
                   ) AS month,
                   SUM(total_amount) AS revenue
            FROM retail_clean
            WHERE CAST(customer_id AS INTEGER) = ?
            GROUP BY month
            ORDER BY month
        """, params=[int(selected_id)])

        if not history.empty:
            fig = px.bar(
                history, x="month", y="revenue",
                color_discrete_sequence=[COLORS["primary"]],
                title="Monthly Purchase Revenue",
            )
            fig.update_layout(
                **plot_layout(),
                # type="category" prevents Plotly interpolating date strings as
                # timestamps, which produces "23:59:59.9996" ticks on sparse data
                xaxis=dict(showgrid=False, title=None, type="category",
                           tickfont=dict(color=COLORS["text_muted"])),
                yaxis=dict(showgrid=True, gridcolor=COLORS["border"],
                           title="Revenue (£)", tickprefix="£",
                           tickfont=dict(color=COLORS["text_muted"])),
            )
            fig.update_traces(marker_line_width=0)
            st.plotly_chart(fig, use_container_width=True)

    action = SEGMENT_ACTIONS.get(segment, "No recommendation available for this segment.")
    st.markdown(
        f'<div class="rec-box"><strong>Recommended action ({segment}):</strong> {action}</div>',
        unsafe_allow_html=True,
    )


# ── Page 2: Segment Explorer ──────────────────────────────────────────────────

elif page == "Segment Explorer":

    totals = query("""
        SELECT COUNT(*)          AS total_customers,
               SUM(total_revenue)  AS total_revenue,
               AVG(clv_12m)        AS avg_clv
        FROM customer_master
    """).iloc[0]

    # Weighted M1 retention: sum actives / sum cohort sizes (not mean of rates)
    m1_rate = query("""
        SELECT CAST(SUM(n_active) AS REAL) / SUM(cohort_size) AS avg_m1
        FROM (
            SELECT cohort_month,
                   SUM(n_active)    AS n_active,
                   SUM(cohort_size) AS cohort_size
            FROM cohort_retention
            WHERE period_number = 1
            GROUP BY cohort_month
        )
    """).iloc[0]["avg_m1"]

    st.markdown("## Segment Explorer")
    st.markdown(f'<div style="color:{COLORS["text_muted"]};font-size:13px;margin-bottom:24px">'
                "Overview of all segments, then select one to deep-dive.</div>",
                unsafe_allow_html=True)

    # ── Global KPIs ──
    col1, col2, col3, col4 = st.columns(4)
    col1.markdown(kpi_card("Total Customers", f"{int(totals['total_customers']):,}",
                           "UK registered"), unsafe_allow_html=True)
    col2.markdown(kpi_card("Total Revenue", fmt_gbp(totals["total_revenue"]),
                           "Dec 2009 – Dec 2011"), unsafe_allow_html=True)
    col3.markdown(kpi_card("Avg Predicted CLV", fmt_gbp(totals["avg_clv"]),
                           "12-month, BG/NBD model", accent=True), unsafe_allow_html=True)
    col4.markdown(kpi_card("Avg M1 Retention", fmt_pct(m1_rate),
                           "Weighted across all cohorts"), unsafe_allow_html=True)

    st.markdown("<hr>", unsafe_allow_html=True)

    # ── All-segments overview charts ──
    st.markdown(f'<div style="font-size:11px;font-weight:600;letter-spacing:.06em;'
                f'text-transform:uppercase;color:{COLORS["text_muted"]};margin-bottom:16px">'
                "All Segments — Overview</div>", unsafe_allow_html=True)

    all_seg_raw = query("SELECT * FROM segment_summary")
    seg_names_available = all_seg_raw["segment"].tolist()
    seg_names_sorted = sort_segments(seg_names_available)

    # Segment selector — drives the deep-dive section below
    selected_seg = st.selectbox(
        "Segment",
        options=seg_names_sorted,
        index=0,
    )

    all_seg = all_seg_raw.copy()

    col_left, col_right = st.columns(2)

    with col_left:
        df_bar = all_seg.sort_values("n_customers")
        bar_colors = [
            COLORS["accent"] if s == selected_seg else COLORS["primary"]
            for s in df_bar["segment"]
        ]
        fig_bar = go.Figure(go.Bar(
            x=df_bar["n_customers"],
            y=df_bar["segment"],
            orientation="h",
            marker_color=bar_colors,
            hovertemplate="%{y}: %{x:,} customers<extra></extra>",
        ))
        fig_bar.update_layout(
            **plot_layout(),
            title="Customers by Segment",
            xaxis=dict(showgrid=True, gridcolor=COLORS["border"],
                       title="Customers", tickfont=dict(color=COLORS["text_muted"])),
            yaxis=dict(showgrid=False, title=None, tickfont=dict(color=COLORS["text"])),
            showlegend=False,
        )
        st.plotly_chart(fig_bar, use_container_width=True)

    with col_right:
        df_clv = all_seg.sort_values("mean_clv")
        clv_colors = [
            COLORS["accent"] if s == selected_seg else COLORS["primary"]
            for s in df_clv["segment"]
        ]
        fig_clv = go.Figure(go.Bar(
            x=df_clv["mean_clv"],
            y=df_clv["segment"],
            orientation="h",
            marker_color=clv_colors,
            hovertemplate="%{y}: £%{x:,.0f} avg CLV<extra></extra>",
        ))
        fig_clv.update_layout(
            **plot_layout(),
            title="Avg Predicted CLV by Segment",
            xaxis=dict(showgrid=True, gridcolor=COLORS["border"],
                       title="Avg 12M CLV (£)", tickprefix="£",
                       tickfont=dict(color=COLORS["text_muted"])),
            yaxis=dict(showgrid=False, title=None, tickfont=dict(color=COLORS["text"])),
            showlegend=False,
        )
        st.plotly_chart(fig_clv, use_container_width=True)

    all_seg["total_revenue_est"] = all_seg["avg_monetary"] * all_seg["n_customers"]
    fig_tree = px.treemap(
        all_seg,
        path=["segment"],
        values="total_revenue_est",
        title="Revenue Share by Segment  (avg monetary × customers)",
        color="mean_clv",
        color_continuous_scale=[
            [0,   COLORS["surface_2"]],
            [0.5, COLORS["primary"]],
            [1,   COLORS["accent"]],
        ],
    )
    fig_tree.update_layout(
        **plot_layout(
            coloraxis_colorbar=dict(
                title="Avg CLV (£)",
                tickprefix="£",
                tickfont=dict(color=COLORS["text"]),
                titlefont=dict(color=COLORS["text"]),
            )
        )
    )
    fig_tree.update_traces(
        textfont=dict(family=f"{FONT}, sans-serif", color="white"),
        marker_line_width=2,
        marker_line_color=COLORS["bg"],
    )
    st.plotly_chart(fig_tree, use_container_width=True)

    # ── Segment deep-dive ──
    st.markdown("<hr>", unsafe_allow_html=True)
    st.markdown(f'<div style="font-size:11px;font-weight:600;letter-spacing:.06em;'
                f'text-transform:uppercase;color:{COLORS["text_muted"]};margin-bottom:16px">'
                f"Segment Deep-Dive — {selected_seg}</div>", unsafe_allow_html=True)

    seg_data    = query("SELECT * FROM customer_master WHERE segment = ?",
                        params=[selected_seg])
    seg_summary = query("SELECT * FROM segment_summary WHERE segment = ?",
                        params=[selected_seg]).iloc[0]

    seg_count = len(seg_data)
    seg_pct   = seg_count / int(totals["total_customers"])

    col1, col2, col3, col4, col5 = st.columns(5)
    col1.markdown(kpi_card("Customers", f"{seg_count:,}",
                           fmt_pct(seg_pct) + " of base"), unsafe_allow_html=True)
    col2.markdown(kpi_card("Avg Recency", f"{seg_summary['avg_recency']:.0f} days"),
                  unsafe_allow_html=True)
    col3.markdown(kpi_card("Avg Frequency", f"{seg_summary['avg_frequency']:.1f}",
                           "orders in period"), unsafe_allow_html=True)
    col4.markdown(kpi_card("Avg Spend / Order", fmt_gbp(seg_summary["avg_monetary"])),
                  unsafe_allow_html=True)
    col5.markdown(kpi_card("Avg CLV", fmt_gbp(seg_summary["mean_clv"]),
                           "12-month prediction", accent=True), unsafe_allow_html=True)

    action = SEGMENT_ACTIONS.get(selected_seg, "No recommendation available.")
    st.markdown(
        f'<div class="rec-box"><strong>Recommended action ({selected_seg}):</strong> {action}</div>',
        unsafe_allow_html=True,
    )


# ── Page 3: Cohort Retention ──────────────────────────────────────────────────

elif page == "Cohort Retention":
    st.markdown("## Cohort Retention Viewer")
    st.markdown(f'<div style="color:{COLORS["text_muted"]};font-size:13px;margin-bottom:24px">'
                "Monthly cohort retention heatmap — 25 cohorts, Dec 2009–Dec 2011.</div>",
                unsafe_allow_html=True)

    # Weighted global M1 for use in dynamic insight text
    global_m1 = query("""
        SELECT CAST(SUM(n_active) AS REAL) / SUM(cohort_size) AS rate
        FROM cohort_retention WHERE period_number = 1
    """).iloc[0]["rate"]
    global_cliff = 1 - global_m1

    # Segment filter sorted in business-value order
    seg_opts_raw = (
        query("SELECT DISTINCT segment FROM cohort_retention ORDER BY segment")
        ["segment"].tolist()
    )
    seg_opts = sort_segments(seg_opts_raw)

    seg_filter = st.selectbox(
        "Segment filter",
        options=["All Segments"] + seg_opts,
        index=0,
    )

    if seg_filter == "All Segments":
        cohort_df = query("""
            SELECT cohort_month, cohort_label, period_number,
                   SUM(n_active)    AS n_active,
                   SUM(cohort_size) AS cohort_size,
                   CAST(SUM(n_active) AS REAL) / SUM(cohort_size) AS retention_rate
            FROM cohort_retention
            GROUP BY cohort_month, cohort_label, period_number
            ORDER BY cohort_month, period_number
        """)
    else:
        cohort_df = query("""
            SELECT cohort_month, cohort_label, period_number,
                   n_active, cohort_size, retention_rate
            FROM cohort_retention
            WHERE segment = ?
            ORDER BY cohort_month, period_number
        """, params=[seg_filter])

    if cohort_df.empty:
        st.markdown('<div class="alert-box">No data found. Run 07_load_to_sqlite.R to rebuild.</div>',
                    unsafe_allow_html=True)
        st.stop()

    # ── Top 5 worst cohorts — M0→M1 drop ──
    m1_data = cohort_df[cohort_df["period_number"] == 1].copy()
    m1_data["drop"] = 1 - m1_data["retention_rate"]
    worst_5 = m1_data.nlargest(5, "drop")[["cohort_label", "retention_rate", "drop"]]

    st.markdown(f'<div style="font-size:12px;font-weight:600;letter-spacing:.06em;'
                f'text-transform:uppercase;color:{COLORS["text_muted"]};margin-bottom:10px">'
                "Worst 5 Cohorts — M0 → M1 Retention Drop</div>", unsafe_allow_html=True)

    cols = st.columns(5)
    for i, (_, row) in enumerate(worst_5.iterrows()):
        cols[i].markdown(
            kpi_card(
                row["cohort_label"],
                fmt_pct(row["retention_rate"]),
                f"M1 retention · −{row['drop']:.0%} from M0",
            ),
            unsafe_allow_html=True,
        )

    st.markdown("<br>", unsafe_allow_html=True)

    # ── Heatmap ──
    pivot = cohort_df.pivot(
        index="cohort_label", columns="period_number", values="retention_rate"
    )
    cohort_order = (
        cohort_df[["cohort_month", "cohort_label"]]
        .drop_duplicates()
        .sort_values("cohort_month", ascending=False)["cohort_label"]
        .tolist()
    )
    pivot = pivot.reindex(cohort_order)
    # Cast period numbers to int to avoid "M0.0" labels
    pivot.columns = [f"M{int(c)}" for c in pivot.columns]

    text_matrix = pivot.map(lambda v: f"{v:.0%}" if pd.notna(v) else "")

    fig = go.Figure(go.Heatmap(
        z=pivot.values,
        x=pivot.columns.tolist(),
        y=pivot.index.tolist(),
        text=text_matrix.values,
        texttemplate="%{text}",
        textfont=dict(size=10, family=f"{FONT}, sans-serif"),
        colorscale=[
            [0.0,  "#6B1A1A"],
            [0.15, "#C0392B"],
            [0.30, "#E67E22"],
            [0.50, "#F1C40F"],
            [0.70, "#27AE60"],
            [1.0,  "#1A5276"],
        ],
        zmin=0, zmax=1,
        colorbar=dict(
            tickformat=".0%",
            tickfont=dict(color=COLORS["text"], family=f"{FONT}, sans-serif"),
            title=dict(text="Retention", font=dict(color=COLORS["text"])),
        ),
        hoverongaps=False,
        hovertemplate="<b>%{y}</b><br>%{x}: %{z:.1%}<extra></extra>",
    ))

    heatmap_title = (
        f"Monthly Cohort Retention — {seg_filter}"
        if seg_filter != "All Segments"
        else "Monthly Cohort Retention — All Segments"
    )
    fig.update_layout(
        **plot_layout(margin=dict(l=100, r=16, t=48, b=40)),
        title=heatmap_title,
        height=560,
        xaxis=dict(title="Months Since First Purchase",
                   tickfont=dict(color=COLORS["text_muted"]), showgrid=False),
        yaxis=dict(title=None, tickfont=dict(color=COLORS["text"]), showgrid=False),
    )
    st.plotly_chart(fig, use_container_width=True)

    # ── Insights ──
    # Segment-specific insight when a segment is selected
    if seg_filter != "All Segments":
        seg_m1 = (
            m1_data["n_active"].sum() / m1_data["cohort_size"].sum()
            if len(m1_data) > 0 else 0
        )
        seg_best  = m1_data.loc[m1_data["retention_rate"].idxmax(), "cohort_label"]
        seg_worst = m1_data.loc[m1_data["retention_rate"].idxmin(), "cohort_label"]
        vs_global = seg_m1 - global_m1
        direction = f"+{vs_global:.1%} above" if vs_global >= 0 else f"{vs_global:.1%} below"

        st.markdown(f"""
        <div class="insight-box">
          <strong>Segment: {seg_filter}</strong><br><br>
          <strong>M1 Retention:</strong> {seg_m1:.1%} of {seg_filter} customers return in
          month 1 — {direction} the overall average ({global_m1:.1%}).<br>
          <strong>Best cohort:</strong> {seg_best} &nbsp;·&nbsp;
          <strong>Worst cohort:</strong> {seg_worst}
        </div>
        """, unsafe_allow_html=True)

    # Global findings always shown (valuable regardless of segment filter)
    st.markdown(f"""
    <div class="insight-box">
      <strong>Global findings — all cohorts:</strong><br><br>
      <strong>M0→M1 cliff:</strong> On average {global_cliff:.0%} of customers never return
      after their first purchase month (overall M1 retention: {global_m1:.1%}).
      The critical intervention window is within 30 days — post-purchase nurture sequences
      (7-day and 21-day follow-ups) are the highest-ROI retention lever.<br><br>
      <strong>Q4 seasonal bias:</strong> A visible diagonal band of elevated retention (25–35%)
      aligns with Oct–Nov each year across cohorts, driven by Christmas gifting repurchase.
      Some "retained" customers are seasonally reactivated, not continuously engaged —
      campaign planning should distinguish between the two.<br><br>
      <strong>Acquisition quality:</strong> Dec 2010 cohort shows the lowest M1 retention,
      confirming that customers acquired during peak Christmas season are predominantly
      one-time buyers. High-volume Q4 acquisition comes at a retention quality cost.
    </div>
    """, unsafe_allow_html=True)
