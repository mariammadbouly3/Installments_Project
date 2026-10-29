import pandas as pd
import plotly.express as px
import streamlit as st

import common as cm

d = cm.data()
o, terms, sectors = d["offers"], d["terms"], d["sectors"]

cm.header("تفاصيل قطاع", "اختاري قطاع وشوفي عروضه، وأرخص جهة تقسيط فيه، والشروط المنشورة للشركات.")

counts = o["sector"].value_counts()
order = sorted(sectors["name_ar"], key=lambda s: -counts.get(s, 0))
sec = st.selectbox("القطاع", order, format_func=lambda s: f"{s} ({counts.get(s, 0)} عرض)")

so = o[o["sector"] == sec]
rated = so[so["has_rate"]]
st_terms = terms[terms["sector"] == sec]

if sec == "دهب وشبكة":
    st.error("تقسيط الدهب والفضة عبر شركات التمويل الاستهلاكي ممنوع من 16 سبتمبر 2026 بقرار من الرقابة المالية، "
             "والبنك المركزي منع البنوك تمول شركات التمويل لشراء الدهب. الشراء كاش مسموح عادي.")

best = (rated.groupby("financier_short")["apr_effective"].mean().sort_values().head(1))
cm.kpis([
    (f"{len(so)}", "عرض منشور"),
    (cm.pct(rated["apr_effective"].mean()) if len(rated) else "—", "متوسط الفايدة السنوية", "cost"),
    (f"{int(rated['is_zero_interest'].sum())}", "عرض 0% فعلًا", "good"),
    (best.index[0] if len(best) else "—", f"أرخص جهة ({cm.pct(best.iloc[0], 1)})" if len(best) else "أرخص جهة"),
], n=4)

if len(rated):
    a, b = st.columns([3, 2])
    with a, st.container(border=True):
        st.markdown("#### عروض القطاع من الأغلى للأرخص")
        r = rated.sort_values("apr_effective")
        fig = px.bar(r, x="apr_effective", y="item", color="financier_short", orientation="h",
                     labels={"apr_effective": "الفايدة السنوية", "item": "", "financier_short": "الجهة"})
        fig.update_xaxes(tickformat=".0%")
        fig.update_yaxes(side="right")
        st.plotly_chart(cm.style_fig(fig, max(320, 26 * len(r) + 80)), use_container_width=True)
    with b, st.container(border=True):
        st.markdown("#### متوسط كل جهة")
        g = (rated.groupby("financier_short", as_index=False)
             .agg(عروض=("offer_id", "count"), apr=("apr_effective", "mean"), extra=("extra_pct", "mean")).sort_values("apr"))
        st.dataframe(pd.DataFrame({"الجهة": g["financier_short"], "عروض": g["عروض"],
                                   "الفايدة السنوية %": g["apr"] * 100, "الزيادة %": g["extra"] * 100}),
                     hide_index=True, use_container_width=True, column_config={
                         "الفايدة السنوية %": st.column_config.NumberColumn(format="%.1f%%"),
                         "الزيادة %": st.column_config.NumberColumn(format="%.1f%%")})
elif len(so):
    st.info("العروض في القطاع ده مفيهاش سعر كاش منشور، فمش ممكن نحسب الفايدة.")
    if sec == "عقارات":
        st.dataframe(pd.DataFrame({"الشقة": so["item"], "سعر الإعلان": so["listed_installment_price"],
                                   "المقدم": so["down_payment"], "شهور": so["months"], "القسط": so["monthly_installment"],
                                   "إجمالي الأقساط": so["total_paid"], "الفرق عن السعر": so["diff_vs_listed_price"],
                                   "المصدر": so["source_url"]}),
                     hide_index=True, use_container_width=True, column_config={
                         **{c: st.column_config.NumberColumn(format="%d") for c in
                            ["سعر الإعلان", "المقدم", "القسط", "إجمالي الأقساط", "الفرق عن السعر"]},
                         "المصدر": st.column_config.LinkColumn(display_text="افتحي")})
        cm.html('<p class="note">في أغلب الإعلانات، سعر الشقة المكتوب = مجموع الأقساط بالظبط، يعني الفايدة مدفونة جوه السعر. اسألي المطور دايمًا عن خصم الكاش.</p>')
else:
    st.info("مفيش عروض بأسعار في القطاع ده لسه. لو شفتي عرض، ضيفيه من صفحة **ضيفي عرض**.")

with st.container(border=True):
    st.markdown("#### الشروط المنشورة للشركات في القطاع ده")
    if st_terms.empty:
        st.markdown("مفيش شروط متسجلة.")
    else:
        st.dataframe(pd.DataFrame({
            "الجهة": st_terms["financier"], "على إيه": st_terms["applies_to"], "المدة": st_terms["duration"],
            "الفايدة": st_terms["interest"], "المقدم": st_terms["down_payment"], "المصاريف": st_terms["admin_fees"],
            "ملاحظات": st_terms["notes"], "التاريخ": st_terms["date_text"], "المصدر": st_terms["source_url"]}),
            hide_index=True, use_container_width=True,
            column_config={"المصدر": st.column_config.LinkColumn(display_text="افتحي")})
