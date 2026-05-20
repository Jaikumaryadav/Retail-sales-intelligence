import sys
"""
=============================================================================
 Retail Sales & Profit Intelligence System
 ETL Pipeline — etl_pipeline.py
 Author : Data Engineering Team
 Purpose: Ingest raw Superstore CSV to clean to enrich to export
=============================================================================
"""

import os
import logging
import numpy as np
import pandas as pd

# -- Logging setup ------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("etl_pipeline.log"),
        logging.StreamHandler(stream=open(sys.stdout.fileno(), mode="w", encoding="utf-8", closefd=False)),
    ],
)
log = logging.getLogger(__name__)

# -- Paths --------------------------------------------------------------------
RAW_PATH       = os.path.join("data", "raw", "superstore.csv")
PROCESSED_PATH = os.path.join("data", "processed", "cleaned_sales_data.csv")

# -----------------------------------------------------------------------------
# 1. EXTRACT
# -----------------------------------------------------------------------------
def extract(path: str) -> pd.DataFrame:
    """Load raw CSV into a DataFrame."""
    log.info(f"Loading raw data from: {path}")
    df = pd.read_csv(path, encoding="latin-1")
    log.info(f"Raw shape: {df.shape[0]:,} rows x {df.shape[1]} columns")
    return df


# -----------------------------------------------------------------------------
# 2. TRANSFORM — Cleaning
# -----------------------------------------------------------------------------
def clean(df: pd.DataFrame) -> pd.DataFrame:
    """Remove duplicates, fix nulls, standardise dtypes."""
    log.info("-- Cleaning ----------------------------------")

    # Duplicate rows
    before = len(df)
    df = df.drop_duplicates()
    log.info(f"Duplicates removed: {before - len(df)}")

    # Standardise column names
    df.columns = (
        df.columns.str.strip()
                  .str.lower()
                  .str.replace(" ", "_", regex=False)
                  .str.replace("-", "_", regex=False)
    )

    # Expected column aliases (Kaggle Superstore uses these names)
    col_map = {
        "row_id":       "row_id",
        "order_id":     "order_id",
        "order_date":   "order_date",
        "ship_date":    "ship_date",
        "ship_mode":    "ship_mode",
        "customer_id":  "customer_id",
        "customer_name":"customer_name",
        "segment":      "segment",
        "country":      "country",
        "city":         "city",
        "state":        "state",
        "postal_code":  "postal_code",
        "region":       "region",
        "product_id":   "product_id",
        "category":     "category",
        "sub_category": "sub_category",
        "product_name": "product_name",
        "sales":        "sales",
        "quantity":     "quantity",
        "discount":     "discount",
        "profit":       "profit",
    }
    df = df.rename(columns={k: v for k, v in col_map.items() if k in df.columns})

    # Date columns
    for col in ["order_date", "ship_date"]:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")
            nulls = df[col].isna().sum()
            if nulls:
                log.warning(f"{col} has {nulls} unparsable values — dropping rows")
                df = df.dropna(subset=[col])

    # Numeric columns — coerce bad values
    for col in ["sales", "quantity", "discount", "profit"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    # Fill remaining numeric NaNs with column median
    num_cols = df.select_dtypes(include="number").columns
    df[num_cols] = df[num_cols].fillna(df[num_cols].median())

    # Fill remaining object NaNs
    obj_cols = df.select_dtypes(include="object").columns
    df[obj_cols] = df[obj_cols].fillna("Unknown")

    log.info(f"Shape after cleaning: {df.shape[0]:,} rows x {df.shape[1]} columns")
    return df


# -----------------------------------------------------------------------------
# 3. TRANSFORM — Feature Engineering
# -----------------------------------------------------------------------------
def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """Create business-relevant derived columns."""
    log.info("-- Feature Engineering ----------------------")

    # -- Date parts ------------------------------------------------------------
    df["order_year"]    = df["order_date"].dt.year
    df["order_month"]   = df["order_date"].dt.month
    df["order_quarter"] = df["order_date"].dt.quarter
    df["order_week"]    = df["order_date"].dt.isocalendar().week.astype(int)
    df["order_dow"]     = df["order_date"].dt.day_name()

    # Days from order to ship
    if "ship_date" in df.columns:
        df["shipping_days"] = (df["ship_date"] - df["order_date"]).dt.days

    # -- Core financial metrics ------------------------------------------------
    # Profit Margin (%) = profit / sales x 100
    df["profit_margin_pct"] = np.where(
        df["sales"] != 0,
        (df["profit"] / df["sales"]) * 100,
        0.0,
    ).round(2)

    # Revenue after discount
    df["discounted_revenue"] = (df["sales"] * (1 - df["discount"])).round(2)

    # Cost of goods (implied)
    df["cogs"] = (df["sales"] - df["profit"]).round(2)

    # -- Customer Lifetime Value (simple proxy) ---------------------------------
    # CLV proxy = total sales per customer across entire history
    clv = df.groupby("customer_id")["sales"].transform("sum").round(2)
    df["customer_ltv"] = clv

    # -- Customer order rank (chronological, per customer) ---------------------
    df = df.sort_values(["customer_id", "order_date"])
    df["customer_order_rank"] = df.groupby("customer_id").cumcount() + 1
    df["is_repeat_customer"]  = (df["customer_order_rank"] > 1).astype(int)

    # -- Month-over-Month sales growth (aggregate level) ------------------------
    monthly = (
        df.groupby(["order_year", "order_month"])["sales"]
          .sum()
          .reset_index()
          .rename(columns={"sales": "monthly_total"})
    )
    monthly["sales_growth_pct"] = monthly["monthly_total"].pct_change() * 100
    monthly["sales_growth_pct"] = monthly["sales_growth_pct"].round(2).fillna(0)

    df = df.merge(monthly[["order_year", "order_month", "sales_growth_pct"]],
                  on=["order_year", "order_month"], how="left")

    # -- Sales per unit --------------------------------------------------------
    df["revenue_per_unit"] = (df["sales"] / df["quantity"].replace(0, 1)).round(2)

    # -- Segment flags ---------------------------------------------------------
    df["is_high_value_order"] = (df["sales"] > df["sales"].quantile(0.75)).astype(int)
    df["is_loss_order"]       = (df["profit"] < 0).astype(int)

    log.info(f"Features added. Final shape: {df.shape[0]:,} rows x {df.shape[1]} columns")
    return df


# -----------------------------------------------------------------------------
# 4. VALIDATE
# -----------------------------------------------------------------------------
def validate(df: pd.DataFrame) -> None:
    """Basic data-quality assertions."""
    log.info("-- Validation --------------------------------")
    assert df["sales"].min() >= 0,    "Negative sales detected!"
    assert df["quantity"].min() >= 0, "Negative quantity detected!"
    assert df["order_date"].isna().sum() == 0, "Null order dates!"
    assert df["customer_id"].isna().sum() == 0, "Null customer IDs!"
    log.info("All validation checks passed OK")


# -----------------------------------------------------------------------------
# 5. LOAD
# -----------------------------------------------------------------------------
def load(df: pd.DataFrame, path: str) -> None:
    """Write cleaned DataFrame to CSV."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    df.to_csv(path, index=False)
    log.info(f"Saved cleaned data to {path}  ({os.path.getsize(path)/1024:.1f} KB)")


# -----------------------------------------------------------------------------
# 6. SUMMARY REPORT
# -----------------------------------------------------------------------------
def print_summary(df: pd.DataFrame) -> None:
    total_sales   = df["sales"].sum()
    total_profit  = df["profit"].sum()
    avg_margin    = df["profit_margin_pct"].mean()
    repeat_rate   = df["is_repeat_customer"].mean() * 100
    n_customers   = df["customer_id"].nunique()
    n_orders      = df["order_id"].nunique()
    date_range    = f"{df['order_date'].min().date()} to {df['order_date'].max().date()}"

    print("\n" + "="*55)
    print("  RETAIL INTELLIGENCE — ETL SUMMARY")
    print("="*55)
    print(f"  Date range       : {date_range}")
    print(f"  Total orders     : {n_orders:>10,}")
    print(f"  Unique customers : {n_customers:>10,}")
    print(f"  Total revenue    : ${total_sales:>12,.2f}")
    print(f"  Total profit     : ${total_profit:>12,.2f}")
    print(f"  Avg profit margin: {avg_margin:>10.2f}%")
    print(f"  Repeat cust. rate: {repeat_rate:>10.2f}%")
    print("="*55 + "\n")


# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
def run_pipeline():
    log.info("====== ETL PIPELINE STARTED ======")
    df = extract(RAW_PATH)
    df = clean(df)
    df = engineer_features(df)
    validate(df)
    load(df, PROCESSED_PATH)
    print_summary(df)
    log.info("====== ETL PIPELINE COMPLETE ======")
    return df


if __name__ == "__main__":
    run_pipeline()
