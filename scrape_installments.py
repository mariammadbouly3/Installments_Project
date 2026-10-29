# -*- coding: utf-8 -*-
"""
سكريبت سحب عروض التقسيط — شغّليه على جهازك (مش بيتشغل من بيئة Claude لأنها مقفولة على الإنترنت).

التثبيت:
    pip install requests beautifulsoup4 pandas

التشغيل:
    python scrape_installments.py andalus                 # كل أقسام الأندلس للأثاث (كاش + قسط 36 شهر)
    python scrape_installments.py aqarmap urls.txt        # ملف فيه روابط إعلانات عقارماب (رابط في كل سطر)

النتيجة بتتحفظ في CSV بنفس أعمدة تاب offers في الداتاسيت، فتقدري تلزقيها تحت الصفوف الموجودة.
ملاحظة: الأنماط مكتوبة على شكل الصفحات وقت كتابة السكريبت (أكتوبر 2026). لو موقع غيّر تصميمه، عدّلي الـ regex.
احترمي شروط استخدام كل موقع وسيبي وقت بين الطلبات (السكريبت بيستنى ثانيتين).
"""
import re, sys, time, datetime
import requests, pandas as pd
from bs4 import BeautifulSoup

HEADERS = {"User-Agent": "Mozilla/5.0 (portfolio research; contact: your-email)"}
TODAY = datetime.date.today().isoformat()
COLS = ["sector","sub_category","item","merchant","financier","financier_type","data_type","cash_price",
        "listed_installment_price","down_payment","upfront_fees","months","monthly_installment",
        "notes","source_name","source_url","date_observed"]

def num(s):
    return float(re.sub(r"[^\d.]", "", s)) if s else None

def get_text(url):
    r = requests.get(url, headers=HEADERS, timeout=30)
    r.raise_for_status()
    return BeautifulSoup(r.text, "html.parser").get_text(" ", strip=True)

# ---------------- الأندلس للأثاث ----------------
ANDALUS = {"غرفة نوم": "bedroom2", "غرفة أطفال": "kids", "غرفة شبابي": "youth", "غرفة سفرة": "dining2",
           "أنتريه": "living2", "ركنة": "corner2", "مراتب": "mattresses"}

def scrape_andalus():
    rows = []
    pat = re.compile(r"##?\s*([^#]{3,60}?)\s+(?:متوفرة|عليها|بتتصنع).*?سعر الكاش\s*([\d,]+)\s*جنيه.*?قسّطها\s*([\d,]+)\s*ج/شهر\s*(\d+)\s*شهر", re.S)
    simple = re.compile(r"سعر الكاش\s*([\d,]+)\s*جنيه\s*أو قسّطها\s*([\d,]+)\s*ج/شهر\s*(\d+)\s*شهر")
    for sub, slug in ANDALUS.items():
        url = f"https://www.andalusfurniture.com/{slug}/"
        try:
            text = get_text(url)
        except Exception as e:
            print("فشل:", url, e); continue
        found = pat.findall(text) or [("", *m) for m in simple.findall(text)]
        for name, cash, monthly, months in found:
            rows.append(dict(sector="أثاث ومطابخ", sub_category=sub, item=(name.strip() or sub), merchant="الأندلس للأثاث",
                             financier="موجو MOGO", financier_type="شركة تمويل استهلاكي", data_type="عرض حقيقي منشور",
                             cash_price=num(cash), listed_installment_price=None, down_payment=0, upfront_fees=0,
                             months=int(months), monthly_installment=num(monthly),
                             notes="سحب آلي؛ بدون مقدم", source_name="الأندلس للأثاث", source_url=url, date_observed=TODAY))
        print(f"{sub}: {len(found)} موديل")
        time.sleep(2)
    return rows

# ---------------- عقارماب ----------------
def scrape_aqarmap(urls):
    rows = []
    for url in urls:
        try:
            text = get_text(url)
        except Exception as e:
            print("فشل:", url, e); continue
        g = lambda label: (re.search(label + r"\s*([\d,]+)", text) or [None, None])[1]
        years = re.search(r"مدة التقسيط\s*(\d+)\s*سنو?ات?", text)
        title = re.search(r"#\s*(.+?)\s+(?:حفظ|ملاحظة)", text)
        listed, down, monthly = num(g("سعر التقسيط")), num(g("المقدم")), num(g("القسط الشهري"))
        if not listed:
            print("مفيش تفاصيل تقسيط:", url); continue
        rows.append(dict(sector="عقارات", sub_category="شقق - تقسيط مطور", item=title.group(1)[:120] if title else "",
                         merchant="مطور/مسوق عقاري", financier="المطور", financier_type="تقسيط مباشر من التاجر",
                         data_type="إعلان حقيقي", cash_price=None, listed_installment_price=listed, down_payment=down,
                         upfront_fees=0, months=int(years.group(1)) * 12 if years else None, monthly_installment=monthly,
                         notes="سحب آلي؛ السعر الكاش غير منشور", source_name="عقارماب", source_url=url, date_observed=TODAY))
        time.sleep(2)
    return rows

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit()
    if sys.argv[1] == "andalus":
        data, out = scrape_andalus(), "scraped_andalus.csv"
    elif sys.argv[1] == "aqarmap":
        urls = [u.strip() for u in open(sys.argv[2], encoding="utf-8") if u.strip()]
        data, out = scrape_aqarmap(urls), "scraped_aqarmap.csv"
    else:
        sys.exit("اختاري: andalus أو aqarmap")
    pd.DataFrame(data, columns=COLS).to_csv(out, index=False, encoding="utf-8-sig")
    print("اتحفظ:", out, "-", len(data), "صف")
