-- =============================================================================
--  Retail Sales & Profit Intelligence System
--  File : business_queries.sql
--  All queries run against the STAR schema in data_warehouse.sql
--  Optimised for PostgreSQL 15+
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q01  Monthly Revenue & Profit Trend
--      Shows total net revenue and profit for every calendar month.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dd.year,
    dd.month_num,
    dd.month_name,
    COUNT(DISTINCT fs.order_id)         AS total_orders,
    SUM(fs.quantity)                    AS units_sold,
    ROUND(SUM(fs.net_sales),    2)      AS net_revenue,
    ROUND(SUM(fs.profit),       2)      AS total_profit,
    ROUND(AVG(fs.profit_margin_pct), 2) AS avg_margin_pct
FROM   fact_sales   fs
JOIN   dim_date     dd ON dd.date_sk = fs.order_date_sk
GROUP  BY dd.year, dd.month_num, dd.month_name
ORDER  BY dd.year, dd.month_num;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q02  Top 10 Products by Revenue
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dp.product_name,
    dp.category,
    dp.sub_category,
    ROUND(SUM(fs.net_sales), 2)         AS total_revenue,
    ROUND(SUM(fs.profit),    2)         AS total_profit,
    ROUND(AVG(fs.profit_margin_pct), 2) AS avg_margin_pct,
    SUM(fs.quantity)                    AS units_sold
FROM   fact_sales  fs
JOIN   dim_products dp ON dp.product_sk = fs.product_sk
GROUP  BY dp.product_name, dp.category, dp.sub_category
ORDER  BY total_revenue DESC
LIMIT  10;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q03  Best Performing Regions
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.region,
    COUNT(DISTINCT fs.order_id)         AS orders,
    COUNT(DISTINCT dc.customer_sk)      AS unique_customers,
    ROUND(SUM(fs.net_sales), 2)         AS net_revenue,
    ROUND(SUM(fs.profit),    2)         AS total_profit,
    ROUND(SUM(fs.profit) / NULLIF(SUM(fs.net_sales), 0) * 100, 2) AS profit_margin_pct,
    ROUND(SUM(fs.net_sales) / NULLIF(COUNT(DISTINCT fs.order_id), 0), 2) AS avg_order_value
FROM   fact_sales    fs
JOIN   dim_customers dc ON dc.customer_sk = fs.customer_sk
GROUP  BY dc.region
ORDER  BY net_revenue DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q04  Profit Margin by Category & Sub-Category
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dp.category,
    dp.sub_category,
    ROUND(SUM(fs.net_sales),    2)      AS net_revenue,
    ROUND(SUM(fs.profit),       2)      AS total_profit,
    ROUND(SUM(fs.cogs),         2)      AS total_cogs,
    ROUND(AVG(fs.profit_margin_pct), 2) AS avg_margin_pct,
    ROUND(SUM(fs.profit) / NULLIF(SUM(fs.net_sales),0) * 100, 2) AS blended_margin_pct,
    COUNT(DISTINCT fs.order_id)         AS order_count
FROM   fact_sales   fs
JOIN   dim_products dp ON dp.product_sk = fs.product_sk
GROUP  BY dp.category, dp.sub_category
ORDER  BY dp.category, blended_margin_pct DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q05  Repeat Customer Rate
--      Customers with > 1 distinct order date are "repeat" customers.
-- ─────────────────────────────────────────────────────────────────────────────
WITH customer_orders AS (
    SELECT
        fs.customer_sk,
        COUNT(DISTINCT fs.order_id) AS order_count
    FROM   fact_sales fs
    GROUP  BY fs.customer_sk
),
classified AS (
    SELECT
        customer_sk,
        order_count,
        CASE WHEN order_count > 1 THEN 'Repeat' ELSE 'One-Time' END AS customer_type
    FROM customer_orders
)
SELECT
    customer_type,
    COUNT(*)                                                  AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)       AS pct_of_total,
    ROUND(AVG(order_count), 2)                               AS avg_orders_per_customer
FROM classified
GROUP BY customer_type
ORDER BY customer_count DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q06  Year-over-Year Revenue Growth
-- ─────────────────────────────────────────────────────────────────────────────
WITH yearly AS (
    SELECT
        dd.year,
        ROUND(SUM(fs.net_sales), 2) AS net_revenue,
        ROUND(SUM(fs.profit),    2) AS total_profit
    FROM   fact_sales fs
    JOIN   dim_date   dd ON dd.date_sk = fs.order_date_sk
    GROUP  BY dd.year
)
SELECT
    y.year,
    y.net_revenue,
    y.total_profit,
    LAG(y.net_revenue) OVER (ORDER BY y.year)                        AS prev_year_revenue,
    ROUND(
        (y.net_revenue - LAG(y.net_revenue) OVER (ORDER BY y.year))
        / NULLIF(LAG(y.net_revenue) OVER (ORDER BY y.year), 0) * 100
    , 2)                                                             AS yoy_revenue_growth_pct,
    ROUND(
        (y.total_profit - LAG(y.total_profit) OVER (ORDER BY y.year))
        / NULLIF(ABS(LAG(y.total_profit) OVER (ORDER BY y.year)), 0) * 100
    , 2)                                                             AS yoy_profit_growth_pct
FROM yearly y
ORDER BY y.year;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q07  Average Order Value (AOV) by Segment & Region
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.segment,
    dc.region,
    COUNT(DISTINCT fs.order_id)                                         AS total_orders,
    ROUND(SUM(fs.net_sales), 2)                                         AS net_revenue,
    ROUND(SUM(fs.net_sales) / NULLIF(COUNT(DISTINCT fs.order_id), 0), 2) AS avg_order_value
FROM   fact_sales    fs
JOIN   dim_customers dc ON dc.customer_sk = fs.customer_sk
GROUP  BY dc.segment, dc.region
ORDER  BY dc.segment, avg_order_value DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q08  RFM Customer Segmentation
--      Recency: days since last purchase
--      Frequency: total orders
--      Monetary: total spend
-- ─────────────────────────────────────────────────────────────────────────────
WITH rfm_raw AS (
    SELECT
        fs.customer_sk,
        dc.customer_name,
        dc.segment,
        dc.region,
        MAX(dd.full_date)                            AS last_order_date,
        (CURRENT_DATE - MAX(dd.full_date))::INT      AS recency_days,
        COUNT(DISTINCT fs.order_id)                  AS frequency,
        ROUND(SUM(fs.net_sales), 2)                  AS monetary
    FROM   fact_sales    fs
    JOIN   dim_customers dc ON dc.customer_sk = fs.customer_sk
    JOIN   dim_date      dd ON dd.date_sk     = fs.order_date_sk
    GROUP  BY fs.customer_sk, dc.customer_name, dc.segment, dc.region
),
rfm_scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency_days  ASC)  AS r_score,  -- lower days = higher score
        NTILE(5) OVER (ORDER BY frequency     DESC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary      DESC) AS m_score
    FROM rfm_raw
),
rfm_labeled AS (
    SELECT *,
        (r_score + f_score + m_score) AS rfm_total,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2                  THEN 'Recent Customers'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2                  THEN 'Lost'
            WHEN m_score >= 4                                   THEN 'Big Spenders'
            ELSE 'Potential Loyalists'
        END AS rfm_segment
    FROM rfm_scored
)
SELECT
    rfm_segment,
    COUNT(*)                         AS customer_count,
    ROUND(AVG(recency_days), 0)      AS avg_recency_days,
    ROUND(AVG(frequency), 1)         AS avg_frequency,
    ROUND(AVG(monetary), 2)          AS avg_monetary,
    ROUND(SUM(monetary), 2)          AS total_segment_revenue
FROM rfm_labeled
GROUP BY rfm_segment
ORDER BY total_segment_revenue DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q09  Top 10 Loss-Making Products (negative profit)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dp.product_name,
    dp.category,
    dp.sub_category,
    COUNT(DISTINCT fs.order_id)         AS order_count,
    ROUND(SUM(fs.net_sales), 2)         AS net_revenue,
    ROUND(SUM(fs.profit),    2)         AS total_profit,
    ROUND(AVG(fs.discount_rate) * 100, 1) AS avg_discount_pct
FROM   fact_sales   fs
JOIN   dim_products dp ON dp.product_sk = fs.product_sk
WHERE  fs.profit < 0
GROUP  BY dp.product_name, dp.category, dp.sub_category
ORDER  BY total_profit ASC
LIMIT  10;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q10  Discount Impact Analysis
--      Do heavy discounts correlate with losses?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN fs.discount_rate = 0              THEN '0% — No Discount'
        WHEN fs.discount_rate BETWEEN 0.01 AND 0.1 THEN '1-10%'
        WHEN fs.discount_rate BETWEEN 0.11 AND 0.2 THEN '11-20%'
        WHEN fs.discount_rate BETWEEN 0.21 AND 0.3 THEN '21-30%'
        WHEN fs.discount_rate BETWEEN 0.31 AND 0.5 THEN '31-50%'
        ELSE '50%+'
    END AS discount_band,
    COUNT(*)                                    AS order_lines,
    ROUND(SUM(fs.net_sales),     2)             AS net_revenue,
    ROUND(SUM(fs.profit),        2)             AS total_profit,
    ROUND(AVG(fs.profit_margin_pct), 2)         AS avg_margin_pct,
    SUM(CASE WHEN fs.profit < 0 THEN 1 ELSE 0 END) AS loss_orders
FROM   fact_sales fs
GROUP  BY discount_band
ORDER  BY MIN(fs.discount_rate);


-- ─────────────────────────────────────────────────────────────────────────────
-- Q11  Shipping Mode Performance
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    sm.ship_mode_name,
    COUNT(DISTINCT fs.order_id)                 AS orders,
    ROUND(AVG(fs.shipping_days), 1)             AS avg_shipping_days,
    ROUND(SUM(fs.net_sales),     2)             AS net_revenue,
    ROUND(SUM(fs.profit),        2)             AS total_profit,
    ROUND(AVG(fs.profit_margin_pct), 2)         AS avg_margin_pct
FROM   fact_sales     fs
JOIN   dim_ship_mode  sm ON sm.ship_mode_sk = fs.ship_mode_sk
GROUP  BY sm.ship_mode_name
ORDER  BY net_revenue DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q12  State-Level Heatmap Data
--      Revenue & profit by state (for geo map in Power BI)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.state,
    dc.region,
    COUNT(DISTINCT dc.customer_sk)              AS customers,
    COUNT(DISTINCT fs.order_id)                 AS orders,
    ROUND(SUM(fs.net_sales),     2)             AS net_revenue,
    ROUND(SUM(fs.profit),        2)             AS total_profit,
    ROUND(SUM(fs.profit) / NULLIF(SUM(fs.net_sales), 0) * 100, 2) AS margin_pct
FROM   fact_sales    fs
JOIN   dim_customers dc ON dc.customer_sk = fs.customer_sk
GROUP  BY dc.state, dc.region
ORDER  BY net_revenue DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q13  Customer Lifetime Value Tiers
-- ─────────────────────────────────────────────────────────────────────────────
WITH clv AS (
    SELECT
        fs.customer_sk,
        dc.customer_name,
        dc.segment,
        ROUND(SUM(fs.net_sales), 2) AS lifetime_value
    FROM   fact_sales    fs
    JOIN   dim_customers dc ON dc.customer_sk = fs.customer_sk
    GROUP  BY fs.customer_sk, dc.customer_name, dc.segment
)
SELECT
    CASE
        WHEN lifetime_value >= 5000  THEN 'Platinum (≥ $5K)'
        WHEN lifetime_value >= 2000  THEN 'Gold ($2K-$5K)'
        WHEN lifetime_value >= 1000  THEN 'Silver ($1K-$2K)'
        WHEN lifetime_value >= 500   THEN 'Bronze ($500-$1K)'
        ELSE                              'Standard (< $500)'
    END                             AS clv_tier,
    segment,
    COUNT(*)                        AS customer_count,
    ROUND(AVG(lifetime_value), 2)   AS avg_ltv,
    ROUND(SUM(lifetime_value), 2)   AS total_ltv
FROM clv
GROUP BY clv_tier, segment
ORDER BY MIN(lifetime_value) DESC, segment;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q14  Quarter-over-Quarter Growth per Category
-- ─────────────────────────────────────────────────────────────────────────────
WITH qtr AS (
    SELECT
        dd.year,
        dd.quarter,
        dp.category,
        ROUND(SUM(fs.net_sales), 2) AS net_revenue
    FROM   fact_sales   fs
    JOIN   dim_date     dd ON dd.date_sk    = fs.order_date_sk
    JOIN   dim_products dp ON dp.product_sk = fs.product_sk
    GROUP  BY dd.year, dd.quarter, dp.category
)
SELECT
    year,
    quarter,
    category,
    net_revenue,
    LAG(net_revenue) OVER (PARTITION BY category ORDER BY year, quarter) AS prev_qtr_revenue,
    ROUND(
        (net_revenue - LAG(net_revenue) OVER (PARTITION BY category ORDER BY year, quarter))
        / NULLIF(LAG(net_revenue) OVER (PARTITION BY category ORDER BY year, quarter), 0) * 100
    , 2) AS qoq_growth_pct
FROM qtr
ORDER BY category, year, quarter;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q15  7-Day Rolling Revenue (for trend line chart)
-- ─────────────────────────────────────────────────────────────────────────────
WITH daily AS (
    SELECT
        dd.full_date,
        ROUND(SUM(fs.net_sales), 2) AS daily_revenue,
        ROUND(SUM(fs.profit),    2) AS daily_profit
    FROM   fact_sales fs
    JOIN   dim_date   dd ON dd.date_sk = fs.order_date_sk
    GROUP  BY dd.full_date
)
SELECT
    full_date,
    daily_revenue,
    daily_profit,
    ROUND(AVG(daily_revenue) OVER (ORDER BY full_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS rolling_7d_revenue,
    ROUND(SUM(daily_revenue) OVER (PARTITION BY DATE_TRUNC('month', full_date)
                                   ORDER BY full_date), 2)                                          AS mtd_revenue
FROM daily
ORDER BY full_date;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q16  Executive KPI Snapshot (single-row dashboard card source)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    ROUND(SUM(net_sales),     2)                  AS total_net_revenue,
    ROUND(SUM(profit),        2)                  AS total_profit,
    ROUND(SUM(profit) / NULLIF(SUM(net_sales), 0) * 100, 2) AS overall_margin_pct,
    COUNT(DISTINCT order_id)                       AS total_orders,
    SUM(quantity)                                  AS total_units_sold,
    ROUND(SUM(net_sales) / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS avg_order_value,
    (SELECT COUNT(DISTINCT customer_sk) FROM fact_sales) AS total_customers
FROM   fact_sales;
