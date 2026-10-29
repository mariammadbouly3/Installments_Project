import pandas as pd
import streamlit as st

import common as cm

cm.header("احسبي القسط الحقيقي", "اكتبي سعر المنتج كاش واختاري نظام التقسيط. الشروط جاية من قاعدة البيانات، والإدارة تقدر تعدلها.")

d = cm.data()
plans = d["plans"][d["plans"]["is_active"]].reset_index(drop=True)
fees = d["plan_fees"]
if plans.empty:
    st.warning("مفيش أنظمة تقسيط مفعّلة. فعّليها من صفحة الإدارة.")
    st.stop()


def fees_of(pid):
    return list(fees.loc[fees["plan_id"] == pid, ["up_to_months", "fee_pct"]].itertuples(index=False, name=None))


PRESETS = {"غرفة نوم": 70000, "موبايل": 24480, "تكييف 1.5 حصان": 28000, "موتوسيكل": 61000, "عمرة 7 أيام": 30000}

left, right = st.columns([1, 1])
with left, st.container(border=True):
    preset = st.radio("منتج جاهز", ["سعر من عندي"] + list(PRESETS), horizontal=True)
    price = st.number_input("سعر المنتج كاش (جنيه)", min_value=500, step=500, format="%d",
                            value=PRESETS.get(preset, 70000), key=f"price_{preset}")
    pid = st.selectbox("نظام التقسيط", plans["plan_id"], format_func=lambda i: plans.set_index("plan_id").loc[i, "name"])
    plan = plans.set_index("plan_id").loc[pid]
    st.caption(plan["note"] or "")
    lo, hi = int(plan["min_months"]), int(plan["max_months"])
    months = st.slider("عدد الشهور", lo, hi, hi) if hi > lo else hi
    if hi == lo:
        st.markdown(f"عدد الشهور: **{hi}**")
    down_pct = st.slider("مقدم (% من السعر)", 0, 50, 0, step=5) / 100

q = cm.plan_quote(float(price), plan, fees_of(pid), int(months), down_pct)
with right:
    cm.receipt(q, float(price), int(months))

# ---- compare every plan for the same price
with st.container(border=True):
    st.markdown("#### نفس السعر على كل الأنظمة")
    rows = []
    for _, p in plans.iterrows():
        for n in sorted({int(p["min_months"]), 12, 24, int(p["max_months"])}):
            if int(p["min_months"]) <= n <= int(p["max_months"]):
                r = cm.plan_quote(float(price), p, fees_of(p["plan_id"]), n, down_pct)
                rows.append({"النظام": p["name"], "شهور": n, "القسط": r["monthly"], "الإجمالي": r["total"],
                             "الزيادة %": r["extra_pct"] * 100, "الفايدة السنوية %": r["apr"] * 100,
                             "الحكم": cm.verdict(r["apr"], cm.cd_rate())[0]})
    cmp = pd.DataFrame(rows).sort_values("الفايدة السنوية %")
    st.dataframe(cmp, hide_index=True, use_container_width=True, column_config={
        "القسط": st.column_config.NumberColumn(format="%d"), "الإجمالي": st.column_config.NumberColumn(format="%d"),
        "الزيادة %": st.column_config.NumberColumn(format="%.1f%%"),
        "الفايدة السنوية %": st.column_config.NumberColumn(format="%.1f%%")})

# ---- real offers near this price
with st.container(border=True):
    st.markdown("#### عروض حقيقية في نفس الرينج")
    o = d["offers"]
    near = o[o["cash_price"].between(price * 0.6, price * 1.4) & o["has_rate"] & ~o["is_scenario"]]
    near = near.assign(gap=(near["cash_price"] - price).abs()).sort_values(["gap", "apr_effective"]).head(10)
    if near.empty:
        st.markdown("مفيش عروض حقيقية قريبة من السعر ده.")
    else:
        st.dataframe(pd.DataFrame({
            "المنتج": near["item"], "المحل": near["merchant"], "الجهة": near["financier_short"],
            "كاش": near["cash_price"], "شهور": near["months"], "القسط": near["monthly_installment"],
            "الفايدة السنوية %": near["apr_effective"] * 100, "المصدر": near["source_url"]}),
            hide_index=True, use_container_width=True, column_config={
                "كاش": st.column_config.NumberColumn(format="%d"), "القسط": st.column_config.NumberColumn(format="%d"),
                "الفايدة السنوية %": st.column_config.NumberColumn(format="%.1f%%"),
                "المصدر": st.column_config.LinkColumn(display_text="افتحي")})
