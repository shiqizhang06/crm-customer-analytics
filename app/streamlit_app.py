import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import sqlite3
from pathlib import Path

# ── Page config ───────────────────────────────────────────────────────────────

st.set_page_config(
    page_title="CRM Analytics",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Design tokens ──────────────────────────────────────────────────────────────
# Direction: Precision & Density / Data & Analysis
# Base colours also declared in .streamlit/config.toml (Streamlit's theming
# system wins over CSS injection for body/text colour — both layers needed).

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
}

FONT = "Space Grotesk"

SEGMENT_ORDER = [
    "Champions", "Loyal Customers", "Potential Loyalists", "Promising",
    "New Customers", "At Risk", "Can't Lose Them", "Hibernating", "Lost",
]

# ── CSS injection ──────────────────────────────────────────────────────────────

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
    font-size: 15px !important;
  }}
  .stApp, [data-testid="stAppViewContainer"],
  [data-testid="stMain"], [data-testid="stVerticalBlock"] {{
    background-color: {COLORS["bg"]} !important;
  }}
  p, li, span, div {{ color: {COLORS["text"]} !important; }}

  /* ── Sidebar — remove Streamlit's secondary-bg square behind widgets ── */
  [data-testid="stSidebar"] {{
    background-color: {COLORS["surface"]} !important;
    border-right: 1px solid {COLORS["border"]};
  }}
  [data-testid="stSidebar"] > div,
  [data-testid="stSidebar"] section,
  [data-testid="stSidebar"] .stElementContainer,
  [data-testid="stSidebar"] [data-testid="stElementContainer"],
  [data-testid="stSidebar"] [data-testid="stVerticalBlock"],
  [data-testid="stSidebar"] [data-testid="stRadio"] > div {{
    background: transparent !important;
    background-color: transparent !important;
    border: none !important;
    box-shadow: none !important;
  }}
  [data-testid="stSidebar"] .stRadio [aria-checked="true"] + div {{
    color: {COLORS["accent"]} !important;
    font-weight: 600 !important;
  }}

  /* ── Page content — remove secondary-bg box behind headings ── */
  [data-testid="stMain"] .stElementContainer,
  [data-testid="stMain"] [data-testid="stElementContainer"] {{
    background: transparent !important;
  }}
  h1, h2, h3, h4 {{
    color: {COLORS["text"]} !important;
    background: transparent !important;
  }}
  h1 {{ font-weight: 700; font-size: 1.7rem; }}
  h2 {{ font-weight: 600; font-size: 1.3rem; }}
  h3 {{ color: {COLORS["text_muted"]} !important; font-weight: 500; font-size: 1.05rem; }}

  /* ── KPI cards ── */
  .kpi-card {{
    background: {COLORS["surface"]};
    border: 1px solid {COLORS["border"]};
    border-radius: 8px;
    padding: 20px 24px;
    min-height: 96px;
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
    font-size: 12px !important;
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
    font-size: 13px;
    color: {COLORS["text_muted"]} !important;
    margin-top: 6px;
  }}
  .kpi-accent::before {{ background: {COLORS["accent"]}; }}

  .seg-badge {{
    display: inline-block;
    background: {COLORS["surface_2"]};
    border: 1px solid {COLORS["primary"]};
    border-radius: 20px;
    padding: 5px 16px;
    font-size: 14px;
    font-weight: 600;
    color: {COLORS["primary"]} !important;
    letter-spacing: 0.03em;
  }}

  .rfm-row {{
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 12px;
  }}
  .rfm-label {{
    width: 24px;
    font-size: 13px;
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
    font-size: 14px;
    font-weight: 700;
    color: {COLORS["text"]} !important;
    text-align: right;
  }}

  /* ── Action / insight boxes ── */
  .rec-box {{
    background: {COLORS["surface"]};
    border: 1px solid {COLORS["border"]};
    border-left: 3px solid {COLORS["accent"]};
    border-radius: 0 8px 8px 0;
    padding: 16px 20px;
    margin-top: 20px;
  }}
  .rec-box .rec-label {{
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: {COLORS["accent"]} !important;
    margin-bottom: 10px;
  }}
  .rec-box .rec-body {{
    font-size: 15px;
    color: {COLORS["text"]} !important;
    line-height: 1.7;
  }}
  .rec-box strong {{ color: {COLORS["accent"]} !important; }}

  .insight-box {{
    background: {COLORS["surface"]};
    border: 1px solid {COLORS["border"]};
    border-left: 3px solid {COLORS["primary"]};
    border-radius: 0 8px 8px 0;
    padding: 16px 20px;
    margin-bottom: 12px;
    font-size: 15px;
    color: {COLORS["text"]} !important;
    line-height: 1.7;
  }}
  .insight-box strong {{ color: {COLORS["text"]} !important; }}

  .alert-box {{
    background: rgba(248,113,113,0.08);
    border: 1px solid {COLORS["danger"]};
    border-radius: 8px;
    padding: 16px 20px;
    font-size: 15px;
    color: {COLORS["danger"]} !important;
  }}

  /* ── Selectbox — blue border signals interactivity, amber on hover ── */
  [data-testid="stSelectbox"] label {{
    color: {COLORS["text_muted"]} !important;
    font-size: 12px !important;
    font-weight: 700 !important;
    letter-spacing: 0.07em !important;
    text-transform: uppercase !important;
  }}
  [data-testid="stSelectbox"] > div > div {{
    background-color: {COLORS["surface_2"]} !important;
    border: 1px solid {COLORS["primary"]} !important;
    border-radius: 6px !important;
    color: {COLORS["text"]} !important;
    font-size: 15px !important;
    font-weight: 500 !important;
  }}
  [data-testid="stSelectbox"] > div > div:hover {{
    border-color: {COLORS["accent"]} !important;
  }}
  [data-testid="stSelectbox"] svg {{ fill: {COLORS["primary"]} !important; }}

  /* ── Dropdown popup options ── */
  [data-baseweb="popover"],
  [data-baseweb="popover"] ul,
  [data-baseweb="popover"] [data-baseweb="menu"] {{
    background-color: {COLORS["surface_2"]} !important;
  }}
  [data-baseweb="popover"] li,
  [data-baseweb="popover"] [role="option"] {{
    color: {COLORS["text"]} !important;
    background-color: transparent !important;
    font-size: 15px !important;
  }}
  [data-baseweb="popover"] li:hover,
  [data-baseweb="popover"] [role="option"]:hover,
  [data-baseweb="popover"] [aria-selected="true"] {{
    background-color: {COLORS["primary"]} !important;
    color: white !important;
  }}

  hr {{ border-color: {COLORS["border"]}; margin: 24px 0; }}
  #MainMenu, footer, header {{ visibility: hidden; }}
  .block-container {{ padding-top: 2rem; }}
"""

st.markdown(f"<style>{_CSS}</style>", unsafe_allow_html=True)

# ── Plotly base theme ──────────────────────────────────────────────────────────

PLOTLY_BASE = dict(
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    font=dict(family=f"{FONT}, sans-serif", color=COLORS["text"], size=13),
    hoverlabel=dict(
        bgcolor=COLORS["surface_2"],
        bordercolor=COLORS["border"],
        font=dict(family=f"{FONT}, sans-serif", color=COLORS["text"], size=13),
    ),
)

_DEFAULT_MARGIN = dict(l=16, r=16, t=44, b=16)

def plot_layout(**overrides):
    return {**PLOTLY_BASE, "margin": _DEFAULT_MARGIN, **overrides}

def chart_title(text):
    """Explicit title dict — avoids magic-underscore colour loss."""
    return dict(text=text, font=dict(color=COLORS["text"], size=15,
                                     family=f"{FONT}, sans-serif"))

# ── Database ───────────────────────────────────────────────────────────────────

DB_PATH = Path(__file__).parent.parent / "data" / "processed" / "crm.db"

SEGMENT_ACTIONS = {
    "Champions": (
        "VIP retention priority. This segment (646 customers) drives 51% of predicted "
        "12-month revenue — losing even a small fraction has material impact. "
        "Exclusive VIP perks, referral programme, early product access. "
        "The top CLV decile captures 58% of holdout revenue; protect it at all costs."
    ),
    "Loyal Customers": (
        "Deepen engagement to protect frequency and spend. Strong P(alive) of 90.6% means "
        "they're active — the goal is preventing migration into At Risk. "
        "Loyalty rewards, cross-sell adjacent categories, "
        "tier-upgrade messaging toward Champions."
    ),
    "Potential Loyalists": (
        "Highest conversion efficiency. P(alive) of 93% and growing spend signal these "
        "customers are on an upward trajectory. "
        "Introduce loyalty programme post-2nd purchase, "
        "targeted follow-up to accelerate to Loyal tier."
    ),
    "Promising": (
        "Early-stage, high-engagement customers. P(alive) 92.8% but low frequency. "
        "Post-purchase nurture sequence (7-day, 21-day follow-ups) "
        "to overcome the M1 retention cliff — 77% of first-time buyers never return. "
        "Push toward second purchase before month 1 ends."
    ),
    "New Customers": (
        "Critical intervention window: the first 30 days. AOV of £539 is strong but 77% "
        "of first-time buyers never return. "
        "7-day and 21-day post-purchase nurture, welcome series, "
        "introduce product discovery to drive a second order."
    ),
    "At Risk": (
        "Largest segment by count (1,071 customers) but modest avg CLV of £438. "
        "Win-back ROI must be evaluated carefully. "
        "Personalised re-engagement offer; benchmark campaign cost "
        "against the £438 CLV ceiling. Prioritise the higher-CLV customers within this segment."
    ),
    "Can't Lose Them": (
        "Most urgent retention priority. Avg CLV of £1,038 is comparable to Loyal Customers, "
        "but P(alive) has dropped to 71.8% — the lowest among active segments. "
        "Immediate win-back outreach, premium incentive, "
        "direct account manager contact for top spenders within this group."
    ),
    "Hibernating": (
        "Previously high-value buyers (AOV £547, nearly matching Champions at £557). "
        "Standard campaign ROI is low, but seasonal reactivation is worth attempting. "
        "Suppress from regular campaigns; include in Q4 "
        "Christmas blasts only. A targeted seasonal offer may reactivate a portion."
    ),
    "Lost": (
        "Cost of reactivation likely exceeds expected CLV for most customers in this group. "
        "Suppress from active campaigns. Include in annual "
        "deep-discount win-back only; do not invest recurring budget here."
    ),
}

def get_conn():
    if not DB_PATH.exists():
        st.markdown(f'<div class="alert-box"><strong>Database not found</strong> at '
                    f'<code>{DB_PATH}</code><br>Run '
                    f'<code>Rscript scripts/07_load_to_sqlite.R</code></div>',
                    unsafe_allow_html=True)
        st.stop()
    return sqlite3.connect(DB_PATH, check_same_thread=False)

@st.cache_data(ttl=300)
def query(sql, params=None):
    with get_conn() as conn:
        return pd.read_sql_query(sql, conn, params=params or [])

def sort_segments(seg_list):
    order = {s: i for i, s in enumerate(SEGMENT_ORDER)}
    return sorted(seg_list, key=lambda s: order.get(s, 99))

def kpi_card(label, value, sub=None, accent=False):
    cls = "kpi-card kpi-accent" if accent else "kpi-card"
    sub_html = f'<div class="kpi-sub">{sub}</div>' if sub else ""
    return (f'<div class="{cls}">'
            f'<div class="kpi-label">{label}</div>'
            f'<div class="kpi-value">{value}</div>'
            f'{sub_html}</div>')

def rfm_bar(label, score):
    pct = score / 5 * 100
    return (f'<div class="rfm-row">'
            f'<div class="rfm-label">{label}</div>'
            f'<div class="rfm-track"><div class="rfm-fill" style="width:{pct}%"></div></div>'
            f'<div class="rfm-score">{score}</div></div>')

def rec_box(segment, action):
    return (f'<div class="rec-box">'
            f'<div class="rec-label">Recommended action — {segment}</div>'
            f'<p class="rec-body">{action}</p>'
            f'</div>')

def fmt_gbp(v):
    return "N/A" if pd.isna(v) else f"£{v:,.0f}"

def fmt_pct(v):
    return "N/A" if pd.isna(v) else f"{v:.1%}"

def clv_decile_label(n):
    """ntile 1=lowest CLV, 10=highest. ntile 10 → Top 10%, ntile 1 → Bottom 10%."""
    top = (11 - int(n)) * 10
    return f"Top {top}%" if top <= 50 else f"Bottom {int(n) * 10}%"

def section_label(text):
    return (f'<div style="font-size:12px;font-weight:700;letter-spacing:.07em;'
            f'text-transform:uppercase;color:{COLORS["text_muted"]};margin-bottom:14px">'
            f'{text}</div>')

# ── Sidebar ────────────────────────────────────────────────────────────────────

with st.sidebar:
    st.markdown(f'<div style="padding:8px 0 24px">'
                f'<div style="font-size:19px;font-weight:700;color:{COLORS["text"]}">CRM Analytics</div>'
                f'<div style="font-size:12px;color:{COLORS["text_muted"]};margin-top:4px">'
                f'UCI Online Retail II · UK Customers</div></div>',
                unsafe_allow_html=True)

    page = st.radio(
        "Navigation",
        ["Customer Lookup", "Segment Explorer", "Cohort Retention"],
        label_visibility="collapsed",
    )

    st.markdown("<hr>", unsafe_allow_html=True)
    st.markdown(f'<div style="font-size:13px;color:{COLORS["text_muted"]};line-height:1.8">'
                f'5,350 UK customers<br>Dec 2009 – Dec 2011<br>BG/NBD + Gamma-Gamma CLV</div>',
                unsafe_allow_html=True)

# ── Page 1: Customer Lookup ────────────────────────────────────────────────────

if page == "Customer Lookup":
    st.markdown("## Customer Lookup")
    st.markdown(f'<div style="color:{COLORS["text_muted"]};font-size:14px;margin-bottom:24px">'
                "Individual customer profile — RFM scores, predicted CLV, and purchase history.</div>",
                unsafe_allow_html=True)

    customer_ids = (
        query("SELECT customer_id FROM customer_master ORDER BY customer_id")
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
        st.markdown(f'<div style="font-size:13px;color:{COLORS["text_muted"]};margin-bottom:6px">Customer ID</div>'
                    f'<div style="font-size:30px;font-weight:700;color:{COLORS["text"]}">{int(c["customer_id"])}</div>',
                    unsafe_allow_html=True)
    with col_seg:
        st.markdown(f'<div style="font-size:13px;color:{COLORS["text_muted"]};margin-bottom:6px">Segment</div>'
                    f'<div class="seg-badge">{segment}</div>',
                    unsafe_allow_html=True)

    st.markdown("<hr>", unsafe_allow_html=True)

    # CLV decile: R ntile assigns 1=lowest, 10=highest CLV
    decile_lbl = clv_decile_label(c["clv_decile"]) if pd.notna(c["clv_decile"]) else "N/A"

    # P(alive): BG/NBD gives 1.0 to customers with 0 repeat transactions — model
    # cannot distinguish "alive but silent" from churned without repeat evidence.
    if pd.isna(c["p_alive"]):
        palive, palive_sub = "N/A", "No CLV model data"
    elif pd.notna(c["cal_frequency"]) and int(c["cal_frequency"]) == 0:
        palive, palive_sub = "—", "Single transaction — model n/a"
    else:
        palive, palive_sub = fmt_pct(c["p_alive"]), "Probability still active"

    col1, col2, col3, col4 = st.columns(4)
    col1.markdown(kpi_card("Total Revenue", fmt_gbp(c["total_revenue"]),
                           f"{int(c['total_orders'])} orders"), unsafe_allow_html=True)
    # Amber accent strip = the primary metric on this page
    col2.markdown(kpi_card("Predicted 12M CLV", fmt_gbp(c["clv_12m"]),
                           "12-month BG/NBD model", accent=True), unsafe_allow_html=True)
    col3.markdown(kpi_card("CLV Decile", decile_lbl, "10 = highest CLV"), unsafe_allow_html=True)
    col4.markdown(kpi_card("P(Alive)", palive, palive_sub), unsafe_allow_html=True)

    st.markdown("<br>", unsafe_allow_html=True)

    col_rfm, col_chart = st.columns([1, 2])

    with col_rfm:
        st.markdown(section_label("RFM Scores"), unsafe_allow_html=True)
        st.markdown(
            rfm_bar("R", int(c["r_score"])) +
            rfm_bar("F", int(c["f_score"])) +
            rfm_bar("M", int(c["m_score"])),
            unsafe_allow_html=True,
        )
        st.markdown(
            f'<div style="margin-top:18px;font-size:14px;color:{COLORS["text_muted"]};line-height:2">'
            f'First purchase: <strong style="color:{COLORS["text"]}">{c["first_purchase_date"]}</strong><br>'
            f'Last purchase: <strong style="color:{COLORS["text"]}">{c["last_purchase_date"]}</strong><br>'
            f'Recency: <strong style="color:{COLORS["text"]}">{int(c["recency"])} days</strong></div>',
            unsafe_allow_html=True,
        )

    with col_chart:
        # invoice_date is now stored as text "YYYY-MM-DD" in SQLite
        history = query("""
            SELECT strftime('%Y-%m', invoice_date) AS month,
                   SUM(total_amount)               AS revenue
            FROM retail_clean
            WHERE CAST(customer_id AS INTEGER) = ?
            GROUP BY month ORDER BY month
        """, params=[int(selected_id)])

        if not history.empty:
            fig = go.Figure(go.Bar(
                x=history["month"], y=history["revenue"],
                marker_color=COLORS["primary"],
                hovertemplate="%{x}: £%{y:,.0f}<extra></extra>",
            ))
            fig.update_layout(
                **plot_layout(),
                title=chart_title("Monthly Purchase Revenue"),
                # type="category" prevents Plotly interpolating month strings
                # as timestamps (fixes "23:59:59" ticks on sparse data)
                xaxis=dict(showgrid=False, title=None, type="category",
                           tickfont=dict(color=COLORS["text_muted"], size=12)),
                yaxis=dict(showgrid=True, gridcolor=COLORS["border"],
                           title="Revenue (£)", tickprefix="£",
                           tickfont=dict(color=COLORS["text_muted"])),
            )
            st.plotly_chart(fig, use_container_width=True)

    st.markdown(rec_box(segment, SEGMENT_ACTIONS.get(
        segment, "No recommendation available.")), unsafe_allow_html=True)


# ── Page 2: Segment Explorer ───────────────────────────────────────────────────

elif page == "Segment Explorer":

    totals = query("""
        SELECT COUNT(*)           AS total_customers,
               SUM(total_revenue)   AS total_revenue,
               AVG(clv_12m)         AS avg_clv
        FROM customer_master
    """).iloc[0]

    m1_rate = query("""
        SELECT CAST(SUM(n_active) AS REAL) / SUM(cohort_size) AS avg_m1
        FROM (
            SELECT cohort_month, SUM(n_active) AS n_active, SUM(cohort_size) AS cohort_size
            FROM cohort_retention WHERE period_number = 1 GROUP BY cohort_month
        )
    """).iloc[0]["avg_m1"]

    st.markdown("## Segment Explorer")
    st.markdown(f'<div style="color:{COLORS["text_muted"]};font-size:14px;margin-bottom:24px">'
                "Select a segment to deep-dive, then scroll for cross-segment comparisons.</div>",
                unsafe_allow_html=True)

    # ── Global KPIs ──
    col1, col2, col3, col4 = st.columns(4)
    col1.markdown(kpi_card("Total Customers", f"{int(totals['total_customers']):,}",
                           "UK registered"), unsafe_allow_html=True)
    col2.markdown(kpi_card("Total Revenue", fmt_gbp(totals["total_revenue"]),
                           "Dec 2009 – Dec 2011"), unsafe_allow_html=True)
    col3.markdown(kpi_card("Avg Predicted CLV", fmt_gbp(totals["avg_clv"]),
                           "12-month BG/NBD model", accent=True), unsafe_allow_html=True)
    col4.markdown(kpi_card("Avg M1 Retention", fmt_pct(m1_rate),
                           "Weighted across all cohorts"), unsafe_allow_html=True)

    st.markdown("<hr>", unsafe_allow_html=True)

    # ── Segment selector ──
    available_segs = query("SELECT DISTINCT segment FROM customer_master")["segment"].tolist()
    selected_seg   = st.selectbox("Segment", options=sort_segments(available_segs), index=0)

    # ── Segment deep-dive (immediately below selector) ──
    seg_summary = query("SELECT * FROM segment_summary WHERE segment = ?",
                        params=[selected_seg]).iloc[0]
    seg_count   = int(query("SELECT COUNT(*) AS n FROM customer_master WHERE segment = ?",
                            params=[selected_seg]).iloc[0]["n"])
    seg_pct     = seg_count / int(totals["total_customers"])

    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(section_label(f"Deep-dive — {selected_seg}"), unsafe_allow_html=True)

    col1, col2, col3, col4, col5 = st.columns(5)
    col1.markdown(kpi_card("Customers", f"{seg_count:,}",
                           fmt_pct(seg_pct) + " of base"), unsafe_allow_html=True)
    col2.markdown(kpi_card("Avg Recency", f"{seg_summary['avg_recency']:.0f} days",
                           "since last purchase"), unsafe_allow_html=True)
    col3.markdown(kpi_card("Avg Frequency", f"{seg_summary['avg_frequency']:.1f}",
                           "orders in dataset period"), unsafe_allow_html=True)
    col4.markdown(kpi_card("Avg Spend / Order", fmt_gbp(seg_summary["avg_monetary"]),
                           "avg transaction value"), unsafe_allow_html=True)
    col5.markdown(kpi_card("Avg CLV", fmt_gbp(seg_summary["mean_clv"]),
                           "12-month prediction", accent=True), unsafe_allow_html=True)

    # ── All-segments comparison ──
    st.markdown("<hr>", unsafe_allow_html=True)
    st.markdown(section_label("All Segments — Comparison"), unsafe_allow_html=True)

    all_seg = query("SELECT * FROM segment_summary")

    col_left, col_right = st.columns(2)

    with col_left:
        df_bar = all_seg.sort_values("n_customers")
        fig_bar = go.Figure(go.Bar(
            x=df_bar["n_customers"], y=df_bar["segment"], orientation="h",
            marker_color=[COLORS["accent"] if s == selected_seg else COLORS["primary"]
                          for s in df_bar["segment"]],
            hovertemplate="%{y}: %{x:,} customers<extra></extra>",
        ))
        fig_bar.update_layout(
            **plot_layout(), title=chart_title("Customers by Segment"),
            xaxis=dict(showgrid=True, gridcolor=COLORS["border"],
                       title="Customers", tickfont=dict(color=COLORS["text_muted"])),
            yaxis=dict(showgrid=False, title=None, tickfont=dict(color=COLORS["text"])),
            showlegend=False,
        )
        st.plotly_chart(fig_bar, use_container_width=True)

    with col_right:
        df_clv = all_seg.sort_values("mean_clv")
        fig_clv = go.Figure(go.Bar(
            x=df_clv["mean_clv"], y=df_clv["segment"], orientation="h",
            marker_color=[COLORS["accent"] if s == selected_seg else COLORS["primary"]
                          for s in df_clv["segment"]],
            hovertemplate="%{y}: £%{x:,.0f}<extra></extra>",
        ))
        fig_clv.update_layout(
            **plot_layout(), title=chart_title("Avg Predicted CLV by Segment"),
            xaxis=dict(showgrid=True, gridcolor=COLORS["border"],
                       title="Avg 12M CLV (£)", tickprefix="£",
                       tickfont=dict(color=COLORS["text_muted"])),
            yaxis=dict(showgrid=False, title=None, tickfont=dict(color=COLORS["text"])),
            showlegend=False,
        )
        st.plotly_chart(fig_clv, use_container_width=True)

    # Revenue treemap — colour by mean CLV (continuous scale), independent of segment selector
    all_seg["total_revenue_est"] = all_seg["avg_monetary"] * all_seg["n_customers"]
    fig_tree = go.Figure(go.Treemap(
        labels=all_seg["segment"],
        parents=[""] * len(all_seg),
        values=all_seg["total_revenue_est"],
        customdata=all_seg[["mean_clv", "n_customers"]],
        hovertemplate="<b>%{label}</b><br>Est. revenue: £%{value:,.0f}<br>"
                      "Avg CLV: £%{customdata[0]:,.0f}<br>"
                      "Customers: %{customdata[1]:,}<extra></extra>",
        marker=dict(
            colors=all_seg["mean_clv"],
            colorscale=[
                [0,   COLORS["surface_2"]],
                [0.5, COLORS["primary"]],
                [1,   COLORS["accent"]],
            ],
            colorbar=dict(
                title=dict(text="Avg CLV (£)", font=dict(color=COLORS["text"])),
                tickprefix="£",
                tickfont=dict(color=COLORS["text"]),
            ),
        ),
        textfont=dict(family=f"{FONT}, sans-serif", color="white", size=13),
    ))
    fig_tree.update_layout(
        **plot_layout(),
        title=chart_title("Revenue Share by Segment — Average Monetary × Customers"),
    )
    st.plotly_chart(fig_tree, use_container_width=True)

    st.markdown(rec_box(selected_seg, SEGMENT_ACTIONS.get(
        selected_seg, "No recommendation available.")), unsafe_allow_html=True)


# ── Page 3: Cohort Retention ───────────────────────────────────────────────────

elif page == "Cohort Retention":
    st.markdown("## Cohort Retention Viewer")
    st.markdown(f'<div style="color:{COLORS["text_muted"]};font-size:14px;margin-bottom:24px">'
                "Monthly cohort retention heatmap — 25 cohorts, Dec 2009–Dec 2011.</div>",
                unsafe_allow_html=True)

    global_m1 = query("""
        SELECT CAST(SUM(n_active) AS REAL) / SUM(cohort_size) AS rate
        FROM cohort_retention WHERE period_number = 1
    """).iloc[0]["rate"]
    global_cliff = 1 - global_m1

    seg_opts = sort_segments(
        query("SELECT DISTINCT segment FROM cohort_retention")["segment"].tolist()
    )
    seg_filter = st.selectbox("Segment filter",
                              options=["All Segments"] + seg_opts, index=0)

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
            FROM cohort_retention WHERE segment = ?
            ORDER BY cohort_month, period_number
        """, params=[seg_filter])

    if cohort_df.empty:
        st.markdown('<div class="alert-box">No data. Run 07_load_to_sqlite.R to rebuild.</div>',
                    unsafe_allow_html=True)
        st.stop()

    # ── Worst 5 cohorts ──
    m1_data = cohort_df[cohort_df["period_number"] == 1].copy()
    m1_data["drop"] = 1 - m1_data["retention_rate"]
    worst_5 = m1_data.nlargest(5, "drop")[["cohort_label", "retention_rate", "drop"]]

    st.markdown(section_label("Worst 5 Cohorts — M0→M1 Retention Drop"),
                unsafe_allow_html=True)
    cols = st.columns(5)
    for i, (_, row) in enumerate(worst_5.iterrows()):
        cols[i].markdown(
            kpi_card(row["cohort_label"], fmt_pct(row["retention_rate"]),
                     f"M1 retention · −{row['drop']:.0%} from M0"),
            unsafe_allow_html=True,
        )

    st.markdown("<br>", unsafe_allow_html=True)

    # ── Heatmap ──
    pivot = cohort_df.pivot(
        index="cohort_label", columns="period_number", values="retention_rate"
    )
    cohort_order = (
        cohort_df[["cohort_month", "cohort_label"]].drop_duplicates()
        .sort_values("cohort_month", ascending=False)["cohort_label"].tolist()
    )
    pivot = pivot.reindex(cohort_order)
    pivot.columns = [f"M{int(c)}" for c in pivot.columns]

    text_matrix = pivot.map(lambda v: f"{v:.0%}" if pd.notna(v) else "")

    heatmap_title = (f"Monthly Cohort Retention — {seg_filter}"
                     if seg_filter != "All Segments"
                     else "Monthly Cohort Retention — All Segments")

    fig = go.Figure(go.Heatmap(
        z=pivot.values,
        x=pivot.columns.tolist(),
        y=pivot.index.tolist(),
        text=text_matrix.values,
        texttemplate="%{text}",
        textfont=dict(size=10, family=f"{FONT}, sans-serif"),
        colorscale=[
            [0.0, "#6B1A1A"], [0.15, "#C0392B"], [0.30, "#E67E22"],
            [0.50, "#F1C40F"], [0.70, "#27AE60"], [1.0,  "#1A5276"],
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
    fig.update_layout(
        **plot_layout(margin=dict(l=100, r=16, t=48, b=40)),
        title=chart_title(heatmap_title), height=560,
        xaxis=dict(title="Months Since First Purchase",
                   tickfont=dict(color=COLORS["text_muted"]), showgrid=False),
        yaxis=dict(title=None, tickfont=dict(color=COLORS["text"]), showgrid=False),
    )
    st.plotly_chart(fig, use_container_width=True)

    # ── Insights ──
    if seg_filter != "All Segments":
        seg_m1   = m1_data["n_active"].sum() / m1_data["cohort_size"].sum() if len(m1_data) else 0
        seg_best  = m1_data.loc[m1_data["retention_rate"].idxmax(), "cohort_label"]
        seg_worst = m1_data.loc[m1_data["retention_rate"].idxmin(), "cohort_label"]
        vs = seg_m1 - global_m1
        vs_txt = f"+{vs:.1%} above" if vs >= 0 else f"{abs(vs):.1%} below"
        st.markdown(
            f'<div class="insight-box"><strong>Segment insight — {seg_filter}</strong><br><br>'
            f'<strong>M1 Retention:</strong> {seg_m1:.1%} of {seg_filter} customers return in '
            f'month 1 — {vs_txt} the overall average of {global_m1:.1%}.<br>'
            f'<strong>Best cohort:</strong> {seg_best} &nbsp;·&nbsp; '
            f'<strong>Worst cohort:</strong> {seg_worst}</div>',
            unsafe_allow_html=True,
        )

    st.markdown(
        f'<div class="insight-box"><strong>Global findings — all cohorts</strong><br><br>'
        f'<strong>M0→M1 cliff:</strong> On average <strong>{global_cliff:.0%}</strong> of customers '
        f'never return after their first purchase month (overall M1 retention: {global_m1:.1%}). '
        f'The critical intervention window is within 30 days — 7-day and 21-day post-purchase '
        f'nurture sequences are the highest-ROI retention lever.<br><br>'
        f'<strong>Q4 seasonal bias:</strong> A visible diagonal band of elevated retention (25–35%) '
        f'aligns with Oct–Nov each year across cohorts, driven by Christmas gifting repurchase. '
        f'Some "retained" customers are seasonally reactivated, not continuously engaged.<br><br>'
        f'<strong>Acquisition quality:</strong> Dec 2010 cohort shows the lowest M1 retention, '
        f'confirming that peak-season acquired customers are predominantly one-time buyers.</div>',
        unsafe_allow_html=True,
    )
