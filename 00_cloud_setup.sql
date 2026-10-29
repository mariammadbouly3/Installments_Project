-- =====================================================================
-- ONE-FILE SETUP — مشروع التقسيط في السوق المصري (PostgreSQL / Neon)
-- بيعمل schema اسمها installments فيها كل الجداول والداتا والدوال والـ views.
-- تشغيله تاني بيرجّع كل حاجة لأولها (RESET).
-- =====================================================================

DROP SCHEMA IF EXISTS installments CASCADE;
CREATE SCHEMA installments;
SET search_path TO installments;

-- ---------------------------------------------------------------------
-- 1) Lookups
-- ---------------------------------------------------------------------
CREATE TABLE sectors (
    sector_id   SERIAL PRIMARY KEY,
    name_ar     TEXT NOT NULL UNIQUE,
    name_en     TEXT NOT NULL
);

CREATE TABLE financiers (
    financier_id   SERIAL PRIMARY KEY,
    name           TEXT NOT NULL UNIQUE,      -- as written in the source
    short_name     TEXT NOT NULL,             -- for charts
    financier_type TEXT
);

-- ---------------------------------------------------------------------
-- 2) Offers: one row = one product on one installment plan
-- ---------------------------------------------------------------------
CREATE TABLE offers (
    offer_id                 SERIAL PRIMARY KEY,
    sector_id                INT NOT NULL REFERENCES sectors(sector_id),
    sub_category             TEXT,
    item                     TEXT NOT NULL,
    merchant                 TEXT,
    financier_id             INT REFERENCES financiers(financier_id),
    data_type                TEXT,
    is_scenario              BOOLEAN NOT NULL DEFAULT FALSE,
    cash_price               NUMERIC(14,2) CHECK (cash_price > 0),
    listed_installment_price NUMERIC(14,2) CHECK (listed_installment_price > 0),
    down_payment             NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (down_payment >= 0),
    upfront_fees             NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (upfront_fees >= 0),
    months                   INT CHECK (months BETWEEN 1 AND 360),
    monthly_installment      NUMERIC(14,2) CHECK (monthly_installment > 0),
    annual_payments_total    NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (annual_payments_total >= 0),
    notes                    TEXT,
    source_name              TEXT,
    source_url               TEXT,
    date_observed            DATE NOT NULL DEFAULT CURRENT_DATE,
    status                   TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('approved','pending','rejected')),
    is_active                BOOLEAN NOT NULL DEFAULT TRUE,
    entry_source             TEXT NOT NULL DEFAULT 'seed' CHECK (entry_source IN ('seed','web','admin')),
    submitted_by             TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((months IS NULL) = (monthly_installment IS NULL))
);
CREATE INDEX ON offers (sector_id);
CREATE INDEX ON offers (status, is_active);

-- 3) Published rules of each company (no specific product)
CREATE TABLE plan_terms (
    term_id        SERIAL PRIMARY KEY,
    sector_id      INT NOT NULL REFERENCES sectors(sector_id),
    financier      TEXT NOT NULL,
    financier_type TEXT,
    applies_to     TEXT,
    duration       TEXT,
    interest       TEXT,
    down_payment   TEXT,
    admin_fees     TEXT,
    notes          TEXT,
    date_text      TEXT,
    source_name    TEXT,
    source_url     TEXT
);

-- 4) Benchmarks (inflation, bank CD) — editable from the admin page
CREATE TABLE benchmarks (
    code       TEXT PRIMARY KEY,
    indicator  TEXT NOT NULL,
    value      NUMERIC(6,4) NOT NULL CHECK (value >= 0),
    source_url TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5) Calculator plans — editable from the admin page
CREATE TABLE calc_plans (
    plan_id          SERIAL PRIMARY KEY,
    name             TEXT NOT NULL UNIQUE,
    flat_annual_rate NUMERIC(6,4) NOT NULL DEFAULT 0 CHECK (flat_annual_rate >= 0),
    min_months       INT NOT NULL CHECK (min_months > 0),
    max_months       INT NOT NULL CHECK (max_months >= min_months),
    note             TEXT,
    source_url       TEXT,
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order       INT NOT NULL DEFAULT 0
);
CREATE TABLE calc_plan_fees (          -- admin fee % by duration ("up to N months")
    plan_id    INT NOT NULL REFERENCES calc_plans(plan_id) ON DELETE CASCADE,
    up_to_months INT NOT NULL,
    fee_pct    NUMERIC(6,4) NOT NULL CHECK (fee_pct >= 0),
    PRIMARY KEY (plan_id, up_to_months)
);

-- ---------------------------------------------------------------------
-- 6) Effective annual interest (IRR of the cash flows), bisection
--    pv  = money actually financed (cash price - down payment - upfront fees)
--    pmt = monthly installment, n = months
--    annual = extra payment at the end of each year (clubs), years = how many
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION effective_apr(pv NUMERIC, pmt NUMERIC, n INT,
                                         annual NUMERIC DEFAULT 0, years INT DEFAULT 0)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE lo FLOAT8 := 0; hi FLOAT8 := 1; r FLOAT8; v FLOAT8; i INT; k INT;
BEGIN
    IF pv IS NULL OR pmt IS NULL OR n IS NULL OR pv <= 0 THEN RETURN NULL; END IF;
    IF pmt * n + COALESCE(annual,0) * COALESCE(years,0) <= pv + 0.5 THEN RETURN 0; END IF;
    FOR i IN 1..100 LOOP
        r := (lo + hi) / 2;
        v := pmt * (1 - power(1 + r, -n)) / r;
        FOR k IN 1..COALESCE(years,0) LOOP v := v + annual / power(1 + r, 12 * k); END LOOP;
        IF v > pv THEN lo := r; ELSE hi := r; END IF;
    END LOOP;
    RETURN round((power(1 + (lo + hi) / 2, 12) - 1)::numeric, 4);
END $$;

INSERT INTO sectors (name_ar, name_en) VALUES
('موبايلات وإلكترونيات', 'Phones & Electronics'),
('أجهزة منزلية', 'Home Appliances'),
('أثاث ومطابخ', 'Furniture'),
('عربيات', 'Cars'),
('عقارات', 'Real Estate'),
('دهب وشبكة', 'Gold'),
('تعليم', 'Education'),
('سفر وعمرة وحج', 'Travel & Umrah'),
('علاج وأسنان', 'Medical & Dental'),
('لبس وموضة', 'Fashion (BNPL)'),
('موتوسيكلات وتكاتك', 'Motorcycles'),
('مستحضرات تجميل وعطور', 'Beauty'),
('اشتراكات جيم ونوادي', 'Gyms & Clubs'),
('طاقة شمسية وتكييفات', 'Solar & AC'),
('تشطيبات وأدوات صحية', 'Finishing'),
('قاعات أفراح وتجهيز عرايس', 'Weddings'),
('ألعاب وبلايستيشن', 'Gaming'),
('عجل ومستلزمات رياضية', 'Bicycles'),
('تأمين', 'Insurance');

INSERT INTO financiers (name, short_name, financier_type) VALUES
('موجو MOGO', 'موجو', 'شركة تمويل استهلاكي'),
('أمان Aman', 'أمان', 'شركة تمويل استهلاكي'),
('TRU', 'TRU', 'شركة تمويل استهلاكي'),
('فرصة Forsa', 'فرصة', 'شركة تمويل استهلاكي'),
('سيمبل Sympl', 'سيمبل', 'اشتر الآن وادفع لاحقًا'),
('معارض/مشروعي', 'معارض/مشروعي', 'تقسيط مباشر من التاجر'),
('تقسيط بنكي', 'قرض بنكي (عربيات)', 'بنك'),
('غير محدد', 'غير محدد', 'غير محدد'),
('المطور', 'المطور العقاري', 'تقسيط مباشر من التاجر'),
('ممنوع عبر التمويل الاستهلاكي', 'ممنوع عبر التمويل الاستهلاكي', 'قرار تنظيمي'),
('البنك الأهلي المصري', 'البنك الأهلي', 'بنك'),
('بطاقات البنوك (الأهلي/CIB/مصر...)', 'بطاقات البنوك', 'بنك'),
('بريميوم كارد', 'بريميوم كارد', 'شركة تمويل استهلاكي'),
('InBank', 'InBank (سامسونج)', 'بنك'),
('—', '—', '—'),
('النادي', 'النادي (مباشر)', 'تقسيط مباشر من التاجر'),
('بنك مصر', 'بنك مصر', 'بنك'),
('العيادة', 'العيادة (مباشر)', 'تقسيط مباشر من التاجر');

INSERT INTO offers (sector_id, sub_category, item, merchant, financier_id, data_type, is_scenario, cash_price,
    listed_installment_price, down_payment, upfront_fees, months, monthly_installment, annual_payments_total,
    notes, source_name, source_url, date_observed) VALUES
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 33', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 70000, NULL, 0, 0, 36, 2995, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 40', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 72500, NULL, 0, 0, 36, 3102, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 38', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 74600, NULL, 0, 0, 36, 3192, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 27', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 94400, NULL, 0, 0, 36, 4039, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 42', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 94500, NULL, 0, 0, 36, 4043, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 41', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 59900, NULL, 0, 0, 36, 2563, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 39', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 64000, NULL, 0, 0, 36, 2738, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 31', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 91800, NULL, 0, 0, 36, 3927, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 16', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 57800, NULL, 0, 0, 36, 2473, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 20', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 57900, NULL, 0, 0, 36, 2477, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 21', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 58700, NULL, 0, 0, 36, 2512, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 14', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 59900, NULL, 0, 0, 36, 2563, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية وتتأكد من شركة التقسيط', 'الأندلس للأثاث - غرف النوم', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 36', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 56300, NULL, 0, 0, 36, 2597, 0, 'قسط أمان؛ مرابحة شهرية ثابتة 1.8333% بدون مقدم (حسب الموقع)', 'الأندلس للأثاث - غرف النوم (نتيجة بحث)', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 37', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 57600, NULL, 0, 0, 36, 2656, 0, 'قسط أمان؛ مرابحة شهرية ثابتة 1.8333% بدون مقدم (حسب الموقع)', 'الأندلس للأثاث - غرف النوم (نتيجة بحث)', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 26', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 82400, NULL, 0, 0, 36, 3800, 0, 'قسط أمان؛ مرابحة شهرية ثابتة 1.8333% بدون مقدم (حسب الموقع)', 'الأندلس للأثاث - غرف النوم (نتيجة بحث)', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 3', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي + سعر كاش مستنتج', FALSE, 65700, NULL, 0, 0, 12, 6680, 0, 'السعر الكاش غير ظاهر؛ مستنتج 65,700 من الإجماليات المنشورة (80,154 / 94,608 / 109,062) ومعدل 1.8333% شهريًا ثابت', 'الأندلس للأثاث - غرف النوم (نتيجة بحث)', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 3', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي + سعر كاش مستنتج', FALSE, 65700, NULL, 0, 0, 24, 3942, 0, 'السعر الكاش غير ظاهر؛ مستنتج 65,700 من الإجماليات المنشورة (80,154 / 94,608 / 109,062) ومعدل 1.8333% شهريًا ثابت', 'الأندلس للأثاث - غرف النوم (نتيجة بحث)', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة نوم', 'غرفة نوم موديل 3', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي + سعر كاش مستنتج', FALSE, 65700, NULL, 0, 0, 36, 3030, 0, 'السعر الكاش غير ظاهر؛ مستنتج 65,700 من الإجماليات المنشورة (80,154 / 94,608 / 109,062) ومعدل 1.8333% شهريًا ثابت', 'الأندلس للأثاث - غرف النوم (نتيجة بحث)', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Samsung Galaxy S26 FE', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='TRU'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 52100, NULL, 0, 0, 12, 4341.67, 0, 'تقسيط بدون فوائد حتى 12 شهر مع TRU؛ القسط = السعر ÷ 12', 'Samsung Egypt - Galaxy S26', 'https://www.samsung.com/eg/smartphones/galaxy-s26/buy/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='ألعاب وبلايستيشن'), 'أجهزة ألعاب', 'بلاي ستيشن 5 سليم - ديسك + ذراع', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 43800, NULL, 0, 0, 3, 14600, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - أجهزة الألعاب', 'https://www.amanstores.com/ar/computers-and-gaming/game-consoles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='ألعاب وبلايستيشن'), 'أجهزة ألعاب', 'بلاي ستيشن 5 برو 2 تيرا', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 69999, NULL, 0, 0, 3, 23333, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - أجهزة الألعاب', 'https://www.amanstores.com/ar/computers-and-gaming/game-consoles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='ألعاب وبلايستيشن'), 'أجهزة ألعاب', 'ذراع DualSense رمادي مموه', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 4444, NULL, 0, 0, 3, 1481.33, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - أجهزة الألعاب', 'https://www.amanstores.com/ar/computers-and-gaming/game-consoles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عجل ومستلزمات رياضية'), 'دراجات', 'دراجة جبلية فونيكس 2608 - 26 بوصة', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 7500, NULL, 0, 0, 3, 2500, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - دراجات', 'https://www.amanstores.com/ar/sports-fitness/bikes-bicycles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عجل ومستلزمات رياضية'), 'دراجات', 'Phoenix 2902 PRO - 29 بوصة', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 7800, NULL, 0, 0, 3, 2600, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - دراجات', 'https://www.amanstores.com/ar/sports-fitness/bikes-bicycles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عجل ومستلزمات رياضية'), 'دراجات', 'دراجة طريق تينكس 700', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 6050, NULL, 0, 0, 3, 2016.67, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - دراجات', 'https://www.amanstores.com/ar/sports-fitness/bikes-bicycles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عجل ومستلزمات رياضية'), 'دراجات', 'عجلة تريكس كلاسيك 26 بوصة', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 4500, NULL, 0, 0, 3, 1500, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - دراجات', 'https://www.amanstores.com/ar/sports-fitness/bikes-bicycles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='تشطيبات وأدوات صحية'), 'أدوات صحية', 'حوض وحدة موبيليا ديكود أبيض 105 سم', 'المشرقي للسيراميك', (SELECT financier_id FROM financiers WHERE name='فرصة Forsa'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 5478, NULL, 0, 0, 6, 913, 0, 'فرصة: 3 أو 6 شهور بدون فوايد ولا مقدم ولا مصاريف', 'المشرقي للسيراميك', 'https://mashreqy.com/categories/%D8%A7%D8%AF%D9%88%D8%A7%D8%AA-%D8%B5%D8%AD%D9%8A%D8%A9', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='لبس وموضة'), 'اشتر الآن وادفع لاحقًا', 'أوردر 4,000 جنيه (مثال الشركة)', 'متاجر سيمبل', (SELECT financier_id FROM financiers WHERE name='سيمبل Sympl'), 'مثال رسمي منشور', FALSE, 4000, NULL, 0, 100, 4, 1000, 0, '0% فوائد + مصاريف خدمة ثابتة 100 ج على كل عملية', 'Sympl عبر متجر جلود', 'https://jlood.com/pages/sympl', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'دراجة كهربائية', 'دراجة كهربائية 500 وات', 'إعلان على دوبيزل', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'إعلان حقيقي', FALSE, 14000, NULL, 1400, 0, 24, 750, 0, 'الإعلان: مقدم 10% وقسط يبدأ من 750 (6–24 شهر) بفايدة 2% شهريًا؛ المدة 24 شهر مفترضة لأنها أقل قسط', 'Dubizzle Egypt', 'https://www.dubizzle.com.eg/en/ad/%D8%A7%D9%82%D9%88%D9%8A-%D8%AF%D8%B1%D8%A7%D8%AC%D9%87-%D9%83%D9%87%D8%B1%D8%A8%D8%A7%D8%A6%D9%8A%D9%87-%D8%A8%D8%A7%D9%84%D8%AA%D9%82%D8%B3%D9%8A%D8%B7-%D9%82%D8%B3%D8%B7-%D9%8A%D8%A8%D8%AF%D8%A7%D8%A1-%D9%85%D9%86-750-%D8%B4%D9%87%D8%B1%D9%8A%D8%A7-ID186579143.html', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'توك توك', 'توك توك بجاج هندي جديد', 'سوق التكاتك (متوسط معارض)', (SELECT financier_id FROM financiers WHERE name='معارض/مشروعي'), 'تقدير مقال (نطاق سعري)', FALSE, 140000, 175000, 0, 0, NULL, NULL, 0, 'المقال: كاش 140 ألف مقابل 175–185 ألف بالتقسيط؛ المدة والمقدم غير مذكورين (أُخذ الحد الأدنى)', 'عرب موتو - أسعار التكاتك 2026', 'https://www.3rbmoto.com/2023/09/as3ar-takatik-fi-masr.html', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'تقسيط بنكي عبر الوكيل', 'تويوتا كورولا 2023 GR B 74', 'المصرية للسيارات', (SELECT financier_id FROM financiers WHERE name='تقسيط بنكي'), 'ناتج حاسبة رسمية', FALSE, 800000, NULL, 0, 0, 60, 18667, 0, 'الحاسبة تعلن فائدة 7% + مصاريف 2.5% + تأمين 2.9% سنويًا (غير محسوب هنا)؛ المقدم الافتراضي غير ظاهر (افتُرض 0) والمدة الافتراضية 60 شهر. القسط يطابق فائدة ثابتة 8% سنويًا', 'المصرية للسيارات - حاسبة التقسيط', 'https://elmasria-auto.com/ar/Installment/683?type=1', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'تقسيط بنكي عبر الوكيل', 'كيا 1.6 A/T Top Line 2022', 'المصرية للسيارات', (SELECT financier_id FROM financiers WHERE name='تقسيط بنكي'), 'ناتج حاسبة رسمية', FALSE, 669900, NULL, 0, 0, 60, 15631, 0, 'الحاسبة تعلن فائدة 7% + مصاريف 2.5% + تأمين 2.9% سنويًا (غير محسوب هنا)؛ المقدم الافتراضي غير ظاهر (افتُرض 0) والمدة الافتراضية 60 شهر. القسط يطابق فائدة ثابتة 8% سنويًا', 'المصرية للسيارات - حاسبة التقسيط', 'https://www.elmasria-auto.com/ar/Installment/887?type=1', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'تقسيط بنكي عبر الوكيل', 'هيونداي أكسنت RB GL 2024', 'المصرية للسيارات', (SELECT financier_id FROM financiers WHERE name='تقسيط بنكي'), 'ناتج حاسبة رسمية', FALSE, 689000, NULL, 0, 0, 60, 16077, 0, 'الحاسبة تعلن فائدة 7% + مصاريف 2.5% + تأمين 2.9% سنويًا (غير محسوب هنا)؛ المقدم الافتراضي غير ظاهر (افتُرض 0) والمدة الافتراضية 60 شهر. القسط يطابق فائدة ثابتة 8% سنويًا', 'المصرية للسيارات - حاسبة التقسيط', 'https://elmasriaportal-p.devsmartly.com/ar/Installment/1520?type=1', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'مستعمل بالتقسيط', 'MG ZS 2026 مستعملة 10,000 كم', 'إعلان على كونتكت كارز', (SELECT financier_id FROM financiers WHERE name='غير محدد'), 'إعلان حقيقي', FALSE, NULL, NULL, 375000, 0, 60, 12133, 0, 'السعر الكاش ''قابل للتفاوض'' فمش ممكن نحسب الفايدة', 'ContactCars', 'https://www.contactcars.com/ar/used-cars/mg-zs/1e423b672638', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'شقق - تقسيط مطور', 'شقة 113م + جاردن - كمبوند صن كابيتال، حدائق أكتوبر', 'مطور/مسوق عقاري', (SELECT financier_id FROM financiers WHERE name='المطور'), 'إعلان حقيقي', FALSE, NULL, 9000000, 900000, 0, 96, 84375, 0, 'سعر الإعلان هو سعر التقسيط؛ السعر الكاش غير منشور فالفايدة مدفونة في السعر. قارني عمود ''فرق عن سعر الإعلان'' للتأكد من اتساق الأرقام', 'عقارماب', 'https://aqarmap.com.eg/ar/listing/6896032-for-sale/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'شقق - تقسيط مطور', 'شقة 104م - نيوم المستقبل سيتي', 'مطور/مسوق عقاري', (SELECT financier_id FROM financiers WHERE name='المطور'), 'إعلان حقيقي', FALSE, NULL, 6000000, 600000, 0, 144, 37500, 0, 'سعر الإعلان هو سعر التقسيط؛ السعر الكاش غير منشور فالفايدة مدفونة في السعر. قارني عمود ''فرق عن سعر الإعلان'' للتأكد من اتساق الأرقام', 'بيوت مصر', 'https://www.bayut.eg/%D8%AA%D9%81%D8%A7%D8%B5%D9%8A%D9%84-503891815/%D8%A7%D9%84%D8%B9%D9%82%D8%A7%D8%B1.html', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'شقق - تقسيط مطور', 'شقة 130م - كايت ريزيدنس، 6 أكتوبر', 'مطور/مسوق عقاري', (SELECT financier_id FROM financiers WHERE name='المطور'), 'إعلان حقيقي', FALSE, NULL, 6200000, 620000, 0, 120, 46500, 0, 'سعر الإعلان هو سعر التقسيط؛ السعر الكاش غير منشور فالفايدة مدفونة في السعر. قارني عمود ''فرق عن سعر الإعلان'' للتأكد من اتساق الأرقام', 'بيوت مصر', 'https://www.bayut.eg/%D8%AA%D9%81%D8%A7%D8%B5%D9%8A%D9%84-503886970/%D8%A7%D9%84%D8%B9%D9%82%D8%A7%D8%B1.html', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'شقق - تقسيط مطور', 'شقة 177م - كايت ريزيدنس، 6 أكتوبر', 'مطور/مسوق عقاري', (SELECT financier_id FROM financiers WHERE name='المطور'), 'إعلان حقيقي', FALSE, NULL, 9500000, 950000, 0, 120, 67083, 0, 'سعر الإعلان هو سعر التقسيط؛ السعر الكاش غير منشور فالفايدة مدفونة في السعر. قارني عمود ''فرق عن سعر الإعلان'' للتأكد من اتساق الأرقام', 'بيوت مصر', 'https://www.bayut.eg/%D8%AA%D9%81%D8%A7%D8%B5%D9%8A%D9%84-503887045/%D8%A7%D9%84%D8%B9%D9%82%D8%A7%D8%B1.html', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'شقق - تقسيط مطور', 'شقة 108م - شابترز R8، العاصمة الإدارية', 'مطور/مسوق عقاري', (SELECT financier_id FROM financiers WHERE name='المطور'), 'إعلان حقيقي', FALSE, NULL, 3420792, 342079, 0, 120, 25655, 0, 'سعر الإعلان هو سعر التقسيط؛ السعر الكاش غير منشور فالفايدة مدفونة في السعر. قارني عمود ''فرق عن سعر الإعلان'' للتأكد من اتساق الأرقام', 'بيوت مصر', 'https://www.bayut.eg/%D8%AA%D9%81%D8%A7%D8%B5%D9%8A%D9%84-503857965/%D8%A7%D9%84%D8%B9%D9%82%D8%A7%D8%B1.html', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'شقق - تقسيط مطور', 'شقة 93م - Abrag One، حدائق أكتوبر', 'مطور/مسوق عقاري', (SELECT financier_id FROM financiers WHERE name='المطور'), 'إعلان حقيقي', FALSE, NULL, 2479000, 123950, 0, 120, 19000, 0, 'سعر الإعلان هو سعر التقسيط؛ السعر الكاش غير منشور فالفايدة مدفونة في السعر. قارني عمود ''فرق عن سعر الإعلان'' للتأكد من اتساق الأرقام', 'بيوت مصر', 'https://www.bayut.eg/%D8%AA%D9%81%D8%A7%D8%B5%D9%8A%D9%84-503855182/%D8%A7%D9%84%D8%B9%D9%82%D8%A7%D8%B1.html', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='دهب وشبكة'), 'سبائك ومشغولات', 'سبيكة دهب 10 جرام عيار 24', 'سوق الصاغة', (SELECT financier_id FROM financiers WHERE name='ممنوع عبر التمويل الاستهلاكي'), 'قرار تنظيمي + سعر مرجعي', FALSE, 72850, NULL, 0, 0, NULL, NULL, 0, 'الرقابة المالية حظرت تمويل الذهب والفضة عبر شركات التمويل الاستهلاكي (تعميم 16 سبتمبر 2026) والمركزي منع تمويل البنوك لها. السعر بتاريخ 29 أكتوبر 2026', 'القاهرة مباشر + الغد', 'https://www.alghad.tv/%D8%A7%D8%AE%D8%A8%D8%A7%D8%B1-%D8%A7%D9%84%D8%BA%D8%AF/news/%D9%85%D8%B5%D8%B1-%D8%AA%D9%86%D9%87%D9%8A-%D8%B9%D8%B5%D8%B1-%D8%A7%D9%84%D8%B0%D9%87%D8%A8-%D8%A8%D8%A7%D9%84%D8%AA%D9%82%D8%B3%D9%8A%D8%B7-%D9%85%D9%86-%D8%A7%D9%84%D8%B1%D8%A7%D8%A8%D8%AD-%D9%88%D9%85%D9%86-%D8%A7%D9%84%D8%AE%D8%A7%D8%B3%D8%B1', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أجهزة منزلية'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - بطاقة البنك الأهلي 10 شهر', 'رنين', (SELECT financier_id FROM financiers WHERE name='البنك الأهلي المصري'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 1200, 10, 1000, 0, 'بدون فوائد وبدون مقدم + مصاريف إدارية 12% (افتُرض دفعها مقدمًا) - شروط أكتوبر 2026', 'رنين - الشروط والأحكام', 'https://www.raneen.com/ar/terms_and_conditions', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أجهزة منزلية'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - بطاقة البنك الأهلي 12 شهر', 'رنين', (SELECT financier_id FROM financiers WHERE name='البنك الأهلي المصري'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 1400.0, 12, 833.333333, 0, 'بدون فوائد وبدون مقدم + مصاريف إدارية 14% (افتُرض دفعها مقدمًا) - شروط أكتوبر 2026', 'رنين - الشروط والأحكام', 'https://www.raneen.com/ar/terms_and_conditions', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أجهزة منزلية'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - بطاقة البنك الأهلي 18 شهر', 'رنين', (SELECT financier_id FROM financiers WHERE name='البنك الأهلي المصري'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 2000, 18, 555.555556, 0, 'بدون فوائد وبدون مقدم + مصاريف إدارية 20% (افتُرض دفعها مقدمًا) - شروط أكتوبر 2026', 'رنين - الشروط والأحكام', 'https://www.raneen.com/ar/terms_and_conditions', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أجهزة منزلية'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - بطاقة البنك الأهلي 24 شهر', 'رنين', (SELECT financier_id FROM financiers WHERE name='البنك الأهلي المصري'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 2500, 24, 416.666667, 0, 'بدون فوائد وبدون مقدم + مصاريف إدارية 25% (افتُرض دفعها مقدمًا) - شروط أكتوبر 2026', 'رنين - الشروط والأحكام', 'https://www.raneen.com/ar/terms_and_conditions', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أجهزة منزلية'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - بطاقة البنك الأهلي 36 شهر', 'رنين', (SELECT financier_id FROM financiers WHERE name='البنك الأهلي المصري'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 3400.0, 36, 277.777778, 0, 'بدون فوائد وبدون مقدم + مصاريف إدارية 34% (افتُرض دفعها مقدمًا) - شروط أكتوبر 2026', 'رنين - الشروط والأحكام', 'https://www.raneen.com/ar/terms_and_conditions', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - موجو 6 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 1000, 6, 1666.666667, 0, 'بدون فوائد + مصاريف إدارية 10% تُدفع مرة واحدة عند التعاقد', 'الأندلس للأثاث - شروط موجو', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - موجو 9 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 1000, 9, 1111.111111, 0, 'بدون فوائد + مصاريف إدارية 10% تُدفع مرة واحدة عند التعاقد', 'الأندلس للأثاث - شروط موجو', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - موجو 12 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 1600, 12, 833.333333, 0, 'بدون فوائد + مصاريف إدارية 16% تُدفع مرة واحدة عند التعاقد', 'الأندلس للأثاث - شروط موجو', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - موجو 24 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 0, 24, 566.666667, 0, '1.5% شهريًا ثابتة على أصل المبلغ، بدون مقدم', 'الأندلس للأثاث - شروط موجو', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - موجو 36 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 0, 36, 427.777778, 0, '1.5% شهريًا ثابتة على أصل المبلغ، بدون مقدم', 'الأندلس للأثاث - شروط موجو', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - أمان 12 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 0, 12, 1016.666667, 0, '22% سنويًا ثابتة تُقسّط مع المبلغ، بدون مقدم وبدون مصاريف', 'الأندلس للأثاث - شروط أمان', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - أمان 24 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 0, 24, 600, 0, '22% سنويًا ثابتة تُقسّط مع المبلغ، بدون مقدم وبدون مصاريف', 'الأندلس للأثاث - شروط أمان', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - أمان 36 شهر', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 0, 36, 461.111111, 0, '22% سنويًا ثابتة تُقسّط مع المبلغ، بدون مقدم وبدون مصاريف', 'الأندلس للأثاث - شروط أمان', 'https://www.andalusfurniture.com/bedroom2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'سيناريو شروط رسمية - صيانة وإطارات', 'إطارات بـ10,000 ج - بطاقات البنوك (الأهلي/CIB/مصر...) 12 شهر', 'بلاك سيركلز', (SELECT financier_id FROM financiers WHERE name='بطاقات البنوك (الأهلي/CIB/مصر...)'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 500, 12, 833.333333, 0, 'بدون فوائد + مصاريف إدارية 5%', 'Blackcircles Egypt - طرق الدفع', 'https://www.blackcircles.com.eg/ar/faq/payment-and-pricing-infos/how-do-i-pay-for-my-tires', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'سيناريو شروط رسمية - صيانة وإطارات', 'إطارات بـ10,000 ج - بطاقات البنوك (الأهلي/CIB/مصر...) 18 شهر', 'بلاك سيركلز', (SELECT financier_id FROM financiers WHERE name='بطاقات البنوك (الأهلي/CIB/مصر...)'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 700.0, 18, 555.555556, 0, 'بدون فوائد + مصاريف إدارية 7%', 'Blackcircles Egypt - طرق الدفع', 'https://www.blackcircles.com.eg/ar/faq/payment-and-pricing-infos/how-do-i-pay-for-my-tires', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'سيناريو شروط رسمية - صيانة وإطارات', 'إطارات بـ10,000 ج - بريميوم كارد 10 شهر', 'بلاك سيركلز', (SELECT financier_id FROM financiers WHERE name='بريميوم كارد'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 400, 10, 1000, 0, 'بدون فوائد + مصاريف إدارية 4%', 'Blackcircles Egypt - طرق الدفع', 'https://www.blackcircles.com.eg/ar/faq/payment-and-pricing-infos/how-do-i-pay-for-my-tires', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'سيناريو شروط رسمية', 'مشتريات 10,000 ج - تقسيط بالهاتف البنك الأهلي 6 شهور', 'أي تاجر', (SELECT financier_id FROM financiers WHERE name='البنك الأهلي المصري'), 'سيناريو محسوب من شروط رسمية', TRUE, 10000, NULL, 0, 845, 6, 1666.666667, 0, 'عمولة تقسيط 8.45% لمدة 6 شهور (بتترد في فترات الحملات فقط)', 'بنكي جيت - الأهلي', 'https://www.bankygate.com/76954', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy A06 (4+64GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 4750, NULL, 0, 0, 24, 198, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy A07 (4+128GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 5700, NULL, 0, 0, 24, 238, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy A16 (8+256GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 9599, NULL, 0, 0, 24, 400, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy A17 (6+128GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 8190, NULL, 0, 0, 24, 341, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy A26 5G (8+256GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 14600, NULL, 0, 0, 24, 608, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy A36 5G (8+256GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 18100, NULL, 0, 0, 24, 754, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy A56 5G (12+256GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 24480, NULL, 0, 0, 24, 1020, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy S25 Plus (12+256GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 50050, NULL, 0, 0, 24, 2085, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy S25 Ultra (12+256GB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 65500, NULL, 0, 0, 24, 2729, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'Galaxy S25 Ultra (12+1TB)', 'Samsung مصر (الموقع الرسمي)', (SELECT financier_id FROM financiers WHERE name='InBank'), 'عرض حقيقي منشور', FALSE, 83300, NULL, 0, 0, 24, 3471, 0, 'الصفحة بتعرض السعر الكاش والقسط الشهري؛ عدد الشهور مش مكتوب لكن القسط = الكاش ÷ 24 في كل المنتجات (يعني 24 شهر بدون فوائد)', 'Samsung Egypt - عروض تقسيط الموبايلات', 'https://www.samsung.com/eg/mobile-installments-promo/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'سامسونج جالكسي A27 (8+128GB) 5G', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 19899, NULL, 0, 0, 3, 6633, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - موبايلات', 'https://www.amanstores.com/ar/mobiles-and-tablets/mobiles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'إنفينيكس هوت 70 (8+256GB)', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 16320, NULL, 0, 0, 3, 5440, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - موبايلات', 'https://www.amanstores.com/ar/mobiles-and-tablets/mobiles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'شاومي ريدمي 17 (6+256GB) 5G', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 15999, NULL, 0, 0, 3, 5333, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - موبايلات', 'https://www.amanstores.com/ar/mobiles-and-tablets/mobiles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'هونر X7e بلس (6+128GB) 5G', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 15999, NULL, 0, 0, 3, 5333, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - موبايلات', 'https://www.amanstores.com/ar/mobiles-and-tablets/mobiles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل', 'ريلمي C100i (4+64GB)', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 9599, NULL, 0, 0, 3, 3199.67, 0, 'علامة ''0•0•0 | ثلاث أشهر'' مفسرة كـ: 0 مقدم / 0 فوائد / 0 مصاريف على 3 شهور', 'أمان ستورز - موبايلات', 'https://www.amanstores.com/ar/mobiles-and-tablets/mobiles/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'موبايل - مقارنة سعر', 'سامسونج جالكسي A56 (12+256GB) 5G', 'بي تك', (SELECT financier_id FROM financiers WHERE name='—'), 'سعر كاش فقط (للمقارنة)', FALSE, 30650, NULL, 0, 0, NULL, NULL, 0, 'نفس الموديل سعره 24,480 على موقع سامسونج الرسمي مع تقسيط 24 شهر بدون فوائد — يعني بي تك أغلى بحوالي 25% قبل أي تقسيط', 'بي تك', 'https://btech.com/ar/p/samsung-galaxy-a56-256gb-12gb-ram-5g-dual-sim-lightgrey', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - كاش', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='—'), 'سعر كاش (مرجع)', FALSE, 304380, NULL, 0, 0, NULL, NULL, 0, 'شامل ضريبة 14%', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 1 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 88282, 0, 12, 15385, 65465, 'مقدم + قسط شهري + قسط سنوي 65,465 ج (مفترض بيتدفع آخر كل سنة) × 1. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 2 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 56328, 0, 24, 10779, 57878, 'مقدم + قسط شهري + قسط سنوي 28,939 ج (مفترض بيتدفع آخر كل سنة) × 2. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 3 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 53284, 0, 36, 7667, 80424, 'مقدم + قسط شهري + قسط سنوي 26,808 ج (مفترض بيتدفع آخر كل سنة) × 3. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 4 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 50264, 0, 48, 6162, 103584, 'مقدم + قسط شهري + قسط سنوي 25,896 ج (مفترض بيتدفع آخر كل سنة) × 4. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 5 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 44153, 0, 60, 5410, 124890, 'مقدم + قسط شهري + قسط سنوي 24,978 ج (مفترض بيتدفع آخر كل سنة) × 5. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 6 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 42636, 0, 72, 4880, 144396, 'مقدم + قسط شهري + قسط سنوي 24,066 ج (مفترض بيتدفع آخر كل سنة) × 6. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 7 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 41719, 0, 84, 4538, 159964, 'مقدم + قسط شهري + قسط سنوي 22,852 ج (مفترض بيتدفع آخر كل سنة) × 7. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'عضوية نادي', 'عضوية نادي الرحاب - تقسيط 8 سنة', 'نادي الرحاب', (SELECT financier_id FROM financiers WHERE name='النادي'), 'عرض حقيقي منشور', FALSE, 304380, NULL, 41109, 0, 96, 4321, 175472, 'مقدم + قسط شهري + قسط سنوي 21,934 ج (مفترض بيتدفع آخر كل سنة) × 8. الفايدة السنوية هنا محسوبة بالتدفقات النقدية (IRR) في بايثون', 'مشاريع ايجي (تحديث 14 فبراير 2026)', 'https://projectsegy.com/al-rehab-club-subscription-price/', '2026-02-14'),
((SELECT sector_id FROM sectors WHERE name_ar='تعليم'), 'مدارس حكومية', 'مصروفات حكومي - حضانة حتى تانية إعدادي', 'وزارة التربية والتعليم', (SELECT financier_id FROM financiers WHERE name='—'), 'عرض حقيقي منشور', FALSE, 320, NULL, 255, 0, 1, 65, 0, 'قسطين: الأول 1 أكتوبر والتاني من 1 فبراير — بدون أي زيادة', 'الوطن (13 سبتمبر 2026)', 'https://www.elwatannews.com/news/details/8357382', '2026-09-13'),
((SELECT sector_id FROM sectors WHERE name_ar='تعليم'), 'مدارس حكومية', 'مصروفات حكومي - أولى ثانوي عام', 'وزارة التربية والتعليم', (SELECT financier_id FROM financiers WHERE name='—'), 'عرض حقيقي منشور', FALSE, 545, NULL, 430, 0, 1, 115, 0, 'قسطين: الأول 1 أكتوبر والتاني من 1 فبراير — بدون أي زيادة', 'الوطن (13 سبتمبر 2026)', 'https://www.elwatannews.com/news/details/8357382', '2026-09-13'),
((SELECT sector_id FROM sectors WHERE name_ar='تعليم'), 'مدارس حكومية', 'مصروفات حكومي - تانية وتالتة ثانوي عام', 'وزارة التربية والتعليم', (SELECT financier_id FROM financiers WHERE name='—'), 'عرض حقيقي منشور', FALSE, 530, NULL, 415, 0, 1, 115, 0, 'قسطين: الأول 1 أكتوبر والتاني من 1 فبراير — بدون أي زيادة', 'الوطن (13 سبتمبر 2026)', 'https://www.elwatannews.com/news/details/8357382', '2026-09-13'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'سيناريو شروط رسمية', 'عمرة 7 أيام 30,000 ج - بطاقة بنك مصر عبر Skyhawk tours 12 شهر', 'Skyhawk tours', (SELECT financier_id FROM financiers WHERE name='بنك مصر'), 'سيناريو: سعر 2026 + شروط قديمة (2023)', TRUE, 30000, NULL, 0, 1725, 12, 2500, 0, 'السعر: أقل برنامج 7 أيام (البنكر، 24 سبتمبر 2026). الشروط: بدون فوائد + مصاريف إدارية 5.75% (المال، مارس 2023 — ممكن تكون اتغيرت)', 'البنكر + جريدة المال', 'https://almalnews.com/1499750/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'سيناريو شروط رسمية', 'عمرة 7 أيام 30,000 ج - بطاقة بنك مصر عبر Travco tours 12 شهر', 'Travco tours', (SELECT financier_id FROM financiers WHERE name='بنك مصر'), 'سيناريو: سعر 2026 + شروط قديمة (2023)', TRUE, 30000, NULL, 0, 3540, 12, 2500, 0, 'السعر: أقل برنامج 7 أيام (البنكر، 24 سبتمبر 2026). الشروط: بدون فوائد + مصاريف إدارية 11.80% (المال، مارس 2023 — ممكن تكون اتغيرت)', 'البنكر + جريدة المال', 'https://almalnews.com/1499750/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'سيناريو شروط رسمية', 'عمرة 7 أيام 30,000 ج - بطاقة بنك مصر عبر Skyhawk tours 36 شهر', 'Skyhawk tours', (SELECT financier_id FROM financiers WHERE name='بنك مصر'), 'سيناريو: سعر 2026 + شروط قديمة (2023)', TRUE, 30000, NULL, 0, 6825, 36, 833.333333, 0, 'السعر: أقل برنامج 7 أيام (البنكر، 24 سبتمبر 2026). الشروط: بدون فوائد + مصاريف إدارية 22.75% (المال، مارس 2023 — ممكن تكون اتغيرت)', 'البنكر + جريدة المال', 'https://almalnews.com/1499750/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'سيناريو شروط رسمية', 'عمرة 7 أيام 30,000 ج - بطاقة بنك مصر عبر Travco tours 36 شهر', 'Travco tours', (SELECT financier_id FROM financiers WHERE name='بنك مصر'), 'سيناريو: سعر 2026 + شروط قديمة (2023)', TRUE, 30000, NULL, 0, 8550, 36, 833.333333, 0, 'السعر: أقل برنامج 7 أيام (البنكر، 24 سبتمبر 2026). الشروط: بدون فوائد + مصاريف إدارية 28.50% (المال، مارس 2023 — ممكن تكون اتغيرت)', 'البنكر + جريدة المال', 'https://almalnews.com/1499750/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='علاج وأسنان'), 'زراعة أسنان', 'زراعة سن واحد (سعر البداية)', 'مراكز آرتي سمايل', (SELECT financier_id FROM financiers WHERE name='العيادة'), 'سعر حقيقي + شروط معلنة (القسط محسوب)', FALSE, 10000, NULL, 0, 0, 12, 833.333333, 0, 'السعر يبدأ من 10,000 ج؛ الصفحة بتقول تقسيط حتى 12 شهر ''بدون فوائد'' (الشروط التفصيلية غير منشورة)', 'آرتي سمايل (تحديث 28 سبتمبر 2026)', 'https://www.arty-smile.com/%D8%B2%D8%B1%D8%A7%D8%B9%D8%A9-%D8%A7%D9%84%D8%A7%D8%B3%D9%86%D8%A7%D9%86-%D8%A8%D8%A7%D9%84%D8%AA%D9%82%D8%B3%D9%8A%D8%B7-%D9%81%D9%89-%D9%85%D8%B5%D8%B1/', '2026-09-28'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'سيناريو شروط رسمية', 'بجاج بوكسر 150 سي سي موديل 2027 - أمان 12 شهر', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سيناريو: سعر حقيقي + شروط أمان المنشورة', TRUE, 61000, NULL, 0, 0, 12, 6201.666667, 0, 'السعر من أمان ستورز؛ الشروط (22% سنويًا ثابتة بدون مقدم) منشورة عند تاجر أثاث وممكن تختلف للموتوسيكلات', 'أمان ستورز + الأندلس للأثاث', 'https://www.amanstores.com/ar/motorcycle/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'سيناريو شروط رسمية', 'بجاج بوكسر 150 سي سي موديل 2027 - أمان 24 شهر', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سيناريو: سعر حقيقي + شروط أمان المنشورة', TRUE, 61000, NULL, 0, 0, 24, 3660, 0, 'السعر من أمان ستورز؛ الشروط (22% سنويًا ثابتة بدون مقدم) منشورة عند تاجر أثاث وممكن تختلف للموتوسيكلات', 'أمان ستورز + الأندلس للأثاث', 'https://www.amanstores.com/ar/motorcycle/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'سيناريو شروط رسمية', 'هوجين بوكسر - أمان 24 شهر', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سيناريو: سعر حقيقي + شروط أمان المنشورة', TRUE, 52000, NULL, 0, 0, 24, 3120, 0, 'السعر من أمان ستورز؛ الشروط (22% سنويًا ثابتة بدون مقدم) منشورة عند تاجر أثاث وممكن تختلف للموتوسيكلات', 'أمان ستورز + الأندلس للأثاث', 'https://www.amanstores.com/ar/motorcycle/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'سيناريو شروط رسمية', 'دايون 4 استيراد بالكامل - أمان 36 شهر', 'أمان ستورز', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'سيناريو: سعر حقيقي + شروط أمان المنشورة', TRUE, 48000, NULL, 0, 0, 36, 2213.333333, 0, 'السعر من أمان ستورز؛ الشروط (22% سنويًا ثابتة بدون مقدم) منشورة عند تاجر أثاث وممكن تختلف للموتوسيكلات', 'أمان ستورز + الأندلس للأثاث', 'https://www.amanstores.com/ar/motorcycle/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال سما - موديل 71', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 38800, NULL, 0, 0, 36, 1660, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال شوكولاتة - موديل 72', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 38800, NULL, 0, 0, 36, 1660, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال ليزر ميني - موديل 74', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 38800, NULL, 0, 0, 36, 1660, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال مرايا بيضاوي - موديل 60', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 39200, NULL, 0, 0, 36, 1677, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال الغيطاني - موديل 62', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 39200, NULL, 0, 0, 36, 1677, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال إنستا - موديل 66', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 39200, NULL, 0, 0, 36, 1677, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال سونتج - موديل 63', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 39500, NULL, 0, 0, 36, 1690, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال أسلغ أرابيسك - موديل 59', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 36800, NULL, 0, 0, 36, 1575, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال رقية - موديل 68', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 36800, NULL, 0, 0, 36, 1575, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال أبليك - موديل 61', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 38400, NULL, 0, 0, 36, 1643, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال ريد نايت - موديل 69', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 38400, NULL, 0, 0, 36, 1643, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة أطفال', 'غرفة أطفال زاوية ميني - موديل 70', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 38400, NULL, 0, 0, 36, 1643, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - غرفة أطفال', 'https://www.andalusfurniture.com/kids/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه كاس العالم - موديل 34', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 39900, NULL, 0, 0, 36, 1707, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه بيرونا - موديل 33', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 39900, NULL, 0, 0, 36, 1707, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه موديل 1', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 47300, NULL, 0, 0, 36, 2024, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه فيوري - موديل 40', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 52000, NULL, 0, 0, 36, 2225, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه كارولينا - موديل 35', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 54600, NULL, 0, 0, 36, 2336, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه نيفادا - موديل 36', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 54600, NULL, 0, 0, 36, 2336, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه موديل 25', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 38600, NULL, 0, 0, 36, 1652, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه موديل 5', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 39600, NULL, 0, 0, 36, 1694, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه موديل 12', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 40600, NULL, 0, 0, 36, 1737, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه موديل 6', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 40900, NULL, 0, 0, 36, 1750, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه موديل 14', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 40900, NULL, 0, 0, 36, 1750, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أنتريه', 'أنتريه موديل 10', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='موجو MOGO'), 'عرض حقيقي منشور', FALSE, 41100, NULL, 0, 0, 36, 1759, 0, 'بدون مقدم؛ الموقع يذكر أن الأرقام تقريبية', 'الأندلس للأثاث - أنتريه', 'https://www.andalusfurniture.com/living2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 106', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 16700, NULL, 0, 0, 12, 1698, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 106', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 16700, NULL, 0, 0, 24, 1002, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 106', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 16700, NULL, 0, 0, 36, 771, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 87', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 23800, NULL, 0, 0, 12, 2420, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 87', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 23800, NULL, 0, 0, 24, 1428, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 87', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 23800, NULL, 0, 0, 36, 1098, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 61', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 45500, NULL, 0, 0, 12, 4626, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 61', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 45500, NULL, 0, 0, 24, 2730, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 61', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 45500, NULL, 0, 0, 36, 2099, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 21', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 47400, NULL, 0, 0, 12, 4819, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 21', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 47400, NULL, 0, 0, 24, 2844, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 21', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 47400, NULL, 0, 0, 36, 2186, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 48', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 50000, NULL, 0, 0, 12, 5084, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 48', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 50000, NULL, 0, 0, 24, 3000, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 48', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 50000, NULL, 0, 0, 36, 2306, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 16', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 50500, NULL, 0, 0, 12, 5135, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 16', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 50500, NULL, 0, 0, 24, 3030, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'غرفة سفرة', 'غرفة سفرة موديل 16', 'الأندلس للأثاث', (SELECT financier_id FROM financiers WHERE name='أمان Aman'), 'عرض حقيقي منشور', FALSE, 50500, NULL, 0, 0, 36, 2329, 0, 'قسط أمان بدون مقدم (22% سنويًا ثابتة)', 'الأندلس للأثاث - غرف السفرة', 'https://www.andalusfurniture.com/dining2/', '2026-10-29');

INSERT INTO plan_terms (sector_id, financier, financier_type, applies_to, duration, interest, down_payment, admin_fees, notes, date_text, source_name, source_url) VALUES
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'فرصة Forsa', 'شركة تمويل استهلاكي', 'أجهزة Samsung', 'حتى 24 شهر', '0%', '0%', '0%', 'عرض لفترة محدودة', '2026-10-15', 'بنكي جيت', 'https://www.bankygate.com/78206'),
((SELECT sector_id FROM sectors WHERE name_ar='موبايلات وإلكترونيات'), 'البنك الأهلي المصري', 'بنك', 'تقسيط بالهاتف - بطاقات ائتمان', '6 شهور', '0% (حملة)', '0%', '8.45% عمولة تُرد في الحملة', 'حملة 1–20 سبتمبر 2026', '2026-09', 'بنكي جيت', 'https://www.bankygate.com/76954'),
((SELECT sector_id FROM sectors WHERE name_ar='أجهزة منزلية'), 'البنك الأهلي المصري عبر رنين', 'بنك', 'كل المنتجات', '10/12/18/24/36 شهر', '0%', '0%', '12%/14%/20%/25%/34%', 'شروط أكتوبر 2026', '2026-10', 'رنين', 'https://www.raneen.com/ar/terms_and_conditions'),
((SELECT sector_id FROM sectors WHERE name_ar='أجهزة منزلية'), 'البنك الأهلي / CIB / بنك مصر', 'بنك', 'تكييفات (العالمية للتكييف)', 'حتى 18 شهر (مصر حتى 12)', '0%', '0%', '0%', 'عرض وكيل', '2026-07', 'العالمية للتكييف', 'https://alalamiaa.com/%D8%AA%D9%83%D9%8A%D9%8A%D9%81%D8%A7%D8%AA-%D8%A8%D8%A7%D9%84%D8%AA%D9%82%D8%B3%D9%8A%D8%B7/'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'موجو MOGO', 'شركة تمويل استهلاكي', 'أثاث', '6/9/12 ثم 15–36 شهر', '0% حتى 12 شهر ثم 1.5% شهريًا ثابتة', '0%', '10% (6 و9 شهور) / 16% (12 شهر)', NULL, '2026-10', 'الأندلس للأثاث', 'https://www.andalusfurniture.com/bedroom2/'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'أمان Aman', 'شركة تمويل استهلاكي', 'أثاث', 'حتى 36 شهر', '22% سنويًا ثابتة', '0%', '0%', NULL, '2026-10', 'الأندلس للأثاث', 'https://www.andalusfurniture.com/bedroom2/'),
((SELECT sector_id FROM sectors WHERE name_ar='أثاث ومطابخ'), 'الأندلس للأثاث (عرض)', 'تقسيط مباشر من التاجر', 'أثاث البيت كله', 'غير محدد', '1.5% شهريًا', '0%', '0%', 'عرض حتى 20 سبتمبر 2026', '2026-09', 'الأندلس للأثاث', 'https://www.andalusfurniture.com/24/'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'المصرية للسيارات (تقسيط بنكي)', 'بنك', 'سيارات جديدة', '12–60 شهر', '7% معلنة', '10%', '2.5% + تأمين 2.9% سنويًا', 'القسط في الحاسبة يطابق 8% ثابتة', '2026-10', 'المصرية للسيارات', 'https://elmasria-auto.com/ar/Installment/683?type=1'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'فاليو', 'شركة تمويل استهلاكي', 'تمويل سيارات', 'غير محدد', 'حتى 15% ثابتة', 'غير محدد', 'غير محدد', 'بدون حظر بيع', '2026', 'النادا نيوز', 'https://alnada-devnewswebsite.azurewebsites.net/en/editorial/بفائدة-ثابته-15-فاليو-تطرح-عروض-لشراء-السيارات-بدون-حظر-بيع-1247'),
((SELECT sector_id FROM sectors WHERE name_ar='عربيات'), 'بنك مصر', 'بنك', 'قرض سيارة', 'حتى 120 شهر', 'غير معلن', 'حتى 100% تمويل', 'غير معلن', 'حد أقصى 6 مليون', '2026-04', 'إيجي إن', 'https://www.egyin.com/article/117314'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'هيئة تعاونيات البناء والإسكان', 'حكومي', '229 وحدة سكنية', '5/7/10 سنين', 'غير معلن', '10%', 'غير معلن', 'طرح يوليو 2026', '2026-06', 'مصراوي', 'https://www.masrawy.com/news/realestate-news/details/2026/6/27/3009071'),
((SELECT sector_id FROM sectors WHERE name_ar='عقارات'), 'تمويل عقاري - الإسكان الاجتماعي', 'حكومي', 'شقق إسكان اجتماعي', 'حتى 20 سنة', 'تمويل عقاري مدعم', '25–50 ألف جدية حجز', 'غير معلن', 'قسط 750–1,300 ج (تقديري)', '2026-05', 'تليجراف مصر', 'https://www.egypttelegraph.com/article/247556'),
((SELECT sector_id FROM sectors WHERE name_ar='دهب وشبكة'), 'الرقابة المالية + البنك المركزي', 'قرار تنظيمي', 'سبائك ومشغولات ذهب وفضة وبلاتين', '—', 'ممنوع عبر التمويل الاستهلاكي', '—', '—', 'تعميم 16 سبتمبر 2026', '2026-09-16', 'الغد', 'https://www.alghad.tv/'),
((SELECT sector_id FROM sectors WHERE name_ar='تعليم'), 'بنك مصر', 'بنك', 'مصروفات مدارس وجامعات', '6 شهور', '0%', '0%', '0%', '26 أغسطس – 30 سبتمبر 2026', '2026-09', 'بنوك 24', 'https://www.bnok24.com/2026/09/%D8%A8%D9%86%D9%83-%D9%85%D8%B5%D8%B1-%D9%8A%D8%AA%D9%8A%D8%AD-%D8%AA%D9%82%D8%B3%D9%8A%D8%B7-%D9%85%D8%B5%D8%B1%D9%88%D9%81%D8%A7%D8%AA-%D8%A7%D9%84%D9%85%D8%AF%D8%A7%D8%B1%D8%B3-%D9%88%D8%A7%D9%84-3/'),
((SELECT sector_id FROM sectors WHERE name_ar='تعليم'), 'البنك الأهلي المصري', 'بنك', 'مشتريات العام الدراسي', '6 شهور', '0%', '0%', '0%', 'حملة سبتمبر 2026', '2026-09', 'بنكي جيت', 'https://www.bankygate.com/76954'),
((SELECT sector_id FROM sectors WHERE name_ar='تعليم'), 'فاليو × الجامعة الأمريكية', 'شركة تمويل استهلاكي', 'مصروفات جامعية', '3–6 شهور', '1.45% شهريًا', '0%', '0%', 'بيانات 2023 (قديمة)', '2023-07', 'Egyptian Streets', 'https://egyptianstreets.com/2023/07/26/valu-is-partnering-with-auc-to-offer-financing-plans-for-undergraduate-and-graduate-tuition-fees/'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'بنك فيصل الإسلامي', 'بنك', 'رحلات عمرة', 'حتى 60 شهر', 'مرابحة (العائد غير معلن)', '10% (تمويل حتى 90%)', 'غير معلن', 'تمويل حتى 750 ألف', '2026-05', 'القرار المصري', 'https://alqararalmasry.com/2026/05/13/'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'نقابة العاملين بالبترول', 'جهة عمل/نقابة', 'برامج عمرة', '12 شهر', 'غير مذكور', '50%', 'غير مذكور', 'للعاملين وأسرهم', '2025-12', 'بترو نيوز', 'https://petro-news.com/145220/'),
((SELECT sector_id FROM sectors WHERE name_ar='علاج وأسنان'), 'عيادات جذور الأسنان', 'تقسيط مباشر من التاجر', 'زراعة وتركيبات وتقويم', 'حتى 12 شهر (التيسير)', '0%', 'غير مذكور', 'غير مذكور', NULL, '2026-07', 'عيادات جذور', 'https://rootsdental.net/'),
((SELECT sector_id FROM sectors WHERE name_ar='علاج وأسنان'), 'أدڤا', 'شركة تمويل استهلاكي', 'زراعة أسنان', '6–60 شهر', 'غير معلن', 'غير مذكور', 'غير مذكور', 'بيانات 2024', '2024', 'أدڤا', 'https://advaeg.com/blog/health-ar/'),
((SELECT sector_id FROM sectors WHERE name_ar='لبس وموضة'), 'سيمبل Sympl', 'اشتر الآن وادفع لاحقًا', 'أي مشتريات', '3/4/5 دفعات (حتى 3 شهور)', '0%', 'حسب الخطة', '100 ج ثابتة لكل عملية', NULL, '2026', 'جلود / فينتك جيت', 'https://jlood.com/pages/sympl'),
((SELECT sector_id FROM sectors WHERE name_ar='لبس وموضة'), 'فاليو × أمازون مصر', 'شركة تمويل استهلاكي', 'مشتريات أمازون', '3 شهور', '0%', '0%', '0%', 'عرض لفترة محدودة', '2026-07', 'فينتك جيت', 'https://fintechgate.net/247512'),
((SELECT sector_id FROM sectors WHERE name_ar='مستحضرات تجميل وعطور'), 'فاليو عبر نون', 'شركة تمويل استهلاكي', 'منتجات الجمال', 'حتى 60 شهر', 'غير معلن', '0%', '0%', NULL, '2026', 'نون مصر', 'https://www.noon.com/egypt-ar/beauty/'),
((SELECT sector_id FROM sectors WHERE name_ar='مستحضرات تجميل وعطور'), 'PayNas عبر نون', 'اشتر الآن وادفع لاحقًا', 'منتجات الجمال', '3 شهور', '0%', 'غير مذكور', 'غير مذكور', NULL, '2026', 'نون مصر', 'https://www.noon.com/egypt-ar/beauty/'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'المنصور للموتوسيكلات', 'تقسيط مباشر من التاجر', 'موتوسيكلات (الإسكندرية)', '24 شهر (حتى 5 سنين بأنظمة أخرى)', 'غير معلن', '30%', 'غير معلن', NULL, '2026', 'المنصور', 'https://almansour-motorcycle.com/'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'بنك مصر', 'بنك', 'قرض سكوتر', 'حتى 84 شهر', 'غير معلن', 'حتى 100% تمويل', 'غير معلن', 'حتى 400 ألف', '2026-10', 'سيارات اليوم', 'https://sayaratelyoum.com/motorcycle-instalments'),
((SELECT sector_id FROM sectors WHERE name_ar='موتوسيكلات وتكاتك'), 'كونتكت', 'شركة تمويل استهلاكي', 'موتوسيكلات', 'حتى 3 سنين', 'لم يُنشر', '20%', 'لم تُنشر', NULL, '2026-10', 'سيارات اليوم', 'https://sayaratelyoum.com/motorcycle-instalments'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'جولدز جيم + البنوك', 'بنك', 'اشتراك سنوي (10,000 ج)', '6–12 شهر', 'غير معلن', 'غير مذكور', 'غير مذكور', 'السعر من بيانات 2025', '2026-03', 'البنكنوت', 'https://invest.albanknote.com/golds-gym-egypt-subscription-prices'),
((SELECT sector_id FROM sectors WHERE name_ar='اشتراكات جيم ونوادي'), 'نادي وادي دجلة', 'تقسيط مباشر من التاجر', 'عضوية نادي', 'من 12 شهر', 'غير معلن', 'أحيانًا 0', 'غير معلن', NULL, '2026-10', 'البنكنوت', 'https://invest.albanknote.com/wadi-degla-club-subscription'),
((SELECT sector_id FROM sectors WHERE name_ar='طاقة شمسية وتكييفات'), 'بنك مصر', 'بنك', 'أنظمة طاقة شمسية منزلية', 'حتى 96 شهر', 'تنافسي (غير معلن)', 'غير مذكور', '0% (حتى 30 يوليو 2026)', 'تمويل 6–250 ألف للموظفين', '2026-05', 'التعمير', 'https://eltaameer.com/archives/444558'),
((SELECT sector_id FROM sectors WHERE name_ar='طاقة شمسية وتكييفات'), 'وزارة الكهرباء (مقترح)', 'حكومي', 'محطات شمسية فوق الأسطح', 'غير محدد', '8%', 'غير محدد', 'غير محدد', 'قيد الدراسة', '2026-10', 'سولارابيك', 'https://solarabic.com/'),
((SELECT sector_id FROM sectors WHERE name_ar='تشطيبات وأدوات صحية'), 'فرصة Forsa عبر المشرقي', 'شركة تمويل استهلاكي', 'سيراميك وأدوات صحية', '3 أو 6 شهور', '0%', '0%', '0%', NULL, '2026', 'المشرقي', 'https://mashreqy.com/'),
((SELECT sector_id FROM sectors WHERE name_ar='تشطيبات وأدوات صحية'), 'عمار ديزاين', 'تقسيط مباشر من التاجر', 'تشطيب شقق', '3/6/9/12 شهر', '0%', '0% أو بسيط', '0%', 'قسط من 8,000 ج', '2026', 'عمار ديزاين', 'https://www.emaardesigns.com/tashteeb-biltaqseet'),
((SELECT sector_id FROM sectors WHERE name_ar='قاعات أفراح وتجهيز عرايس'), 'فرصة Forsa عبر WEDDnGo', 'شركة تمويل استهلاكي', 'قاعة وفستان وميكاب وتصوير', '6–12 شهر', '0%', '0%', '0%', 'عرض حتى 31/8', '2026', 'WEDDnGo', 'https://www.weddngo.com/ar/forsa-Installment-offer.html'),
((SELECT sector_id FROM sectors WHERE name_ar='قاعات أفراح وتجهيز عرايس'), 'ميد تقسيط عبر WEDDnGo', 'شركة تمويل استهلاكي', 'كل خدمات الفرح', 'حتى 36 شهر', 'غير معلن', '0%', 'غير معلن', '+ خصم 30%', '2026', 'WEDDnGo', 'https://www.weddngo.com/ar/offer30.html'),
((SELECT sector_id FROM sectors WHERE name_ar='ألعاب وبلايستيشن'), 'أمان ستورز', 'شركة تمويل استهلاكي', 'أجهزة ألعاب', '3 شهور', '0%', '0%', '0%', 'علامة 0•0•0', '2026-10', 'أمان ستورز', 'https://www.amanstores.com/ar/computers-and-gaming/game-consoles/'),
((SELECT sector_id FROM sectors WHERE name_ar='عجل ومستلزمات رياضية'), 'بنك مصر - مبادرة دراجتك صحتك', 'بنك', 'دراجات المبادرة', '6/12/24 شهر', 'غير معلن', 'غير مذكور', 'غير مذكور', 'أقساط 752/399/224 ج (بيانات 2024)', '2024-02', 'مصراوي', 'https://www.masrawy.com/news/news_egypt/details/2024/2/13/2538030/'),
((SELECT sector_id FROM sectors WHERE name_ar='تأمين'), 'المصرية للسيارات (برنامج تأمين)', 'شركة تأمين', 'تأمين شامل على السيارة', 'سنوي', '2.9% من قيمة العربية سنويًا', '—', '—', 'مثال: 4,640 ج/سنة لعربية 800 ألف', '2026-10', 'المصرية للسيارات', 'https://elmasria-auto.com/ar/Installment/683?type=1'),
((SELECT sector_id FROM sectors WHERE name_ar='تأمين'), 'أمان ليك', 'منصة تأمين', 'وثائق تأمين السيارات', 'شهري أو سنوي', 'بدون فوائد عبر البنوك (حسب المنصة)', 'غير مذكور', 'غير مذكور', NULL, '2026-07', 'أمان ليك', 'https://amanleek.com/'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'كونتكت - مناسك', 'شركة تمويل استهلاكي', 'حج وعمرة', 'عمرة حتى 12 شهر / حج حتى 60 شهر', 'غير معلن', '20%', 'غير معلن', NULL, '2026', 'كونتكت', 'https://contact.eg/products/manasik'),
((SELECT sector_id FROM sectors WHERE name_ar='سفر وعمرة وحج'), 'بنك مصر - عمرتك بالتقسيط', 'بنك', 'عمرة عبر شركات سياحة شريكة', '6–36 شهر', '0%', 'غير مذكور', '1% لـ 28.5% حسب الشركة والمدة', 'بيانات مارس 2023', '2023-03', 'جريدة المال', 'https://almalnews.com/1499750/'),
((SELECT sector_id FROM sectors WHERE name_ar='تأمين'), 'مصر لتأمينات الحياة عبر البنك الأهلي (ابن سينا)', 'شركة تأمين', 'تأمين طبي فردي وعائلي', 'سنوي', '—', '—', '—', '5 باقات بحد تغطية 50–300 ألف؛ الأقساط غير منشورة', '2026-10-19', 'بنوك 24', 'https://www.bnok24.com/2026/10/');

INSERT INTO benchmarks (code, indicator, value, source_url) VALUES
('inflation', 'التضخم السنوي - إجمالي الجمهورية (سبتمبر 2026)', 0.128, 'https://qna.org.qa/ar-QA/News-Area/News/2026-10/10/'),
('inflation_urban', 'التضخم السنوي - الحضر (سبتمبر 2026)', 0.139, 'https://arabfinance.com/ar/news/newdetails/48536'),
('inflation_core', 'التضخم الأساسي (سبتمبر 2026)', 0.141, 'https://arabfinance.com/ar/news/newdetails/48536'),
('cd_rate', 'شهادة البنك الأهلي الثابتة 3 سنين', 0.1775, 'https://nl7za.com/');

INSERT INTO calc_plans (name, flat_annual_rate, min_months, max_months, note, source_url, sort_order) VALUES
('موجو (15–36 شهر)', 0.18, 15, 36, '1.5% شهريًا ثابتة على أصل المبلغ، بدون مقدم', 'https://www.andalusfurniture.com/bedroom2/', 1),
('موجو (6–12 شهر بدون فوائد)', 0, 6, 12, 'بدون فوائد + مصاريف إدارية 10% أو 16% مرة واحدة', 'https://www.andalusfurniture.com/bedroom2/', 2),
('أمان', 0.22, 6, 36, '22% سنويًا ثابتة تتقسط مع المبلغ، بدون مقدم ولا مصاريف', 'https://www.andalusfurniture.com/bedroom2/', 3),
('بطاقة البنك الأهلي (عبر رنين)', 0, 10, 36, 'بدون فوائد + مصاريف إدارية حسب المدة (أكتوبر 2026)', 'https://www.raneen.com/ar/terms_and_conditions', 4),
('موقع سامسونج (InBank)', 0, 24, 24, '24 شهر بدون فوائد ولا مصاريف', 'https://www.samsung.com/eg/mobile-installments-promo/', 5),
('قرض عربية بنكي (8% ثابتة)', 0.08, 12, 60, 'القسط في حاسبة المصرية للسيارات بيطابق 8% ثابتة', 'https://elmasria-auto.com/ar/Installment/683?type=1', 6);

INSERT INTO calc_plan_fees (plan_id, up_to_months, fee_pct)
SELECT plan_id, x.m, x.f FROM calc_plans, (VALUES (9, 0.10), (12, 0.16)) AS x(m, f) WHERE name LIKE 'موجو (6%'
UNION ALL
SELECT plan_id, x.m, x.f FROM calc_plans, (VALUES (10, 0.12), (12, 0.14), (18, 0.20), (24, 0.25), (36, 0.34)) AS x(m, f) WHERE name LIKE 'بطاقة البنك الأهلي%';

-- ---------------------------------------------------------------------
-- 7) Views. v_offers = every offer with its numbers computed live.
-- ---------------------------------------------------------------------
CREATE VIEW v_offers AS
WITH b AS (
    SELECT o.*, s.name_ar AS sector, s.name_en AS sector_en,
           f.name AS financier, f.short_name AS financier_short, f.financier_type,
           CASE WHEN o.months IS NOT NULL THEN o.down_payment + o.upfront_fees + o.months * o.monthly_installment
                                               + o.annual_payments_total END AS total_paid
    FROM offers o
    JOIN sectors s USING (sector_id)
    LEFT JOIN financiers f USING (financier_id)
)
SELECT b.*,
       b.total_paid - b.cash_price                                        AS extra_vs_cash,
       ROUND((b.total_paid - b.cash_price) / b.cash_price, 4)              AS extra_pct,
       b.total_paid - b.listed_installment_price                          AS diff_vs_listed_price,
       CASE WHEN b.cash_price IS NOT NULL AND b.months IS NOT NULL THEN
            effective_apr(b.cash_price - b.down_payment - b.upfront_fees, b.monthly_installment, b.months,
                          CASE WHEN b.annual_payments_total > 0 THEN b.annual_payments_total / GREATEST(b.months / 12, 1) ELSE 0 END,
                          CASE WHEN b.annual_payments_total > 0 THEN GREATEST(b.months / 12, 1) ELSE 0 END)
       END                                                                AS apr_effective
FROM b;

-- Only what the public sees: approved + active
CREATE VIEW v_live_offers AS
SELECT v.*,
       (v.apr_effective IS NOT NULL)                       AS has_rate,
       (v.apr_effective IS NOT NULL AND ABS(v.extra_pct) < 0.005) AS is_zero_interest,
       CASE WHEN v.apr_effective IS NULL THEN 'مش محسوبة'
            WHEN ABS(v.extra_pct) < 0.005 THEN '0% — قسّط'
            WHEN v.apr_effective < (SELECT value FROM benchmarks WHERE code = 'cd_rate') THEN 'أقل من الشهادة'
            ELSE 'الكاش أوفر' END                           AS verdict,
       CASE WHEN v.months IS NULL THEN NULL
            WHEN v.months <= 6  THEN '1) حتى 6 شهور'
            WHEN v.months <= 12 THEN '2) 7-12 شهر'
            WHEN v.months <= 24 THEN '3) 13-24 شهر'
            WHEN v.months <= 36 THEN '4) 25-36 شهر'
            ELSE '5) أكتر من 36 شهر' END                    AS duration_bucket
FROM v_offers v
WHERE v.status = 'approved' AND v.is_active;

-- ---------------------------------------------------------------------
-- 8) Power BI views (Get data -> PostgreSQL -> load these, then Refresh)
-- ---------------------------------------------------------------------
CREATE VIEW pbi_offers AS
SELECT offer_id, sector, sector_en, sub_category, item, merchant, financier, financier_short, financier_type,
       data_type, CASE WHEN is_scenario THEN 'سيناريو' ELSE 'عرض حقيقي' END AS offer_kind,
       cash_price, listed_installment_price, down_payment, upfront_fees, months, monthly_installment,
       annual_payments_total, total_paid, extra_vs_cash, extra_pct, apr_effective, verdict, duration_bucket,
       is_zero_interest, has_rate, entry_source, source_name, source_url, date_observed, created_at
FROM v_live_offers;

CREATE VIEW pbi_sector_summary AS
SELECT s.name_ar AS sector, s.name_en AS sector_en,
       COUNT(o.offer_id)                                             AS offers,
       COUNT(o.offer_id) FILTER (WHERE o.has_rate)                   AS offers_with_rate,
       ROUND(AVG(o.extra_pct) FILTER (WHERE o.has_rate), 4)          AS avg_extra_pct,
       ROUND(AVG(o.apr_effective) FILTER (WHERE o.has_rate), 4)      AS avg_apr,
       COUNT(o.offer_id) FILTER (WHERE o.is_zero_interest)           AS zero_interest_offers,
       (SELECT COUNT(*) FROM plan_terms t WHERE t.sector_id = s.sector_id) AS plan_terms
FROM sectors s LEFT JOIN v_live_offers o ON o.sector_id = s.sector_id
GROUP BY s.sector_id, s.name_ar, s.name_en;

CREATE VIEW pbi_financier_summary AS
SELECT financier_short AS financier, financier_type,
       COUNT(*)                                   AS offers,
       ROUND(AVG(apr_effective), 4)               AS avg_apr,
       ROUND(MIN(apr_effective), 4)               AS min_apr,
       ROUND(MAX(apr_effective), 4)               AS max_apr
FROM v_live_offers
WHERE has_rate AND NOT is_zero_interest
GROUP BY financier_short, financier_type;

CREATE VIEW pbi_benchmarks AS SELECT code, indicator, value FROM benchmarks;

-- check
SELECT 'offers' AS t, COUNT(*) FROM offers
UNION ALL SELECT 'live_offers', COUNT(*) FROM v_live_offers
UNION ALL SELECT 'plan_terms', COUNT(*) FROM plan_terms
UNION ALL SELECT 'calc_plans', COUNT(*) FROM calc_plans;
