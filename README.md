# 💳 حسبة التقسيط · Egypt Installments Analyzer

An Arabic web app on a PostgreSQL database of **137 real installment offers** across 15 sectors of the Egyptian market
(everything except food and water), collected from merchant, bank and consumer-finance websites in October 2026.
It answers one question: **how much extra do you really pay when you buy on installments?**
Every offer's effective annual interest is computed inside the database, so a new or edited offer shows up straight away
on every page and in Power BI.

**Pages**
| Page | What it does |
|---|---|
| لوحة المؤشرات (Dashboard) | Average effective interest, how many offers are truly 0%, interest by sector and by financier against inflation and the bank CD rate. Refreshes every minute. |
| احسبي القسط (Calculator) | Price + plan + months + down payment → a full receipt, effective annual rate and a verdict (installments vs. cash). Compares every plan and shows real offers at the same price. |
| كل العروض (Offers) | Search and filter every published offer, with a link to its source. CSV download. |
| تفاصيل قطاع (Sector) | Offers, cheapest financier and published company terms for one sector. |
| ضيفي عرض (Submit) | Anyone can submit an offer they saw. It is saved as *pending* until an admin approves it. |
| المصادر والمنهجية (Sources) | How the interest is calculated, benchmark figures and every source. |
| الإدارة (Admin) | Password protected: approve/reject submitted offers, add and edit offers, hide offers, edit the calculator plans and the benchmark rates. |

## Stack
PostgreSQL (Neon in the cloud) · Python · pandas · SQLAlchemy · Streamlit · Plotly · Power BI

## Run on your laptop
```bash
pip install -r requirements.txt
streamlit run app.py
```
Or double-click `run_app.bat` on Windows. Without a `DATABASE_URL`, the sidebar asks for the local PostgreSQL password
(database `installments_db`). For the admin page, copy `.streamlit/secrets.toml.example` to `.streamlit/secrets.toml` and set `ADMIN_PASSWORD`.

## Deploy (free)
1. **Database**: create a Neon project, then run `sql/00_cloud_setup.sql` once (in pgAdmin or the Neon SQL editor).
2. **App**: on [share.streamlit.io](https://share.streamlit.io) choose this repo, set `app.py` as the main file, and add these secrets:
   ```toml
   DATABASE_URL = "postgresql://USER:PASSWORD@HOST/neondb?sslmode=require"
   ADMIN_PASSWORD = "choose-a-password"
   ```
3. **Power BI**: Get data → PostgreSQL → server = Neon host (or `localhost`), database = `neondb` (or `installments_db`).
   Load `installments.pbi_offers`, `pbi_sector_summary`, `pbi_financier_summary` and `pbi_benchmarks`, then use **Refresh** to pull new offers.

## Database
`sql/00_cloud_setup.sql` builds schema `installments`: `sectors`, `financiers`, `offers`, `plan_terms`, `benchmarks`,
`calc_plans`, `calc_plan_fees`. The function `effective_apr()` solves the internal rate of return of each offer's cash flows
(bisection, including yearly payments for club memberships). `v_offers` computes total paid, extra over cash and effective APR
for every row; `v_live_offers` keeps only approved, visible offers; `pbi_*` views feed Power BI.
`sql/01_analysis_queries.sql` has 12 business questions (CTEs, window functions, FILTER, CROSS JOIN with benchmarks).

## Main findings
- Furniture on 36 months costs **+54%** over cash (MOGO) — an effective **35%** a year; Aman about **43–46%**.
- "Interest-free" with a 10% admin fee over 6 months is an effective **44%** a year.
- In **71%** of offers, paying cash beats installments + a 17.75% bank CD. Only 28 offers were truly 0%.
- The same Galaxy A56 costs **25% more** cash at one retailer than on Samsung's site with 24 months at 0%.
- Real estate listings show the installment price only; the cash price is hidden.
- Financing gold through consumer-finance companies is banned since 16 September 2026.

## Data notes
- Every offer has its source link. Sites state their figures are approximate.
- *Scenario* rows apply published terms to a real price or to a fixed 10,000 EGP, to compare companies fairly.
- Beauty, solar, weddings and insurance have published terms but no priced offers yet.
- Benchmarks: annual inflation 12.8% (CAPMAS, Sep 2026), NBE 3-year CD 17.75%.

## Repository layout
| Folder | What's inside |
|---|---|
| `/` | The Streamlit app (`app.py`, `common.py`, `writes.py`, `views/`) |
| `sql/` | `00_cloud_setup.sql` (whole database in one file) and `01_analysis_queries.sql` (12 business questions) |
| `analysis/` | The dataset (CSV + Excel with live formulas), the cleaning & EDA notebook, and the scraping script |
| `web/` | A static one-page version of the findings with the calculator (`index.html`) |
