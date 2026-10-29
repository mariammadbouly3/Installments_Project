import pandas as pd
import streamlit as st

import common as cm

d = cm.data()
o, b = d["offers"], d["benchmarks"]

cm.header("المصادر والمنهجية", "الداتا جت منين، والفايدة اتحسبت إزاي، وإيه حدودها.")

with st.container(border=True):
    st.markdown("""
#### إزاي بنحسب الفايدة الحقيقية
- **الإجمالي** = المقدم + المصاريف الإدارية + (القسط × عدد الشهور) + أي دفعات سنوية.
- **الزيادة عن الكاش** = الإجمالي − السعر كاش.
- **الفايدة السنوية الفعلية**: بنحسب نسبة الفايدة الشهرية اللي تخلي قيمة الأقساط النهارده = المبلغ اللي اتموّل فعلًا
  (السعر كاش − المقدم − المصاريف)، وبعدين نحولها لسنوية: (1 + الشهرية)^12 − 1.
  نفس الحساب موجود في قاعدة البيانات كدالة `effective_apr`، فأي عرض جديد بيتحسب لوحده.
- المصاريف الإدارية مفترض إنها بتتدفع مقدمًا. لو بتتقسط مع المبلغ، الفايدة الفعلية بتقل شوية.
- **الحكم**: لو الفايدة أعلى من عائد الشهادة البنكية، الكاش أوفر. لو 0%، قسّطي وحطي الكاش في شهادة.
""")

with st.container(border=True):
    st.markdown("#### أرقام المقارنة")
    st.dataframe(pd.DataFrame({"المؤشر": b["indicator"], "القيمة %": b["value"] * 100, "المصدر": b["source_url"]}),
                 hide_index=True, use_container_width=True, column_config={
                     "القيمة %": st.column_config.NumberColumn(format="%.2f%%"),
                     "المصدر": st.column_config.LinkColumn(display_text="افتحي")})

with st.container(border=True):
    st.markdown("#### المصادر")
    s = (o.groupby(["source_name", "source_url"], dropna=False).agg(عروض=("offer_id", "count"), القطاع=("sector", "first"))
         .reset_index().sort_values("عروض", ascending=False))
    st.dataframe(pd.DataFrame({"المصدر": s["source_name"], "القطاع": s["القطاع"], "عروض": s["عروض"], "الرابط": s["source_url"]}),
                 hide_index=True, use_container_width=True,
                 column_config={"الرابط": st.column_config.LinkColumn(display_text="افتحي")})

with st.container(border=True):
    st.markdown("""
#### حدود الداتا
- العروض متجمعة من مواقع رسمية للمحلات والبنوك وشركات التمويل وإعلانات منشورة، لحد أكتوبر 2026. المواقع نفسها بتقول إن الأرقام تقريبية.
- الصفوف **سيناريو**: سعر حقيقي أو مبلغ ثابت (10,000 ج) مطبق عليه شروط منشورة في مكان تاني، علشان نقارن الشركات ببعض.
- قطاعات التجميل والطاقة الشمسية والأفراح والتأمين فيها شروط بس من غير أسعار منشورة.
- العقارات: السعر الكاش مش منشور، فالفايدة مش محسوبة.
- العروض اللي بتتضاف من صفحة **ضيفي عرض** مبتظهرش غير بعد موافقة الإدارة.
- الصفحة دي للتحليل، مش عرض سعر. اتأكدي من الشروط مع الشركة قبل ما تمضي.
""")
