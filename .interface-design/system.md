---
name: CRM Analytics Design System
description: Design decisions for the CRM Streamlit analytics app — analytics BI tool direction
type: project
---

## Intent

**Who:** CRM / marketing analyst. Desk or meeting room, planning campaigns or reviewing retention metrics. Business judgment, not technical depth.
**What:** Look up customers pre-campaign, assess segment health, track cohort retention.
**Feel:** Precise, data-forward. Sharp like a BI tool. Numbers are the hero — controls recede.

## Direction: Precision & Density / Data & Analysis

Tight spacing, borders-only depth, high-weight typography for numbers. Chosen because:
- Analytics context requires high information density
- Dark field makes numbers (the payload) advance
- Borders are cleaner than shadows in dark themes — shadows add noise

## Foundation

| Token | Value | Why |
|-------|-------|-----|
| `bg` | `#0A1628` | Deep navy-black — trustworthy, analytical. Navy over pure black adds professional warmth |
| `surface` | `#112240` | One step lighter — card / sidebar elevation |
| `surface_2` | `#1A3560` | Second elevation — active states, badge backgrounds |
| `border` | `#1E3A5F` | Subtle structural separator |
| `primary` | `#3D8EF0` | Interactive + primary data viz. Clear blue reads as "information" |
| `accent` | `#F59E0B` | Amber — deliberate attention signal ("act on this"). Used only on the single most important KPI card per view and recommendation boxes |
| `text` | `#E2E8F0` | Near-white with blue undertone — high contrast, not harsh |
| `text_muted` | `#8B9EC4` | Labels, secondary info — recedes without disappearing |
| `success` | `#34D399` | Positive indicators |
| `danger` | `#F87171` | Error / alert states |

## Typography

**Typeface:** Space Grotesk (Google Fonts, weights 300–700)
**Why:** Tabular-style numerics, strong weight differentiation. KPI values at 700 weight read at a glance; labels at 500 weight recede.

| Use | Size | Weight |
|-----|------|--------|
| Page title (h1) | 1.6rem | 700 |
| Section header (h2) | 1.2rem | 600 |
| Subsection (h3) | 1rem | 500 |
| KPI value | 28px | 700 |
| KPI label | 11px | 600, uppercase, 0.08em tracking |
| Body / sub | 12–13px | 400 |

## Depth Strategy: Borders-only

No box shadows. In dark themes, shadows add visual noise. Borders are the elevation signal.

KPI cards use a **2px top accent strip** (via `::before` pseudo-element) as the single decorative element:
- Blue strip (`#3D8EF0`) = standard card
- Amber strip (`#F59E0B`, `.kpi-accent`) = primary / most important metric

## Spacing Grid

Base: 8px. Rhythm: 8, 16, 24, 32px.

| Context | Value |
|---------|-------|
| Card padding | 20px 24px |
| Section gap | 24px |
| Inline gap | 12px |
| Border radius | 8px (cards), 4px (tracks), 20px (badges) |

## Component Patterns

**KPI Card:** 20px/24px padding, 1px border `#1E3A5F`, 8px radius, 2px top strip, label 11px/700/uppercase, value 28px/700

**Segment Badge:** inline-block, `#1A3560` bg, 1px `#3D8EF0` border, 20px radius, 13px/600

**RFM Bar:** 8px height track, `#1A3560` bg, gradient fill `#3D8EF0 → #F59E0B`, 4px radius

**Recommendation Box:** left 3px `#F59E0B` border, `#112240` bg, 14px/18px padding, strong in amber

**Insight Box:** left 3px `#3D8EF0` border, same construction as rec-box

**Alert Box:** `rgba(248,113,113,0.08)` bg, 1px `#F87171` border

## Plotly Chart Defaults

```python
PLOTLY_BASE = dict(
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    font=dict(family="Space Grotesk, sans-serif", color="#E2E8F0", size=13),
    hoverlabel=dict(bgcolor="#1A3560", bordercolor="#1E3A5F", ...),
)
DEFAULT_MARGIN = dict(l=16, r=16, t=40, b=16)
```

`margin` and `coloraxis_colorbar` are NOT in PLOTLY_BASE to avoid `update_layout()` duplicate-key crashes. Merge via `{**PLOTLY_BASE, "margin": DEFAULT_MARGIN, **overrides}`.

## CSS Injection Pattern

Always inject font `<link>` and `<style>` in **separate** `st.markdown()` calls. Combining them in one call causes CSS to render as visible text in some Streamlit versions.

```python
st.markdown('<link href="..." rel="stylesheet">', unsafe_allow_html=True)
st.markdown(f"<style>{_CSS}</style>", unsafe_allow_html=True)
```
