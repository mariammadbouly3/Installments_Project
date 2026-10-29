"""حسبة التقسيط - entry point.

Run locally:   streamlit run app.py   (or double-click run_app.bat)
Cloud:         Streamlit Community Cloud with DATABASE_URL and ADMIN_PASSWORD in the app secrets.
"""
import streamlit as st

import common as cm

st.set_page_config(page_title="حسبة التقسيط", page_icon="💳", layout="wide", initial_sidebar_state="auto")
cm.inject_style()


def page_file(name):
    """Pages live in views/ on the laptop, but next to app.py in the GitHub repo. Support both."""
    nested = cm.HERE / "views" / name
    return str(nested if nested.exists() else cm.HERE / name)


pages = [
    st.Page(page_file("dashboard.py"), title="لوحة المؤشرات", icon="📊", default=True),
    st.Page(page_file("calculator.py"), title="احسبي القسط", icon="🧮"),
    st.Page(page_file("offers.py"), title="كل العروض", icon="📋"),
    st.Page(page_file("sector.py"), title="تفاصيل قطاع", icon="🔎"),
    st.Page(page_file("submit.py"), title="ضيفي عرض", icon="➕"),
    st.Page(page_file("sources.py"), title="المصادر والمنهجية", icon="📚"),
    st.Page(page_file("admin.py"), title="الإدارة", icon="🔐"),
]
try:
    nav = st.navigation(pages, position="top")
except TypeError:  # older Streamlit without top navigation
    nav = st.navigation(pages)

if not cm.database_url():
    cm.local_connect_form()
    cm.header("حسبة التقسيط", "اتصلي بقاعدة البيانات الأول.")
    st.info("اكتبي كلمة مرور PostgreSQL في القائمة الجانبية واضغطي **اتصال**. لو التطبيق شغال على Streamlit Cloud، "
            "ضيفي DATABASE_URL في الـ Secrets بدل كده.")
    st.stop()

try:
    cm.data()
except Exception as e:  # noqa: BLE001
    cm.local_connect_form()
    cm.header("حسبة التقسيط", "تعذّر الاتصال بقاعدة البيانات.")
    st.error("اتأكدي إن بيانات الاتصال صح، وإنك شغلتي ملف sql/00_cloud_setup.sql على قاعدة البيانات دي.\n\n" + str(e))
    st.stop()

nav.run()
