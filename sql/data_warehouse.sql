-- =============================================================================
--  Retail Sales & Profit Intelligence System
--  File : data_warehouse.sql
--  RDBMS: PostgreSQL 15+  (MySQL-compatible notes in comments)
--  Schema: STAR schema — 3 dimensions + 1 fact table
-- =============================================================================

-- ── Database setup ────────────────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS retail_intelligence;
\c retail_intelligence;   -- psql: connect to DB   (MySQL: USE retail_intelligence;)

-- ── Extensions (PostgreSQL only) ─────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- =============================================================================
-- DIMENSION 1 — dim_customers
-- =============================================================================
DROP TABLE IF EXISTS dim_customers CASCADE;

CREATE TABLE dim_customers (
    customer_sk     SERIAL          PRIMARY KEY,          -- surrogate key
    customer_id     VARCHAR(20)     NOT NULL UNIQUE,      -- natural key  e.g. CG-12520
    customer_name   VARCHAR(120)    NOT NULL,
    segment         VARCHAR(50)     NOT NULL,             -- Consumer / Corporate / Home Office
    city            VARCHAR(100),
    state           VARCHAR(100),
    postal_code     VARCHAR(20),
    country         VARCHAR(100)    DEFAULT 'United States',
    region          VARCHAR(50),                          -- East / West / Central / South
    customer_ltv    NUMERIC(12, 2)  DEFAULT 0.00,         -- lifetime value (updated by ETL)
    is_repeat       BOOLEAN         DEFAULT FALSE,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customers_segment ON dim_customers(segment);
CREATE INDEX idx_customers_region  ON dim_customers(region);
CREATE INDEX idx_customers_state   ON dim_customers(state);

COMMENT ON TABLE  dim_customers IS 'Customer dimension — one row per unique customer';
COMMENT ON COLUMN dim_customers.customer_ltv IS 'Total revenue across all orders; refreshed nightly';


-- =============================================================================
-- DIMENSION 2 — dim_products
-- =============================================================================
DROP TABLE IF EXISTS dim_products CASCADE;

CREATE TABLE dim_products (
    product_sk      SERIAL          PRIMARY KEY,
    product_id      VARCHAR(30)     NOT NULL UNIQUE,      -- e.g. FUR-BO-10001798
    product_name    VARCHAR(300)    NOT NULL,
    category        VARCHAR(50)     NOT NULL,             -- Furniture / Technology / Office Supplies
    sub_category    VARCHAR(50)     NOT NULL,             -- Chairs / Phones / Binders …
    brand           VARCHAR(100),                         -- populated where available
    is_active       BOOLEAN         DEFAULT TRUE,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_products_category     ON dim_products(category);
CREATE INDEX idx_products_sub_category ON dim_products(sub_category);

COMMENT ON TABLE dim_products IS 'Product dimension — one row per SKU';


-- =============================================================================
-- DIMENSION 3 — dim_date
-- =============================================================================
DROP TABLE IF EXISTS dim_date CASCADE;

CREATE TABLE dim_date (
    date_sk         INT             PRIMARY KEY,          -- YYYYMMDD integer key
    full_date       DATE            NOT NULL UNIQUE,
    day_of_week     SMALLINT        NOT NULL,             -- 1=Monday … 7=Sunday
    day_name        VARCHAR(10)     NOT NULL,
    day_of_month    SMALLINT        NOT NULL,
    day_of_year     SMALLINT        NOT NULL,
    week_of_year    SMALLINT        NOT NULL,
    month_num       SMALLINT        NOT NULL,
    month_name      VARCHAR(10)     NOT NULL,
    quarter         SMALLINT        NOT NULL,
    year            SMALLINT        NOT NULL,
    is_weekend      BOOLEAN         NOT NULL DEFAULT FALSE,
    is_holiday      BOOLEAN         NOT NULL DEFAULT FALSE,
    fiscal_quarter  VARCHAR(6),                           -- e.g. FY25Q1
    fiscal_year     SMALLINT
);

-- Populate dim_date for 2015-01-01 → 2025-12-31
INSERT INTO dim_date
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT                        AS date_sk,
    d                                                   AS full_date,
    EXTRACT(ISODOW FROM d)::SMALLINT                    AS day_of_week,
    TO_CHAR(d, 'Day')                                   AS day_name,
    EXTRACT(DAY   FROM d)::SMALLINT                     AS day_of_month,
    EXTRACT(DOY   FROM d)::SMALLINT                     AS day_of_year,
    EXTRACT(WEEK  FROM d)::SMALLINT                     AS week_of_year,
    EXTRACT(MONTH FROM d)::SMALLINT                     AS month_num,
    TO_CHAR(d, 'Month')                                 AS month_name,
    EXTRACT(QUARTER FROM d)::SMALLINT                   AS quarter,
    EXTRACT(YEAR  FROM d)::SMALLINT                     AS year,
    EXTRACT(ISODOW FROM d) IN (6, 7)                   AS is_weekend,
    FALSE                                               AS is_holiday,
    'FY' || TO_CHAR(d,'YY') || 'Q' || EXTRACT(QUARTER FROM d) AS fiscal_quarter,
    EXTRACT(YEAR FROM d)::SMALLINT                      AS fiscal_year
FROM generate_series('2015-01-01'::DATE, '2025-12-31'::DATE, '1 day') AS d;

COMMENT ON TABLE dim_date IS 'Date dimension — one row per calendar day 2015-2025';


-- =============================================================================
-- DIMENSION 4 — dim_ship_mode  (mini / junk dimension)
-- =============================================================================
DROP TABLE IF EXISTS dim_ship_mode CASCADE;

CREATE TABLE dim_ship_mode (
    ship_mode_sk    SERIAL      PRIMARY KEY,
    ship_mode_name  VARCHAR(50) NOT NULL UNIQUE,  -- Standard Class / Second Class / First Class / Same Day
    avg_days        SMALLINT,
    cost_tier       VARCHAR(20)                   -- Low / Medium / High / Express
);

INSERT INTO dim_ship_mode (ship_mode_name, avg_days, cost_tier) VALUES
    ('Standard Class', 5, 'Low'),
    ('Second Class',   3, 'Medium'),
    ('First Class',    2, 'High'),
    ('Same Day',       0, 'Express');


-- =============================================================================
-- FACT TABLE — fact_sales
-- =============================================================================
DROP TABLE IF EXISTS fact_sales CASCADE;

CREATE TABLE fact_sales (
    sales_sk            BIGSERIAL       PRIMARY KEY,
    -- Foreign keys to dimensions
    order_date_sk       INT             NOT NULL REFERENCES dim_date(date_sk),
    ship_date_sk        INT             REFERENCES dim_date(date_sk),
    customer_sk         INT             NOT NULL REFERENCES dim_customers(customer_sk),
    product_sk          INT             NOT NULL REFERENCES dim_products(product_sk),
    ship_mode_sk        INT             REFERENCES dim_ship_mode(ship_mode_sk),

    -- Degenerate dimensions (no separate table needed)
    order_id            VARCHAR(25)     NOT NULL,
    row_id              INT,

    -- Measures
    quantity            SMALLINT        NOT NULL DEFAULT 1,
    unit_price          NUMERIC(10, 2)  NOT NULL DEFAULT 0.00,
    discount_rate       NUMERIC(5, 4)   NOT NULL DEFAULT 0.00,  -- e.g. 0.2000 = 20%
    gross_sales         NUMERIC(12, 2)  NOT NULL DEFAULT 0.00,  -- before discount
    net_sales           NUMERIC(12, 2)  NOT NULL DEFAULT 0.00,  -- after discount
    cogs                NUMERIC(12, 2)  NOT NULL DEFAULT 0.00,
    profit              NUMERIC(12, 2)  NOT NULL DEFAULT 0.00,
    profit_margin_pct   NUMERIC(7, 4)   NOT NULL DEFAULT 0.00,
    shipping_days       SMALLINT,
    revenue_per_unit    NUMERIC(10, 2),

    -- Audit
    etl_loaded_at       TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    etl_source_file     VARCHAR(200)
);

-- Performance indexes
CREATE INDEX idx_fact_order_date   ON fact_sales(order_date_sk);
CREATE INDEX idx_fact_customer     ON fact_sales(customer_sk);
CREATE INDEX idx_fact_product      ON fact_sales(product_sk);
CREATE INDEX idx_fact_order_id     ON fact_sales(order_id);
CREATE INDEX idx_fact_ship_mode    ON fact_sales(ship_mode_sk);

-- Partial indexes for common filters
CREATE INDEX idx_fact_profitable   ON fact_sales(profit)       WHERE profit > 0;
CREATE INDEX idx_fact_loss_orders  ON fact_sales(profit)       WHERE profit < 0;

COMMENT ON TABLE  fact_sales IS 'Central fact table — one row per order line item';
COMMENT ON COLUMN fact_sales.gross_sales IS 'sales column from source before applying discount';
COMMENT ON COLUMN fact_sales.net_sales   IS 'gross_sales * (1 - discount_rate)';


-- =============================================================================
-- AGGREGATED SUMMARY TABLE (materialised for BI tool performance)
-- =============================================================================
DROP TABLE IF EXISTS agg_monthly_sales CASCADE;

CREATE TABLE agg_monthly_sales (
    agg_sk          SERIAL       PRIMARY KEY,
    year            SMALLINT     NOT NULL,
    month_num       SMALLINT     NOT NULL,
    month_name      VARCHAR(10),
    category        VARCHAR(50),
    region          VARCHAR(50),
    total_orders    INT          DEFAULT 0,
    total_quantity  INT          DEFAULT 0,
    gross_revenue   NUMERIC(14,2) DEFAULT 0.00,
    net_revenue     NUMERIC(14,2) DEFAULT 0.00,
    total_profit    NUMERIC(14,2) DEFAULT 0.00,
    avg_profit_margin NUMERIC(7,4) DEFAULT 0.00,
    UNIQUE (year, month_num, category, region)
);

COMMENT ON TABLE agg_monthly_sales IS 'Pre-aggregated monthly KPIs for dashboard fast-lane queries';


-- =============================================================================
-- STORED PROCEDURE — Load fact from staging
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_load_fact_sales()
LANGUAGE plpgsql AS $$
BEGIN
    -- Insert new rows only (upsert guard via order_id + row_id)
    INSERT INTO fact_sales (
        order_date_sk, ship_date_sk, customer_sk, product_sk, ship_mode_sk,
        order_id, row_id,
        quantity, unit_price, discount_rate,
        gross_sales, net_sales, cogs, profit, profit_margin_pct,
        shipping_days, revenue_per_unit
    )
    SELECT
        TO_CHAR(s.order_date, 'YYYYMMDD')::INT,
        TO_CHAR(s.ship_date,  'YYYYMMDD')::INT,
        c.customer_sk,
        p.product_sk,
        sm.ship_mode_sk,
        s.order_id,
        s.row_id,
        s.quantity,
        CASE WHEN s.quantity > 0 THEN s.sales / s.quantity ELSE s.sales END,
        s.discount,
        s.sales,
        s.sales * (1 - s.discount),
        s.sales - s.profit,
        s.profit,
        CASE WHEN s.sales <> 0 THEN (s.profit / s.sales) * 100 ELSE 0 END,
        EXTRACT(DAY FROM (s.ship_date - s.order_date))::SMALLINT,
        CASE WHEN s.quantity > 0 THEN s.sales / s.quantity ELSE s.sales END
    FROM   staging_sales s
    JOIN   dim_customers c  ON c.customer_id   = s.customer_id
    JOIN   dim_products  p  ON p.product_id    = s.product_id
    JOIN   dim_ship_mode sm ON sm.ship_mode_name = s.ship_mode
    WHERE  NOT EXISTS (
        SELECT 1 FROM fact_sales f
        WHERE  f.order_id = s.order_id
        AND    f.row_id   = s.row_id
    );

    RAISE NOTICE 'sp_load_fact_sales completed at %', NOW();
END;
$$;
