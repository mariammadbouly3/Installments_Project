import streamlit as st

import common as cm
import writes

cm.header("ضيفي عرض شفتيه", "شفتي عرض تقسيط في محل أو على موقع؟ اكتبي أرقامه هنا. العرض بيروح للإدارة تراجعه، وبعد الموافقة بيظهر في كل الصفحات وفي Power BI.")

d = cm.data()
sectors = d["sectors"]
fins = sorted(d["financiers"]["short_name"].unique())

with st.form("submit_offer", clear_on_submit=True):
    a, b = st.columns(2)
    sector_id = a.selectbox("القطاع", sectors["sector_id"], format_func=lambda i: sectors.set_index("sector_id").loc[i, "name_ar"])
    item = b.text_input("المنتج", placeholder="مثلًا: ثلاجة شارب 18 قدم")
    merchant = a.text_input("المحل أو الموقع", placeholder="مثلًا: بي تك")
    fin_pick = b.selectbox("جهة التقسيط", fins + ["جهة تانية"])
    fin_other = b.text_input("اسم الجهة (لو اخترتي جهة تانية)")
    c1, c2, c3 = st.columns(3)
    cash = c1.number_input("السعر كاش (جنيه)", min_value=0, step=100, format="%d")
    down = c2.number_input("المقدم (جنيه)", min_value=0, step=100, format="%d")
    fee = c3.number_input("مصاريف إدارية بتتدفع مرة واحدة (جنيه)", min_value=0, step=50, format="%d")
    c4, c5 = st.columns(2)
    months = c4.number_input("عدد الشهور", min_value=1, max_value=120, value=12, step=1)
    monthly = c5.number_input("القسط الشهري (جنيه)", min_value=0, step=50, format="%d")
    url = st.text_input("رابط العرض (لو موجود)")
    who = st.text_input("اسمك (اختياري)")
    sent = st.form_submit_button("ابعتي العرض للمراجعة", type="primary")

if sent:
    financier = fin_other.strip() if fin_pick == "جهة تانية" else fin_pick
    if not item.strip() or not cash or not monthly or (fin_pick == "جهة تانية" and not financier):
        st.error("اكتبي اسم المنتج والسعر كاش والقسط الشهري، واسم الجهة لو اخترتي جهة تانية.")
    elif down + fee >= cash:
        st.error("المقدم والمصاريف لازم يكونوا أقل من السعر كاش.")
    else:
        apr = cm.effective_apr(cash - down - fee, monthly, int(months))
        fid_name = d["financiers"].drop_duplicates("short_name").set_index("short_name")["name"].get(financier, financier)
        oid = writes.add_offer(cm.engine(), {
            "sector_id": sector_id, "item": item, "merchant": merchant, "financier": fid_name,
            "cash_price": cash, "down_payment": down, "upfront_fees": fee, "months": months, "monthly_installment": monthly,
            "source_name": merchant or "إضافة من الموقع", "source_url": url or None, "submitted_by": who or None})
        cm.refresh()
        total = down + fee + monthly * months
        st.success(f"وصل العرض رقم {oid} للإدارة. هتدفعي {total:,.0f} ج بدل {cash:,.0f} ج كاش، "
                   f"يعني زيادة {cm.pct((total - cash) / cash, 1)} وفايدة سنوية فعلية {cm.pct(apr, 1)}.")
        label, cls, msg = cm.verdict(apr, cm.cd_rate())
        cm.html(f'<div class="vd {cls}">{label}<p>{msg}</p></div>')
