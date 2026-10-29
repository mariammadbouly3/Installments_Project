import hmac

import pandas as pd
import streamlit as st

import common as cm
import writes

cm.header("الإدارة", "راجعي العروض اللي جت من الموقع، وضيفي وعدّلي العروض، وغيّري شروط الحاسبة وأرقام المقارنة. أي تغيير بيظهر على طول في كل الصفحات وفي Power BI.")

# ---------------------------------------------------------------- password gate
expected = cm.admin_password()
if not expected:
    st.warning("صفحة الإدارة مقفولة لحد ما تحددي كلمة مرور لها. ضيفي ADMIN_PASSWORD في الـ Secrets بتاعة التطبيق "
               "(أو في ملف .streamlit/secrets.toml لو شغالة على اللاب).")
    st.stop()

if not st.session_state.get("is_admin"):
    with st.form("login"):
        pw = st.text_input("كلمة مرور الإدارة", type="password")
        if st.form_submit_button("دخول", type="primary"):
            if hmac.compare_digest(pw, expected):
                st.session_state["is_admin"] = True
                st.rerun()
            else:
                st.error("كلمة المرور غلط.")
    st.stop()

if st.button("خروج"):
    st.session_state["is_admin"] = False
    st.rerun()

eng = cm.engine()
d = cm.data()
allo, sectors = d["all_offers"], d["sectors"]


def offer_table(df):
    return pd.DataFrame({
        "اختيار": False, "رقم": df["offer_id"], "المنتج": df["item"], "القطاع": df["sector"], "المحل": df["merchant"],
        "الجهة": df["financier_short"], "كاش": df["cash_price"], "شهور": df["months"], "القسط": df["monthly_installment"],
        "الفايدة %": df["apr_effective"] * 100, "الحالة": df["status"].map(cm.AR_STATUS), "من": df["entry_source"].map(cm.AR_SOURCE),
        "بعتها": df["submitted_by"], "الرابط": df["source_url"]})


CFG = {"كاش": st.column_config.NumberColumn(format="%d"), "القسط": st.column_config.NumberColumn(format="%d"),
       "الفايدة %": st.column_config.NumberColumn(format="%.1f%%"), "الرابط": st.column_config.LinkColumn(display_text="افتحي")}

t_review, t_all, t_new, t_plans = st.tabs(["📥 عروض للمراجعة", "📚 كل العروض", "➕ عرض جديد", "🧮 الحاسبة والمقارنة"])

# ---------------------------------------------------------------- review web submissions
with t_review:
    pend = allo[allo["status"] == "pending"]
    if pend.empty:
        st.success("مفيش عروض مستنية مراجعة.")
    else:
        st.markdown(f"**{len(pend)}** عرض جه من الموقع. علّمي على اللي عايزة تنشريه أو ترفضيه.")
        tbl = offer_table(pend)
        ed = st.data_editor(tbl, hide_index=True, use_container_width=True, key="pend",
                            disabled=[c for c in tbl.columns if c != "اختيار"], column_config=CFG)
        ids = ed.loc[ed["اختيار"], "رقم"].tolist()
        a, b, c = st.columns(3)
        if a.button(f"✅ انشري ({len(ids)})", disabled=not ids, use_container_width=True, type="primary"):
            writes.set_status(eng, ids, "approved"); cm.refresh(); st.rerun()
        if b.button(f"❌ ارفضي ({len(ids)})", disabled=not ids, use_container_width=True):
            writes.set_status(eng, ids, "rejected"); cm.refresh(); st.rerun()
        if c.button("✅ انشري الكل", use_container_width=True):
            writes.set_status(eng, pend["offer_id"].tolist(), "approved"); cm.refresh(); st.rerun()

# ---------------------------------------------------------------- all offers: edit numbers, hide/show
with t_all:
    f1, f2 = st.columns(2)
    sec = f1.selectbox("القطاع", ["الكل"] + sorted(allo["sector"].unique()))
    stt = f2.multiselect("الحالة", list(cm.AR_STATUS), default=["approved"], format_func=cm.AR_STATUS.get)
    v = allo[allo["status"].isin(stt)]
    if sec != "الكل":
        v = v[v["sector"] == sec]
    st.caption(f"{len(v)} عرض. عدّلي السعر أو القسط أو الشهور، أو شيلي علامة «ظاهر» علشان تخفي العرض، وبعدين احفظي.")
    base = pd.DataFrame({"رقم": v["offer_id"], "المنتج": v["item"], "الجهة": v["financier_short"],
                         "كاش": v["cash_price"], "شهور": v["months"], "القسط": v["monthly_installment"],
                         "الفايدة %": v["apr_effective"] * 100, "ظاهر": v["is_active"].astype(bool)}).reset_index(drop=True)
    edited = st.data_editor(base, hide_index=True, use_container_width=True, key="edit_all",
                            disabled=["رقم", "المنتج", "الجهة", "الفايدة %"], column_config=CFG | {
                                "شهور": st.column_config.NumberColumn(format="%d", min_value=1, max_value=360)})
    keys = ["كاش", "شهور", "القسط", "ظاهر"]
    diff = (edited[keys].fillna(-1) != base[keys].fillna(-1)).any(axis=1)
    changed = edited[diff & edited["شهور"].notna() & edited["القسط"].notna()]
    if st.button(f"💾 احفظي التعديلات ({len(changed)})", type="primary", disabled=changed.empty):
        n = writes.update_offers(eng, [{"offer_id": r["رقم"], "cash_price": r["كاش"] if pd.notna(r["كاش"]) else None,
                                        "monthly_installment": r["القسط"], "months": r["شهور"], "is_active": r["ظاهر"]}
                                       for _, r in changed.iterrows()])
        cm.refresh()
        st.success(f"اتحفظ {n} تعديل، والفايدة اتحسبت من جديد.")
        st.rerun()

# ---------------------------------------------------------------- add an approved offer directly
with t_new, st.form("admin_new", clear_on_submit=True):
    st.markdown("#### عرض جديد (بيتنشر على طول)")
    a, b = st.columns(2)
    sector_id = a.selectbox("القطاع", sectors["sector_id"], format_func=lambda i: sectors.set_index("sector_id").loc[i, "name_ar"])
    item = b.text_input("المنتج")
    merchant = a.text_input("المحل")
    financier = b.selectbox("جهة التقسيط", sorted(d["financiers"]["name"].unique()) + ["جهة جديدة"])
    new_fin = b.text_input("اسم الجهة الجديدة")
    c1, c2, c3, c4, c5 = st.columns(5)
    cash = c1.number_input("كاش", min_value=0, step=100, format="%d")
    down = c2.number_input("مقدم", min_value=0, step=100, format="%d")
    fee = c3.number_input("مصاريف", min_value=0, step=50, format="%d")
    months = c4.number_input("شهور", min_value=1, max_value=360, value=12)
    monthly = c5.number_input("القسط", min_value=0, step=50, format="%d")
    src = a.text_input("اسم المصدر")
    url = b.text_input("رابط المصدر")
    notes = st.text_input("ملاحظات")
    if st.form_submit_button("انشري العرض", type="primary"):
        fin = new_fin.strip() if financier == "جهة جديدة" else financier
        if not item.strip() or not monthly or not fin:
            st.error("اكتبي المنتج والقسط والجهة.")
        else:
            oid = writes.add_offer(eng, {"sector_id": sector_id, "item": item, "merchant": merchant, "financier": fin,
                                         "cash_price": cash or None, "down_payment": down, "upfront_fees": fee,
                                         "months": months, "monthly_installment": monthly, "source_name": src,
                                         "source_url": url or None, "notes": notes or None},
                                   status="approved", entry_source="admin")
            cm.refresh()
            st.success(f"اتنشر العرض رقم {oid}.")

# ---------------------------------------------------------------- calculator plans + benchmarks
with t_plans:
    st.markdown("#### أنظمة الحاسبة")
    p = d["plans"]
    pb = pd.DataFrame({"رقم": p["plan_id"], "النظام": p["name"], "فايدة ثابتة سنوية %": p["flat_annual_rate"] * 100,
                       "أقل مدة": p["min_months"], "أطول مدة": p["max_months"], "مفعّل": p["is_active"].astype(bool)})
    pe = st.data_editor(pb, hide_index=True, use_container_width=True, key="plans", disabled=["رقم", "النظام"],
                        column_config={"فايدة ثابتة سنوية %": st.column_config.NumberColumn(format="%.2f", min_value=0, step=0.5)})
    pch = pe[(pe != pb).any(axis=1)]
    if st.button(f"💾 احفظي الأنظمة ({len(pch)})", disabled=pch.empty, type="primary"):
        writes.update_plans(eng, [{"plan_id": r["رقم"], "flat_annual_rate": r["فايدة ثابتة سنوية %"] / 100,
                                   "min_months": r["أقل مدة"], "max_months": r["أطول مدة"], "is_active": r["مفعّل"]}
                                  for _, r in pch.iterrows()])
        cm.refresh(); st.rerun()

    st.markdown("#### أرقام المقارنة (التضخم والشهادة)")
    b = d["benchmarks"]
    bb = pd.DataFrame({"code": b["code"], "المؤشر": b["indicator"], "القيمة %": b["value"] * 100})
    be = st.data_editor(bb, hide_index=True, use_container_width=True, key="bench", disabled=["code", "المؤشر"],
                        column_config={"code": None, "القيمة %": st.column_config.NumberColumn(format="%.2f", min_value=0, step=0.25)})
    bch = be[be["القيمة %"] != bb["القيمة %"]]
    if st.button(f"💾 احفظي الأرقام ({len(bch)})", disabled=bch.empty):
        writes.update_benchmarks(eng, [{"code": r["code"], "value": r["القيمة %"] / 100} for _, r in bch.iterrows()])
        cm.refresh(); st.rerun()
