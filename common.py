"""Shared pieces for every page: style, database connection, data loading and the interest math."""
from __future__ import annotations

import datetime as dt
import os
import re
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import pandas as pd
import streamlit as st
from sqlalchemy import create_engine, text

HERE = Path(__file__).parent

# ---------------------------------------------------------------- palette (light, same as the website)
BG, SURFACE, SOFT, LINE = "#F5F8F3", "#FFFFFF", "#EAF2EC", "#D9E3DB"
INK, MUTED = "#1D2A23", "#5D6B63"
GREEN, CORAL, GOLD = "#24876A", "#DB5F43", "#C9962A"
GREEN_SOFT, CORAL_SOFT, GOLD_SOFT = "#D3EBE1", "#FBE3DC", "#F7ECCF"
VERDICT_COLORS = {"0% — قسّط": GREEN, "أقل من الشهادة": GOLD, "الكاش أوفر": CORAL, "مش محسوبة": "#AAB5AE"}
FONT, DISPLAY = "IBM Plex Sans Arabic", "Alexandria"

AR_STATUS = {"approved": "منشور", "pending": "في انتظار المراجعة", "rejected": "مرفوض"}
AR_SOURCE = {"seed": "الداتا الأصلية", "web": "من الموقع", "admin": "من الإدارة"}
CAIRO = ZoneInfo("Africa/Cairo")


def now():
    """Cairo time, also on the cloud server (which runs on UTC)."""
    return dt.datetime.now(CAIRO)


def today():
    return now().date()


def egp(x):
    return "—" if x is None or pd.isna(x) else f"{float(x):,.0f} ج"


def short_egp(x):
    x = float(x or 0)
    if x >= 1e6:
        return f"{x / 1e6:,.2f} مليون ج"
    if x >= 1e3:
        return f"{x / 1e3:,.0f} ألف ج"
    return f"{x:,.0f} ج"


def pct(x, d=0):
    return "—" if x is None or pd.isna(x) else f"{float(x) * 100:.{d}f}%"


# ---------------------------------------------------------------- interest math (same as the SQL function)
def effective_apr(pv, pmt, n, annual=0.0, years=0):
    """Effective annual interest of financing `pv` with `n` monthly payments `pmt` (+ optional yearly payments)."""
    if not pv or pv <= 0 or not pmt or not n:
        return None
    if pmt * n + annual * years <= pv + 0.5:
        return 0.0
    lo, hi = 0.0, 1.0
    for _ in range(100):
        r = (lo + hi) / 2
        v = pmt * (1 - (1 + r) ** -n) / r + sum(annual / (1 + r) ** (12 * k) for k in range(1, years + 1))
        lo, hi = (r, hi) if v > pv else (lo, r)
    return (1 + (lo + hi) / 2) ** 12 - 1


def plan_quote(price, plan, fees, months, down_pct):
    """Apply one calculator plan. Returns a dict with every line of the receipt."""
    down = price * down_pct
    financed = price - down
    fee_rate = 0.0
    for up_to, f in sorted(fees):
        if months <= up_to:
            fee_rate = f
            break
    else:
        if fees:
            fee_rate = sorted(fees)[-1][1]
    fee = financed * fee_rate
    monthly = financed * (1 + plan["flat_annual_rate"] * months / 12) / months
    total = down + fee + monthly * months
    apr = effective_apr(financed - fee, monthly, months) or 0.0
    return dict(down=down, fee=fee, fee_rate=fee_rate, monthly=monthly, total=total,
                extra=total - price, extra_pct=(total - price) / price if price else 0, apr=apr)


def verdict(apr, cd):
    if apr is None:
        return "مش محسوبة", "mute", "مفيش سعر كاش نقارن بيه."
    if apr < 0.001:
        return "0% — قسّط", "good", "العرض ده 0% فعلًا. قسّطي وحطي الكاش في شهادة وهتكسبي الفرق."
    if apr < cd:
        return "أقل من الشهادة", "mid", f"الفايدة {pct(apr, 1)} أقل من عائد الشهادة ({pct(cd, 2)})، فالتقسيط مقبول."
    return "الكاش أوفر", "bad", f"الفايدة {pct(apr, 1)} أعلى من عائد الشهادة ({pct(cd, 2)}). لو معاكي الكاش، ادفعي كاش."


# ---------------------------------------------------------------- style
def html(markup: str):
    """Render raw HTML/CSS. Strips comments, indentation and blank lines so Markdown never shows it as text."""
    markup = re.sub(r"/\*.*?\*/", "", markup, flags=re.S)
    st.markdown("\n".join(line.strip() for line in markup.splitlines() if line.strip()), unsafe_allow_html=True)


def inject_style():
    html(f"""
    <link href="https://fonts.googleapis.com/css2?family=Alexandria:wght@500;700;800&family=IBM+Plex+Sans+Arabic:wght@400;500;600&display=swap" rel="stylesheet">
    <style>
    html, body, .stApp, [class*="st-"], button, input, textarea, select {{ font-family: '{FONT}', Tahoma, sans-serif !important; }}
    [data-testid="stIconMaterial"], .material-symbols-rounded, [class*="material-symbols"] {{ font-family: 'Material Symbols Rounded' !important; }}
    .stApp {{ background: {BG}; }}
    h1, h2, h3, h4 {{ font-family: '{DISPLAY}', '{FONT}', sans-serif !important; color: {INK}; }}
    [data-testid="stMain"], [data-testid="stSidebarContent"], [data-testid="stHeader"] {{ direction: rtl; }}
    [data-testid="stHeader"] {{ background: rgba(245,248,243,.85); backdrop-filter: blur(10px); border-bottom: 1px solid {LINE}; }}
    [data-testid="stDecoration"], [data-testid="stStatusWidget"], [data-testid="stMainMenu"], [data-testid="stAppDeployButton"] {{ display: none; }}
    .block-container {{ padding-top: 4.2rem; max-width: 1400px; }}
    h1, h2, h3, h4, p, label, li, .stMarkdown {{ text-align: right; }}
    [data-testid="stSidebar"] > div:first-child {{ background: {SURFACE}; border-left: 1px solid {LINE}; }}
    [data-testid="stSidebarContent"] * {{ direction: rtl; }}
    [data-testid="stTopNavLinkContainer"] a, [data-testid="stSidebarNavLink"] {{ border-radius: 999px; }}
    [data-testid="stTopNavLinkContainer"] a[aria-current="page"] {{ background: {GREEN}; }}
    [data-testid="stTopNavLinkContainer"] a[aria-current="page"] * {{ color: #fff !important; }}
    /* panels */
    [data-testid="stVerticalBlockBorderWrapper"]:has(> div > [data-testid="stVerticalBlock"]) {{
        background: {SURFACE}; border: 1px solid {LINE} !important; border-radius: 18px;
    }}
    [data-testid="stForm"] {{ background: {SURFACE}; border: 1px solid {LINE}; border-radius: 18px; }}
    [data-baseweb="select"] > div, [data-baseweb="input"] > div, .stDateInput input, .stNumberInput input, textarea {{
        background: {BG} !important; border-color: {LINE} !important;
    }}
    [data-testid="stSlider"], [data-testid="stDataFrame"], [data-testid="stDataEditor"], .js-plotly-plot {{ direction: ltr; }}
    [data-baseweb="tag"] {{ background: {GREEN} !important; }}
    .stButton > button, .stDownloadButton > button, [data-testid="stFormSubmitButton"] > button {{ border-radius: 999px; font-weight: 600; }}
    [data-baseweb="tab-list"] {{ gap: .4rem; flex-wrap: wrap; }}
    [data-baseweb="tab"] {{ background: {SOFT}; border-radius: 999px; padding: .45rem 1.1rem; font-weight: 500; }}
    [data-baseweb="tab"][aria-selected="true"] {{ background: {GREEN}; color: #fff; }}
    [data-baseweb="tab-highlight"], [data-baseweb="tab-border"] {{ display: none; }}
    /* header strip */
    .route {{ display:flex; flex-direction:column; gap:.45rem; margin-bottom: 1.1rem; }}
    .route h1 {{ font-size: 2.3rem; font-weight: 800; margin: 0; line-height: 1.2; padding: 0; }}
    .route p {{ color: {MUTED}; margin: 0; font-size: 1rem; max-width: 70ch; }}
    .bars {{ display:flex; gap:.45rem; align-items:center; margin:.1rem 0 .2rem; }}
    .bars span {{ height: 8px; border-radius: 99px; display:block; }}
    .bars i {{ font-style: normal; font-size: .82rem; color: {MUTED}; margin-inline-start:.35rem; }}
    /* KPI cards */
    .kpis {{ display:grid; grid-template-columns: repeat(var(--n,5), minmax(0,1fr)); gap: .8rem; margin: .4rem 0 1rem; }}
    .kpi {{ background: {SURFACE}; border:1px solid {LINE}; border-radius: 16px; padding: .9rem 1.1rem; }}
    .kpi b {{ display:block; font-family:'{DISPLAY}', sans-serif; font-size: 1.5rem; font-weight: 700; color: {INK}; line-height:1.3; }}
    .kpi small {{ color: {MUTED}; font-size: .85rem; }}
    .kpi.cost b {{ color: {CORAL}; }} .kpi.good b {{ color: {GREEN}; }} .kpi.accent {{ border-color: {GOLD}; }}
    .chip {{ display:inline-block; padding:.15rem .7rem; border-radius:99px; font-size:.85rem; margin: 0 0 .3rem .3rem; background: {SOFT}; }}
    .note {{ color:{MUTED}; font-size:.85rem; }}
    .live {{ display:inline-flex; align-items:center; gap:.4rem; color:{MUTED}; font-size:.85rem; }}
    .live::before {{ content:""; width:8px; height:8px; border-radius:50%; background:{GREEN}; box-shadow:0 0 0 4px {GREEN_SOFT}; }}
    /* receipt */
    .receipt {{ background:{SURFACE}; border-radius:4px; padding:22px 24px 28px; border:1px solid {LINE};
                -webkit-mask: radial-gradient(circle 7px at 50% 100%, #0000 98%, #000) 0 0/18px 100%; }}
    .receipt h4 {{ text-align:center; color:{MUTED}; font-weight:500; font-size:1rem; margin:0; }}
    .receipt .big {{ text-align:center; font-family:'{DISPLAY}', sans-serif; font-size:2.4rem; font-weight:800; margin:.2rem 0 0; }}
    .receipt .big small {{ font-size:1rem; color:{MUTED}; font-weight:500; }}
    .receipt hr {{ border:0; border-top:2px dashed {LINE}; margin:14px 0; }}
    .receipt .ln {{ display:flex; justify-content:space-between; gap:10px; padding:3px 0; font-variant-numeric: tabular-nums; }}
    .receipt .ln span:first-child {{ color:{MUTED}; }}
    .receipt .ln.tot {{ font-weight:700; font-size:1.05rem; }}
    .receipt .ln.ex span:last-child {{ color:{CORAL}; font-weight:700; }}
    .vd {{ margin-top:14px; border-radius:12px; padding:12px 14px; font-weight:600; }}
    .vd p {{ margin:4px 0 0; font-weight:400; font-size:.9rem; }}
    .vd.good {{ background:{GREEN_SOFT}; color:#155a46; }} .vd.mid {{ background:{GOLD_SOFT}; color:#7a5a12; }}
    .vd.bad {{ background:{CORAL_SOFT}; color:#9a3420; }} .vd.mute {{ background:{SOFT}; color:{MUTED}; }}
    @media (max-width: 760px) {{
        .block-container {{ padding: 3.6rem .8rem 2rem; }}
        .route h1 {{ font-size: 1.7rem; }}
        .kpis {{ grid-template-columns: repeat(2, minmax(0,1fr)) !important; gap: .55rem; }}
        .kpi b {{ font-size: 1.15rem; }}
    }}
    @media (prefers-reduced-motion: reduce) {{ * {{ transition: none !important; animation: none !important; }} }}
    </style>""")


def header(title: str, subtitle: str = ""):
    html(f"""
    <div class="route">
      <div class="bars">
        <span style="width:90px;background:{GREEN}"></span>
        <span style="width:60px;background:{GOLD}"></span>
        <span style="width:80px;background:{CORAL}"></span>
        <i>التقسيط في السوق المصري · أسعار حقيقية بمصادرها</i>
      </div>
      <h1>{title}</h1>
      {f'<p>{subtitle}</p>' if subtitle else ''}
    </div>""")


def kpis(items, n=None):
    """items: list of (value, label) or (value, label, css_class)."""
    cells = "".join(f'<div class="kpi {it[2] if len(it) > 2 else ""}"><b>{it[0]}</b><small>{it[1]}</small></div>' for it in items)
    html(f'<div class="kpis" style="--n:{n or len(items)}">{cells}</div>')


def receipt(q, price, months):
    label, cls, msg = verdict(q["apr"], cd_rate())
    fee_txt = egp(q["fee"]) + (f" · {pct(q['fee_rate'])}" if q["fee_rate"] else "")
    html(f"""
    <div class="receipt">
      <h4>إيصال التقسيط</h4>
      <div class="big">{q['monthly']:,.0f} <small>ج / شهر</small></div>
      <hr>
      <div class="ln"><span>السعر كاش</span><span>{egp(price)}</span></div>
      <div class="ln"><span>المقدم</span><span>{egp(q['down'])}</span></div>
      <div class="ln"><span>مصاريف إدارية</span><span>{fee_txt}</span></div>
      <div class="ln"><span>الأقساط</span><span>{months} × {q['monthly']:,.0f} ج</span></div>
      <hr>
      <div class="ln tot"><span>إجمالي هتدفعيه</span><span>{egp(q['total'])}</span></div>
      <div class="ln ex"><span>الزيادة عن الكاش</span><span>+{q['extra']:,.0f} ج · {pct(q['extra_pct'], 1)}</span></div>
      <div class="ln"><span>الفايدة السنوية الفعلية</span><span><b>{pct(q['apr'], 1)}</b></span></div>
      <div class="vd {cls}">{label}<p>{msg}</p></div>
    </div>""")


def style_fig(fig, height=None):
    fig.update_layout(
        paper_bgcolor="rgba(0,0,0,0)", plot_bgcolor="rgba(0,0,0,0)",
        font=dict(family=FONT, color=INK, size=13), margin=dict(l=10, r=10, t=40, b=10),
        legend=dict(orientation="h", y=1.1, x=1, xanchor="right", bgcolor="rgba(0,0,0,0)"),
        hoverlabel=dict(font_family=FONT), title=dict(x=1, xanchor="right"),
    )
    if height:
        fig.update_layout(height=height)
    fig.update_xaxes(gridcolor=LINE, zeroline=False)
    fig.update_yaxes(gridcolor=LINE, zeroline=False)
    return fig


# ---------------------------------------------------------------- database
def _secret(name):
    try:
        return st.secrets.get(name)
    except Exception:  # noqa: BLE001  (no secrets.toml on a local run)
        return None


def database_url():
    """Cloud: DATABASE_URL in Streamlit secrets. Local: env var, or the sidebar form."""
    return _secret("DATABASE_URL") or os.getenv("DATABASE_URL") or st.session_state.get("local_url")


def admin_password():
    return _secret("ADMIN_PASSWORD") or os.getenv("ADMIN_PASSWORD")


@st.cache_resource(show_spinner=False)
def get_engine(url: str):
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg2://" + url[len("postgresql://"):]
    eng = create_engine(url, pool_pre_ping=True, pool_recycle=300)
    with eng.connect() as c:
        c.execute(text("SELECT 1"))
    return eng


def local_connect_form():
    """Only shown when no DATABASE_URL is configured (running on the laptop)."""
    with st.sidebar:
        st.markdown("### 🔌 الاتصال بقاعدة البيانات")
        host = st.text_input("الخادم", os.getenv("PGHOST", "localhost"))
        port = st.text_input("المنفذ", os.getenv("PGPORT", "5432"))
        db = st.text_input("قاعدة البيانات", os.getenv("PGDATABASE", "installments_db"))
        user = st.text_input("اسم المستخدم", os.getenv("PGUSER", "postgres"))
        pw = st.text_input("كلمة المرور", os.getenv("PGPASSWORD", ""), type="password")
        if st.button("اتصال", type="primary", use_container_width=True):
            from urllib.parse import quote_plus
            st.session_state["local_url"] = f"postgresql://{quote_plus(user)}:{quote_plus(pw)}@{host}:{port}/{db}"
            st.rerun()


def engine():
    url = database_url()
    return get_engine(url) if url else None


def _floats(df):
    for col in df.columns:
        if df[col].dtype == object and df[col].dropna().map(lambda v: isinstance(v, Decimal)).any():
            df[col] = df[col].astype(float)
    return df


QUERIES = {
    "offers": "SELECT * FROM installments.v_live_offers",
    "all_offers": "SELECT * FROM installments.v_offers ORDER BY created_at DESC, offer_id DESC",
    "sectors": "SELECT * FROM installments.sectors ORDER BY name_ar",
    "financiers": "SELECT * FROM installments.financiers ORDER BY short_name",
    "terms": """SELECT t.*, s.name_ar AS sector FROM installments.plan_terms t
                JOIN installments.sectors s USING (sector_id) ORDER BY s.name_ar""",
    "benchmarks": "SELECT * FROM installments.benchmarks",
    "plans": "SELECT * FROM installments.calc_plans ORDER BY sort_order, plan_id",
    "plan_fees": "SELECT * FROM installments.calc_plan_fees ORDER BY plan_id, up_to_months",
}


@st.cache_data(ttl=60, show_spinner="جاري تحميل البيانات...")
def load_data(_eng, url_key: str):
    with _eng.connect() as c:
        out = {k: _floats(pd.read_sql(text(v), c)) for k, v in QUERIES.items()}
    for k in ("offers", "all_offers"):
        out[k]["created_at"] = pd.to_datetime(out[k]["created_at"], utc=True).dt.tz_convert(CAIRO)
    return out


def data():
    return load_data(engine(), str(hash(database_url())))


def refresh():
    """Call after any write so every page shows the change straight away."""
    load_data.clear()


def bench(code, default):
    b = data()["benchmarks"].set_index("code")["value"]
    return float(b.get(code, default))


def cd_rate():
    return bench("cd_rate", 0.1775)


def inflation():
    return bench("inflation", 0.128)
