import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

import common as cm

cm.header("لوحة المؤشرات", "كام بتدفعي زيادة لما تقسّطي في مصر؟ الأرقام بتتحسب من قاعدة البيانات وبتتحدّث لوحدها.")


def ref_lines(fig, horizontal=True):
    """Dashed lines for inflation and the bank CD rate."""
    for val, name, color in [(cm.inflation(), "التضخم", cm.MUTED), (cm.cd_rate(), "الشهادة", cm.GREEN)]:
        if horizontal:
            fig.add_vline(x=val, line_dash="dash", line_color=color, annotation_text=f"{name} {cm.pct(val, 1)}",
                          annotation_position="top", annotation_font_color=color)
        else:
            fig.add_hline(y=val, line_dash="dash", line_color=color, annotation_text=f"{name} {cm.pct(val, 1)}",
                          annotation_font_color=color)
    return fig


@st.fragment(run_every="60s")
def live_dashboard():
    d = cm.data()
    o, allo = d["offers"], d["all_offers"]
    rated = o[o["has_rate"]]
    costly = rated[~rated["is_zero_interest"]]
    cd = cm.cd_rate()

    cm.html(f'<span class="live">آخر تحديث {cm.now():%H:%M}، وبتتحدّث كل دقيقة</span>')
    c1, c2 = st.columns([1, 3])
    with c1:
        kind = st.selectbox("العروض", ["الكل", "العروض الحقيقية بس"], index=0)
    with c2:
        if st.button("🔄 تحديث دلوقتي"):
            cm.refresh()
            st.rerun(scope="fragment")
    if kind != "الكل":
        o = o[~o["is_scenario"]]
        rated = o[o["has_rate"]]
        costly = rated[~rated["is_zero_interest"]]

    pending = int((allo["status"] == "pending").sum())
    cm.kpis([
        (f"{len(o)}", f"عرض منشور في {o['sector'].nunique()} قطاع"),
        (cm.pct(costly["apr_effective"].mean()), "متوسط الفايدة السنوية في العروض اللي فيها تكلفة", "cost"),
        (cm.pct((rated["apr_effective"] >= cd).mean()), "من العروض الكاش فيها أوفر من التقسيط + شهادة", "cost"),
        (f"{int(rated['is_zero_interest'].sum())}", "عرض 0% فعلًا من غير أي مصاريف", "good"),
        (f"{pending}", "عرض جه من الموقع مستني المراجعة", "accent"),
    ])

    a, b = st.columns(2)
    with a, st.container(border=True):
        st.markdown("#### الفايدة السنوية حسب القطاع")
        s = rated.groupby("sector", as_index=False).agg(apr=("apr_effective", "mean"), n=("offer_id", "count")).sort_values("apr")
        s["color"] = s["apr"].map(lambda v: cm.GREEN if v < 0.001 else (cm.GOLD if v < cd else cm.CORAL))
        fig = go.Figure(go.Bar(x=s["apr"], y=s["sector"], orientation="h", marker_color=s["color"],
                               text=s["apr"].map(lambda v: cm.pct(v)), textposition="outside",
                               customdata=s["n"], hovertemplate="%{y}<br>%{x:.1%}<br>%{customdata} عرض<extra></extra>"))
        fig.update_xaxes(tickformat=".0%", range=[0, max(0.5, s["apr"].max() * 1.15)])
        fig.update_yaxes(side="right")
        st.plotly_chart(cm.style_fig(ref_lines(fig), 460), use_container_width=True)
    with b, st.container(border=True):
        st.markdown("#### الفايدة حسب جهة التقسيط")
        f = (costly.groupby("financier_short", as_index=False)
             .agg(apr=("apr_effective", "mean"), n=("offer_id", "count")).query("n >= 2").sort_values("apr"))
        fig = go.Figure(go.Bar(x=f["apr"], y=f["financier_short"], orientation="h", marker_color=cm.CORAL,
                               text=f["apr"].map(lambda v: cm.pct(v)), textposition="outside",
                               customdata=f["n"], hovertemplate="%{y}<br>%{x:.1%}<br>%{customdata} عرض<extra></extra>"))
        fig.update_xaxes(tickformat=".0%", range=[0, max(0.5, (f["apr"].max() if len(f) else 0) * 1.15)])
        fig.update_yaxes(side="right")
        st.plotly_chart(cm.style_fig(ref_lines(fig), 460), use_container_width=True)
        cm.html('<p class="note">العروض اللي فيها تكلفة بس، والجهات اللي ليها عرضين أو أكتر.</p>')

    a, b = st.columns(2)
    with a, st.container(border=True):
        st.markdown("#### قسّطي ولا ادفعي كاش؟")
        v = o["verdict"].value_counts().reset_index()
        v.columns = ["الحكم", "عدد"]
        pie = px.pie(v, names="الحكم", values="عدد", hole=.6, color="الحكم", color_discrete_map=cm.VERDICT_COLORS)
        st.plotly_chart(cm.style_fig(pie, 340), use_container_width=True)
        cm.html(f'<p class="note">مقارنة بعائد شهادة {cm.pct(cd, 2)}: لو الفايدة أعلى منه، الكاش أوفر.</p>')
    with b, st.container(border=True):
        st.markdown("#### المدة بتزود الإجمالي، مش الفايدة")
        dd = costly.dropna(subset=["months"])
        sc = px.scatter(dd, x="months", y="extra_pct", color="financier_short", hover_name="item",
                        labels={"months": "عدد الشهور", "extra_pct": "الزيادة عن الكاش", "financier_short": "الجهة"})
        sc.update_yaxes(tickformat=".0%")
        sc.update_traces(marker=dict(size=10, opacity=.8))
        st.plotly_chart(cm.style_fig(sc, 340), use_container_width=True)

    with st.container(border=True):
        st.markdown("#### أحدث العروض اللي اتضافت")
        new = o.sort_values(["created_at", "offer_id"], ascending=False).head(8)
        st.dataframe(pd.DataFrame({
            "المنتج": new["item"], "القطاع": new["sector"], "الجهة": new["financier_short"],
            "كاش": new["cash_price"], "شهور": new["months"], "القسط": new["monthly_installment"],
            "الفايدة السنوية": new["apr_effective"] * 100, "اتضاف": new["created_at"].dt.strftime("%d/%m/%Y"),
            "من": new["entry_source"].map(cm.AR_SOURCE)}),
            hide_index=True, use_container_width=True, column_config={
                "كاش": st.column_config.NumberColumn(format="%d"), "القسط": st.column_config.NumberColumn(format="%d"),
                "الفايدة السنوية": st.column_config.NumberColumn(format="%.1f%%")})


live_dashboard()
