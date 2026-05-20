# Power BI Dashboard Build Guide
## Retail Sales & Profit Intelligence System

---

## PRE-REQUISITES

1. **Download** Power BI Desktop (free): https://powerbi.microsoft.com/desktop
2. **Data source**: `data/processed/cleaned_sales_data.csv`
3. **Estimated build time**: 2–3 hours

---

## STEP 1 — CONNECT DATA

1. Open Power BI Desktop → **Get Data** → **Text/CSV**
2. Navigate to `data/processed/cleaned_sales_data.csv` → **Load**
3. In **Power Query Editor**:
   - Verify `order_date` is type **Date**
   - Verify `sales`, `profit`, `discount` are **Decimal Number**
   - Verify `quantity` is **Whole Number**
   - Click **Close & Apply**

---

## STEP 2 — CREATE A DATE TABLE

In the **Model** view, add a calculated Date table:

```dax
DateTable =
ADDCOLUMNS(
    CALENDAR(DATE(2015,1,1), DATE(2025,12,31)),
    "Year",        YEAR([Date]),
    "Month Num",   MONTH([Date]),
    "Month Name",  FORMAT([Date], "MMM"),
    "Quarter",     "Q" & QUARTER([Date]),
    "Week",        WEEKNUM([Date]),
    "Weekday",     FORMAT([Date], "ddd"),
    "YearMonth",   FORMAT([Date], "YYYY-MM")
)
```

**Mark as Date Table**: right-click DateTable → Mark as date table → select `Date` column.

**Create relationship**: `DateTable[Date]` → `cleaned_sales_data[order_date]` (Many-to-One)

---

## STEP 3 — DAX MEASURES

Create a dedicated **Measures table** (Enter Data → empty table named `_Measures`).

### ── Core KPI Measures ──────────────────────────────────────────────────────

```dax
Total Revenue =
ROUND(SUM(cleaned_sales_data[sales]), 2)

Total Profit =
ROUND(SUM(cleaned_sales_data[profit]), 2)

Total Orders =
DISTINCTCOUNT(cleaned_sales_data[order_id])

Total Units Sold =
SUM(cleaned_sales_data[quantity])

Avg Order Value =
DIVIDE([Total Revenue], [Total Orders], 0)

Profit Margin % =
DIVIDE([Total Profit], [Total Revenue], 0) * 100

Total Customers =
DISTINCTCOUNT(cleaned_sales_data[customer_id])
```

### ── Time Intelligence ────────────────────────────────────────────────────

```dax
Revenue LY =
CALCULATE([Total Revenue],
    SAMEPERIODLASTYEAR(DateTable[Date]))

YoY Revenue Growth % =
DIVIDE(
    [Total Revenue] - [Revenue LY],
    ABS([Revenue LY]),
    BLANK()
) * 100

Revenue MTD =
CALCULATE([Total Revenue],
    DATESMTD(DateTable[Date]))

Revenue QTD =
CALCULATE([Total Revenue],
    DATESQTD(DateTable[Date]))

Revenue YTD =
CALCULATE([Total Revenue],
    DATESYTD(DateTable[Date]))

Profit YTD =
CALCULATE([Total Profit],
    DATESYTD(DateTable[Date]))
```

### ── Customer Metrics ─────────────────────────────────────────────────────

```dax
Repeat Customer Rate % =
VAR RepeatCustomers =
    COUNTROWS(
        FILTER(
            SUMMARIZE(cleaned_sales_data,
                cleaned_sales_data[customer_id],
                "OrderCount", DISTINCTCOUNT(cleaned_sales_data[order_id])),
            [OrderCount] > 1
        )
    )
RETURN
DIVIDE(RepeatCustomers, [Total Customers], 0) * 100

Avg Customer LTV =
DIVIDE([Total Revenue], [Total Customers], 0)
```

### ── Dynamic Metrics ──────────────────────────────────────────────────────

```dax
Loss Orders Count =
COUNTROWS(
    FILTER(cleaned_sales_data, cleaned_sales_data[profit] < 0)
)

High Discount Orders =
COUNTROWS(
    FILTER(cleaned_sales_data, cleaned_sales_data[discount] >= 0.3)
)

Avg Shipping Days =
AVERAGE(cleaned_sales_data[shipping_days])

Revenue per Customer =
DIVIDE([Total Revenue], [Total Customers], 0)
```

---

## PAGE 1 — EXECUTIVE OVERVIEW

**Goal**: C-suite KPI snapshot — one glance = full picture.

### Layout (1280 × 720 canvas):

```
┌─────────────────────────────────────────────────────────┐
│  HEADER: Company logo | "Sales Intelligence Dashboard"  │
│           Date range slicer | Segment slicer            │
├──────┬──────┬──────┬──────┬──────┬──────────────────────┤
│  KPI │  KPI │  KPI │  KPI │  KPI │                      │
│ Card │ Card │ Card │ Card │ Card │    Trend Line Chart   │
│      │      │      │      │      │   (Revenue + Profit)  │
├──────┴──────┴──────┴──────┴──────┤                      │
│                                  ├──────────────────────┤
│     Revenue by Category          │  YoY Growth Gauge    │
│       (Clustered Bar)            │     or Card          │
├──────────────────────────────────┴──────────────────────┤
│            Bottom: Data last refreshed timestamp         │
└─────────────────────────────────────────────────────────┘
```

### Cards — add 5 KPI cards across the top:

| Card # | Title | Measure | Format |
|--------|-------|---------|--------|
| 1 | Total Revenue | `[Total Revenue]` | $#,##0 |
| 2 | Total Profit | `[Total Profit]` | $#,##0 |
| 3 | Profit Margin | `[Profit Margin %]` | 0.00% |
| 4 | Total Orders | `[Total Orders]` | #,##0 |
| 5 | YoY Growth | `[YoY Revenue Growth %]` | +0.00% |

**Formatting**: Bold font 20pt for value, 10pt subtitle, accent colour border bottom.

### Trend Line Chart:

- **Visual**: Line Chart
- **X-axis**: `DateTable[YearMonth]` (sorted by Month Num)
- **Values**: `[Total Revenue]`, `[Total Profit]`
- **Legend**: auto
- **Markers**: On
- **Analytics**: Add average line for Revenue

### Clustered Bar — Revenue by Category:

- **Visual**: Clustered Bar Chart
- **Y-axis**: `cleaned_sales_data[category]`
- **X-axis**: `[Total Revenue]`
- **Small multiples**: `cleaned_sales_data[region]` (optional)
- **Data labels**: On, outside end
- **Sort**: Descending by revenue

### Slicers (top-right):

- **Slicer 1**: `DateTable[Year]` — Tile style
- **Slicer 2**: `cleaned_sales_data[segment]` — Dropdown
- **Slicer 3**: `cleaned_sales_data[region]` — Dropdown

---

## PAGE 2 — REGIONAL ANALYSIS

**Goal**: Geo-distribution of sales, profit hotspots.

### Visuals:

**1. Filled Map (main visual, 50% of page)**
- Location: `cleaned_sales_data[state]`
- Values (colour saturation): `[Total Revenue]`
- Tooltips: `[Total Profit]`, `[Profit Margin %]`, `[Total Orders]`

**2. Clustered Column — Revenue by Region:**
- X-axis: `cleaned_sales_data[region]`
- Y-axis: `[Total Revenue]`, `[Total Profit]` (clustered)
- Data labels: On

**3. Matrix — State Performance:**
- Rows: `cleaned_sales_data[state]`
- Values: `[Total Revenue]`, `[Total Profit]`, `[Profit Margin %]`, `[Total Orders]`
- Conditional formatting: Data bars on Revenue column; Red-Yellow-Green scale on Margin %

**4. Scatter Chart — Revenue vs Profit by State:**
- X: `[Total Revenue]`
- Y: `[Total Profit]`
- Details: `cleaned_sales_data[state]`
- Size: `[Total Orders]`
- Add: Constant line at Y=0 (profit boundary)

**Slicers**: Year, Category, Segment

---

## PAGE 3 — PRODUCT PERFORMANCE

**Goal**: SKU-level analysis — winners, losers, discounting.

### Visuals:

**1. Top N Products Bar Chart:**
- Visual: Horizontal Bar
- Y-axis: `cleaned_sales_data[product_name]`
- X-axis: `[Total Revenue]`
- **Top N filter**: Top 10 by `[Total Revenue]`
- Colour conditional formatting: Green = profitable, Red = loss

**2. Sub-Category Treemap:**
- Group: `cleaned_sales_data[category]`
- Details: `cleaned_sales_data[sub_category]`
- Values: `[Total Revenue]`
- Colour: `[Profit Margin %]` (diverging scale: Red → White → Green)

**3. Discount vs Profit Scatter:**
- X: `AVERAGE(cleaned_sales_data[discount])` per product
- Y: `[Total Profit]`
- Details: `cleaned_sales_data[sub_category]`
- Reference line: X = 0.2 (20% discount threshold)
- **Insight**: Products bottom-right (high discount, low profit) need pricing review

**4. Loss Makers Table:**
```
Columns: Product Name | Category | Orders | Revenue | Profit | Avg Discount
Filter: [Total Profit] < 0
Sort: Profit ASC
Conditional formatting: Profit column → Red background
```

**5. Category Donut:**
- Values: `[Total Revenue]`
- Legend: `cleaned_sales_data[category]`
- Inner label: Total Revenue

---

## PAGE 4 — SALES TRENDS & FORECASTING

**Goal**: Temporal patterns + Prophet forecast output.

### Visuals:

**1. Area Chart — Monthly Revenue Trend:**
- X-axis: `DateTable[YearMonth]`
- Y-axis: `[Total Revenue]`
- Secondary Y: `[Total Profit]`
- Analytics pane: Trend line + Forecast (built-in, 6 periods)

**2. Seasonal Heatmap (Matrix):**
- Rows: `DateTable[Year]`
- Columns: `DateTable[Month Name]` (sorted by Month Num)
- Values: `[Total Revenue]`
- Conditional formatting: Data colour → Green gradient
- **Insight**: Spot Q4 spike patterns

**3. Waterfall Chart — Monthly Profit Movement:**
- Category: `DateTable[Month Name]`
- Y: `[Total Profit]`
- Breakdown: `cleaned_sales_data[category]`

**4. Import Forecast CSV:**
- Get Data → `reports/forecast_table.csv`
- Line chart: X = `forecast_month`, Y = `predicted_sales`
- Error bars: `lower_bound` / `upper_bound`
- Combine with actuals on same chart using separate series

**5. KPI Cards — Current Period:**
- Revenue MTD: `[Revenue MTD]`
- Revenue QTD: `[Revenue QTD]`
- Revenue YTD: `[Revenue YTD]`
- Profit YTD: `[Profit YTD]`

---

## STEP 4 — FORMATTING & THEME

### Apply custom theme (paste in JSON via View → Themes → Customize):

```json
{
  "name": "RetailIntelligence",
  "dataColors": [
    "#1e3a5f", "#e84393", "#f5a623",
    "#10b981", "#6366f1", "#ef4444"
  ],
  "background": "#f8fafc",
  "foreground": "#1e3a5f",
  "tableAccent": "#1e3a5f",
  "visualStyles": {
    "card": { "calloutValue": { "fontSize": 28, "fontBold": true } }
  }
}
```

### Page-level settings (each page):
- Canvas size: 1280 × 720
- Page background: #ffffff
- Wallpaper: Off

### Navigation:
- Add **Buttons** (Insert → Buttons → Blank) linking to each page
- Label: "Overview" | "Regional" | "Products" | "Trends"
- Place in consistent header position on all pages

---

## STEP 5 — PUBLISH

1. **File → Publish → Publish to Power BI**
2. Sign in with Microsoft account (free)
3. Choose **My Workspace**
4. Enable **Scheduled Refresh** (if on Gateway) — daily at 6:00 AM
5. Share report link with stakeholders

---

## TIPS FOR INTERVIEW

- Use **Bookmarks** to create "story mode" — preset views of different time periods
- Use **Q&A visual** so stakeholders can ask questions in natural language
- Add **Smart Narrative** visual (auto-generates text summary of the page)
- Use **Decomposition Tree** on profit to drill into loss drivers
