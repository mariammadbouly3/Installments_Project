import pandas as pd
import streamlit as st

import common as cm

cm.header("كل العروض", "كل عرض منشور معاه رابط مصدره. الصفوف المعلّمة سيناريو فيها سعر حقيقي مطبق عليه شروط منشورة في مكان تاني.")

o = cm.data()["offers"]

f1, f2, f3, f4 = st.columns([2, 2, 2, 1])
q = f1.text_input("دوري على منتج أو محل")
sectors = f2.multiselect("القطاع", sorted(o["sector"].unique()))
fins = f3.multiselect("جهة التقسيط", sorted(o["financier_short"].dropna().unique()))
real = f4.checkbox("الحقيقية بس")

v = o
if q:
    v = v[v[["item", "merchant", "financier", "sector"]].fillna("").agg(" ".join, axis=1).str.contains(q, regex=False)]
if sectors:
    v = v[v["sector"].isin(sectors)]
if fins:
    v = v[v["financier_short"].isin(fins)]
if real:
    v = v[~v["is_scenario"]]
v = v.sort_values("apr_effective", ascending=False, na_position="last")

cm.kpis([
    (f"{len(v)}", "عرض في الاختيار ده"),
    (cm.pct(v.loc[v["has_rate"] & ~v["is_zero_interest"], "apr_effective"].mean()), "متوسط الفايدة (اللي فيها تكلفة)", "cost"),
    (f"{int(v['is_zero_interest'].sum())}", "عرض 0% فعلًا", "good"),
    (cm.pct(v["extra_pct"].mean()), "متوسط الزيادة عن الكاش"),
], n=4)

st.dataframe(pd.DataFrame({
    "المنتج": v["item"], "النوع": v["is_scenario"].map({True: "سيناريو", False: "حقيقي"}),
    "القطاع": v["sector"], "المحل": v["merchant"], "الجهة": v["financier_short"],
    "كاش": v["cash_price"].fillna(v["listed_installment_price"]), "مقدم": v["down_payment"], "مصاريف": v["upfront_fees"],
    "شهور": v["months"], "القسط": v["monthly_installment"], "الإجمالي": v["total_paid"],
    "الزيادة %": v["extra_pct"] * 100, "الفايدة السنوية %": v["apr_effective"] * 100,
    "الحكم": v["verdict"], "ملاحظات": v["notes"], "المصدر": v["source_url"]}),
    hide_index=True, use_container_width=True, height=600, column_config={
        c: st.column_config.NumberColumn(format="%d") for c in ["كاش", "مقدم", "مصاريف", "القسط", "الإجمالي"]} | {
        "الزيادة %": st.column_config.NumberColumn(format="%.1f%%"),
        "الفايدة السنوية %": st.column_config.NumberColumn(format="%.1f%%"),
        "المصدر": st.column_config.LinkColumn(display_text="افتحي")})

st.download_button("⬇️ نزّلي الاختيار ده CSV", v.to_csv(index=False).encode("utf-8-sig"),
                   file_name="installment_offers.csv", mime="text/csv")
