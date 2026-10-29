-- =====================================================================
-- مشروع التقسيط — أسئلة تجارية (PostgreSQL)
-- بتشتغل على schema installments بعد 00_cloud_setup.sql
-- شغلي كل query لوحدها: ظلليها واضغطي F5
-- =====================================================================
SET search_path TO installments;

-- Q1) نظرة عامة: أرقام الـ KPIs
SELECT COUNT(*)                                                    AS total_offers,
       COUNT(DISTINCT sector)                                      AS sectors,
       COUNT(*) FILTER (WHERE has_rate)                            AS offers_with_rate,
       COUNT(*) FILTER (WHERE has_rate AND is_zero_interest)       AS truly_zero_interest,
       ROUND(AVG(extra_pct) FILTER (WHERE has_rate) * 100, 1)      AS avg_extra_pct,
       ROUND(AVG(apr_effective) FILTER (WHERE has_rate AND NOT is_zero_interest) * 100, 1) AS avg_apr_when_not_zero
FROM v_live_offers;

-- Q2) أنهي قطاع أغلى في التقسيط؟
SELECT sector,
       COUNT(*)                                            AS offers,
       ROUND(AVG(extra_pct) * 100, 1)                      AS avg_extra_pct,
       ROUND(AVG(apr_effective) * 100, 1)                  AS avg_apr_pct,
       ROUND(100.0 * AVG(is_zero_interest::int), 0)        AS pct_zero_interest
FROM v_live_offers
WHERE has_rate
GROUP BY sector
ORDER BY avg_apr_pct DESC;

-- Q3) أنهي شركة تقسيط أغلى؟ (العروض اللي فيها تكلفة بس)
SELECT financier,
       COUNT(*)                              AS offers,
       ROUND(AVG(apr_effective) * 100, 1)    AS avg_apr_pct,
       ROUND(MIN(apr_effective) * 100, 1)    AS min_apr_pct,
       ROUND(MAX(apr_effective) * 100, 1)    AS max_apr_pct
FROM v_live_offers
WHERE has_rate AND NOT is_zero_interest
GROUP BY financier
HAVING COUNT(*) >= 2
ORDER BY avg_apr_pct DESC;

-- Q4) أرخص جهة تقسيط في كل قطاع (Window function)
WITH ranked AS (
    SELECT sector, financier, ROUND(AVG(apr_effective) * 100, 1) AS avg_apr_pct, COUNT(*) AS offers,
           ROW_NUMBER() OVER (PARTITION BY sector ORDER BY AVG(apr_effective)) AS rn
    FROM v_live_offers
    WHERE has_rate
    GROUP BY sector, financier
)
SELECT sector, financier AS cheapest_financier, avg_apr_pct, offers
FROM ranked
WHERE rn = 1
ORDER BY avg_apr_pct, sector;

-- Q5) خدعة "بدون فوائد": عروض فايدتها 0% بس فيها مصاريف إدارية
SELECT item, financier, months,
       ROUND(100 * upfront_fees / cash_price, 2) AS admin_fee_pct,
       ROUND(apr_effective * 100, 1)      AS real_apr_pct
FROM v_live_offers
WHERE upfront_fees > 0 AND has_rate
ORDER BY real_apr_pct DESC;

-- Q6) المدة بتأثر إزاي؟ الزيادة الإجمالية مقابل الفايدة السنوية
SELECT duration_bucket,
       COUNT(*)                              AS offers,
       ROUND(AVG(extra_pct) * 100, 1)        AS avg_extra_pct,
       ROUND(AVG(apr_effective) * 100, 1)    AS avg_apr_pct
FROM v_live_offers
WHERE has_rate AND NOT is_zero_interest
GROUP BY duration_bucket
ORDER BY duration_bucket;

-- Q7) قسّط ولا ادفع كاش؟ (مقارنة بعائد الشهادة البنكية)
SELECT CASE WHEN o.is_zero_interest                 THEN '1) 0% — قسّط وحط الفلوس في شهادة'
            WHEN o.apr_effective < b.value          THEN '2) أقل من عائد الشهادة'
            ELSE                                         '3) أغلى من الشهادة — الكاش أوفر' END AS decision,
       COUNT(*) AS offers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM v_live_offers o
CROSS JOIN (SELECT value FROM benchmarks WHERE code = 'cd_rate') b
WHERE o.has_rate
GROUP BY decision
ORDER BY decision;

-- Q8) نفس المنتج بأكتر من مدة: الفرق بالجنيه بين أقصر وأطول مدة
SELECT item, financier, cash_price,
       MIN(months)                                              AS shortest,
       MAX(months)                                              AS longest,
       MAX(total_paid) FILTER (WHERE months = (SELECT MIN(months) FROM v_live_offers x WHERE x.item = v.item AND x.financier = v.financier)) AS paid_shortest,
       MAX(total_paid) FILTER (WHERE months = (SELECT MAX(months) FROM v_live_offers x WHERE x.item = v.item AND x.financier = v.financier)) AS paid_longest
FROM v_live_offers v
WHERE has_rate
GROUP BY item, financier, cash_price
HAVING COUNT(DISTINCT months) > 1
ORDER BY cash_price DESC;

-- Q9) العقارات: هل سعر الإعلان = مجموع الأقساط؟ (يعني الفايدة مدفونة)
SELECT item,
       listed_installment_price,
       ROUND(100 * down_payment / listed_installment_price, 1) AS down_pct,
       months / 12                                             AS years,
       monthly_installment,
       total_paid,
       diff_vs_listed_price,
       CASE WHEN ABS(diff_vs_listed_price) < 1000 THEN 'السعر = مجموع الأقساط'
            ELSE 'فيه دفعة ناقصة (استلام/دفعات سنوية)' END     AS check_result
FROM v_live_offers
WHERE sector = 'عقارات'
ORDER BY listed_installment_price DESC;

-- Q10) نفس الموبايل في أكتر من متجر: فرق السعر الكاش
SELECT o1.item AS btech_item, o1.cash_price AS btech_cash,
       o2.item AS samsung_item, o2.cash_price AS samsung_cash, o2.months AS samsung_months,
       ROUND(100 * (o1.cash_price - o2.cash_price) / o2.cash_price, 1) AS btech_premium_pct
FROM v_live_offers o1
JOIN v_live_offers o2 ON o2.item ILIKE '%A56%12+256%' AND o2.merchant LIKE 'Samsung%'
WHERE o1.merchant = 'بي تك' AND o1.item LIKE '%A56%';

-- Q11) جودة الداتا: كل قطاع فيه كام عرض حقيقي وكام سيناريو وكام شرط
SELECT s.sector,
       COUNT(o.offer_id) FILTER (WHERE NOT o.is_scenario)        AS real_offers,
       COUNT(o.offer_id) FILTER (WHERE o.is_scenario)    AS scenario_rows,
       (SELECT COUNT(*) FROM plan_terms t WHERE t.sector_id = s.sector_id) AS plan_terms
FROM (SELECT name_ar AS sector, sector_id FROM sectors) s
LEFT JOIN v_live_offers o ON o.sector = s.sector
GROUP BY s.sector, s.sector_id
ORDER BY real_offers DESC;

-- Q12) القطاعات اللي فيها قيود أو حظر قانوني
SELECT s.name_ar AS sector, t.financier, t.interest, t.notes, t.date_text
FROM plan_terms t JOIN sectors s USING (sector_id)
WHERE t.financier_type = 'قرار تنظيمي' OR t.interest LIKE '%ممنوع%';
