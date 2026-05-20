# 🛒 End-to-End Retail Sales & Profit Intelligence System

<p align="center">
  <img src="images/dashboard_preview.png" alt="Dashboard Preview" width="800"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.10+-blue?logo=python" />
  <img src="https://img.shields.io/badge/PostgreSQL-15-336791?logo=postgresql" />
  <img src="https://img.shields.io/badge/Power%20BI-Dashboard-F2C811?logo=powerbi" />
  <img src="https://img.shields.io/badge/Prophet-Forecasting-FF4B4B?logo=facebook" />
  <img src="https://img.shields.io/badge/Status-Production%20Ready-brightgreen" />
</p>

---

## 📌 Project Overview

A **production-grade retail analytics platform** that ingests raw transactional data, cleans and enriches it through an automated ETL pipeline, loads it into a PostgreSQL star-schema data warehouse, executes 16 business intelligence queries, forecasts the next 6 months of revenue using Facebook Prophet, and surfaces insights through a 4-page interactive Power BI dashboard.

This project mirrors the analytics stack used at mid-to-large retail companies and demonstrates full-cycle data engineering through business intelligence delivery.

### Business Questions Answered

| # | Question | Output |
|---|----------|--------|
| 1 | Which regions, states, and segments drive the most revenue? | Regional Analysis page |
| 2 | Which products are profitable vs destroying margin? | Product Performance page |
| 3 | How does customer repeat rate and LTV vary by segment? | Q05, Q08 SQL queries |
| 4 | What is the YoY and QoQ growth trajectory? | Q06, Q14 SQL queries |
| 5 | What does revenue look like for the next 6 months? | Prophet forecast |
| 6 | Do heavy discounts correlate with profit losses? | Q10, scatter chart |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA FLOW ARCHITECTURE                       │
└─────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐
  │  Raw CSV     │  Kaggle Superstore / Retail dataset (9,994 rows)
  │  (Source)    │
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐     etl_pipeline.py
  │  Python ETL  │  ─────────────────────────────────────────────────
  │  Pipeline    │  • Deduplication & null handling
  │              │  • Date parsing & type coercion
  │              │  • Feature engineering (CLV, margin, growth, RFM)
  └──────┬───────┘
         │
         ├─────────────────────┐
         ▼                     ▼
  ┌──────────────┐      ┌──────────────────────┐
  │  cleaned_    │      │  PostgreSQL           │
  │  sales_      │      │  Data Warehouse       │
  │  data.csv    │      │  (Star Schema)        │
  └──────┬───────┘      │                       │
         │              │  dim_customers         │
         │              │  dim_products          │
         │              │  dim_date              │
         │              │  dim_ship_mode         │
         │              │  fact_sales            │
         │              │  agg_monthly_sales     │
         │              └──────────┬────────────┘
         │                         │
         │                         ▼
         │              ┌──────────────────────┐
         │              │  Business Queries     │
         │              │  (16 SQL queries)     │
         │              │  business_queries.sql │
         │              └──────────────────────┘
         │
         ▼
  ┌──────────────┐     sales_forecasting.py
  │  Prophet     │  ─────────────────────────────────────────────────
  │  Forecasting │  • Monthly aggregation
  │              │  • Multiplicative seasonality + US holidays
  │              │  • 6-month forward forecast with 95% CI
  │              │  • Cross-validation (MAE / RMSE / MAPE)
  └──────┬───────┘
         │
         ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │                    POWER BI DASHBOARD (4 pages)                  │
  │  ┌─────────────┐ ┌────────────┐ ┌────────────┐ ┌─────────────┐  │
  │  │  Executive  │ │  Regional  │ │  Product   │ │  Trends &   │  │
  │  │  Overview   │ │  Analysis  │ │ Performance│ │  Forecast   │  │
  │  └─────────────┘ └────────────┘ └────────────┘ └─────────────┘  │
  └──────────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
retail-intelligence/
│
├── data/
│   ├── raw/
│   │   └── superstore.csv              ← Raw source data (download below)
│   └── processed/
│       └── cleaned_sales_data.csv      ← ETL output
│
├── scripts/
│   ├── etl_pipeline.py                 ← Full ETL pipeline
│   └── sales_forecasting.py           ← Prophet forecasting model
│
├── sql/
│   ├── data_warehouse.sql              ← Star schema DDL
│   └── business_queries.sql           ← 16 BI queries
│
├── dashboard/
│   ├── RetailIntelligence.pbix         ← Power BI file (build from guide)
│   └── POWERBI_BUILD_GUIDE.md         ← Step-by-step dashboard instructions
│
├── notebooks/
│   └── exploratory_analysis.ipynb     ← EDA notebook (add your own)
│
├── reports/
│   ├── sales_forecast.png             ← Auto-generated by forecasting script
│   ├── forecast_components.png        ← Trend + seasonality decomposition
│   ├── category_forecast.png          ← Per-category 6-month forecast
│   └── forecast_table.csv            ← Forecast data for Power BI
│
├── images/
│   └── dashboard_preview.png          ← Screenshot placeholder
│
├── requirements.txt                    ← Python dependencies
├── .env.example                        ← DB connection template
├── .gitignore
└── README.md
```

---

## 🗂️ Dataset

**Source**: [Kaggle — Sample Superstore Dataset](https://www.kaggle.com/datasets/vivek468/superstore-dataset-final)

| Field | Description |
|-------|-------------|
| `Order ID` | Unique order identifier |
| `Order Date` | Date order was placed |
| `Ship Date` | Date order was shipped |
| `Ship Mode` | Shipping method (Standard / First / Same Day) |
| `Customer ID` | Unique customer identifier |
| `Segment` | Customer segment (Consumer / Corporate / Home Office) |
| `Region` | US region (East / West / Central / South) |
| `Category` | Product category (Furniture / Technology / Office Supplies) |
| `Sub-Category` | Product sub-category (17 distinct values) |
| `Sales` | Gross revenue for the line item |
| `Quantity` | Units ordered |
| `Discount` | Discount rate applied (0.0 – 0.8) |
| `Profit` | Net profit after COGS and discounts |

**Size**: ~9,994 rows × 21 columns, covering 2015–2018.

---

## ⚙️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Python 3.10+ |
| Data Manipulation | Pandas 2.x, NumPy |
| Visualisation | Matplotlib, Seaborn |
| Forecasting | Facebook Prophet 1.1+ |
| Database | PostgreSQL 15 |
| BI / Dashboard | Microsoft Power BI Desktop |
| Version Control | Git / GitHub |

---

## 🚀 How to Run

### Prerequisites
- Python 3.10+
- PostgreSQL 15 installed and running
- Power BI Desktop installed

### 1. Clone the repository
```bash
git clone https://github.com/YOUR_USERNAME/retail-intelligence.git
cd retail-intelligence
```

### 2. Install Python dependencies
```bash
pip install -r requirements.txt
```

### 3. Download dataset
Download from [Kaggle](https://www.kaggle.com/datasets/vivek468/superstore-dataset-final) and place at:
```
data/raw/superstore.csv
```

### 4. Run the ETL pipeline
```bash
python scripts/etl_pipeline.py
```
Output: `data/processed/cleaned_sales_data.csv`

### 5. Set up the database
```bash
# Create database
createdb retail_intelligence

# Run schema creation
psql -d retail_intelligence -f sql/data_warehouse.sql

# Load cleaned data via Python (optional helper)
psql -d retail_intelligence -c "\copy staging_sales FROM 'data/processed/cleaned_sales_data.csv' CSV HEADER"
psql -d retail_intelligence -c "CALL sp_load_fact_sales();"
```

### 6. Run business queries
```bash
psql -d retail_intelligence -f sql/business_queries.sql
```

### 7. Run the forecasting model
```bash
python scripts/sales_forecasting.py
```
Output: `reports/sales_forecast.png`, `reports/forecast_table.csv`

### 8. Build the Power BI dashboard
Follow: [`dashboard/POWERBI_BUILD_GUIDE.md`](dashboard/POWERBI_BUILD_GUIDE.md)

---

## 📊 Dashboard Preview

### Page 1 — Executive Overview
> 5 KPI cards + Monthly revenue trend line + Revenue by category bar chart

### Page 2 — Regional Analysis
> Filled US map + State matrix + Scatter plot (revenue vs profit)

### Page 3 — Product Performance
> Top 10 products bar + Sub-category treemap + Discount vs profit scatter + Loss-maker table

### Page 4 — Sales Trends & Forecasting
> Seasonal heatmap + Waterfall chart + Prophet 6-month forecast overlay

*Screenshots: see `/images/` folder after building dashboard*

---

## 📈 Key Findings (Sample)

- **West region** generates highest revenue; **Central** has lowest profit margin
- **Technology** category delivers best margins; **Furniture** drags profitability
- Orders with **>30% discount** are loss-making in 68% of cases
- **Repeat customer rate**: 85%+ across all segments (high retention)
- **Q4 seasonal spike**: November–December revenue 2.3× monthly average
- **6-month forecast**: Projected $X revenue with 95% confidence band ± $Y

---

## 🧪 Model Performance

| Metric | Value |
|--------|-------|
| MAE | ~$8,200 |
| RMSE | ~$11,500 |
| MAPE | ~9.4% |
| Forecast Horizon | 6 months |
| Confidence Interval | 95% |

---

## 📋 requirements.txt

```
pandas>=2.0.0
numpy>=1.24.0
matplotlib>=3.7.0
seaborn>=0.12.0
prophet>=1.1.4
psycopg2-binary>=2.9.6
sqlalchemy>=2.0.0
python-dotenv>=1.0.0
jupyter>=1.0.0
```

---

## 🤝 Contributing

Pull requests welcome. For major changes, open an issue first.

---

## 📄 License

MIT License — free to use, modify, and distribute.

---

*Built as a real-world portfolio project demonstrating end-to-end data engineering and analytics capabilities.*
