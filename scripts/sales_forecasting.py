"""
=============================================================================
 Retail Sales & Profit Intelligence System
 File : sales_forecasting.py
 Model: Facebook Prophet — 6-month forward forecast
 Input: data/processed/cleaned_sales_data.csv
=============================================================================
"""

import os
import warnings
import logging

import numpy  as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")                            # non-interactive backend for CI
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns

from prophet            import Prophet
from prophet.diagnostics import cross_validation, performance_metrics
from prophet.plot        import plot_cross_validation_metric

warnings.filterwarnings("ignore")
logging.getLogger("cmdstanpy").setLevel(logging.WARNING)

# ── Paths ────────────────────────────────────────────────────────────────────
DATA_PATH   = os.path.join("data", "processed", "cleaned_sales_data.csv")
OUTPUT_DIR  = os.path.join("reports")
os.makedirs(OUTPUT_DIR, exist_ok=True)

FORECAST_MONTHS = 6
CONFIDENCE      = 0.95


# ─────────────────────────────────────────────────────────────────────────────
# 1. LOAD & AGGREGATE
# ─────────────────────────────────────────────────────────────────────────────
def load_and_aggregate(path: str, freq: str = "MS") -> pd.DataFrame:
    """Load cleaned CSV → aggregate to monthly sales → Prophet format."""
    print(f"Loading: {path}")
    df = pd.read_csv(path, parse_dates=["order_date"])

    monthly = (
        df.groupby(pd.Grouper(key="order_date", freq=freq))
          .agg(
              y          = ("sales",   "sum"),
              profit     = ("profit",  "sum"),
              orders     = ("order_id", "nunique"),
              units      = ("quantity", "sum"),
          )
          .reset_index()
          .rename(columns={"order_date": "ds"})
    )

    # Prophet needs no zeros / missing months
    monthly = monthly[monthly["y"] > 0].reset_index(drop=True)
    print(f"Monthly observations: {len(monthly)}  |  Range: {monthly['ds'].min().date()} → {monthly['ds'].max().date()}")
    return monthly


# ─────────────────────────────────────────────────────────────────────────────
# 2. BUILD & FIT MODEL
# ─────────────────────────────────────────────────────────────────────────────
def build_model(df: pd.DataFrame) -> Prophet:
    """Configure and fit Prophet model with US holidays & custom seasonality."""
    model = Prophet(
        yearly_seasonality  = True,
        weekly_seasonality  = False,      # monthly data — no weekly pattern
        daily_seasonality   = False,
        seasonality_mode    = "multiplicative",
        changepoint_prior_scale     = 0.05,   # flexibility of trend
        seasonality_prior_scale     = 10,
        holidays_prior_scale        = 10,
        interval_width              = CONFIDENCE,
    )

    # Add US public holidays as regressors
    model.add_country_holidays(country_name="US")

    print("Fitting Prophet model …")
    model.fit(df[["ds", "y"]])
    print("Model fit complete ✓")
    return model


# ─────────────────────────────────────────────────────────────────────────────
# 3. FORECAST
# ─────────────────────────────────────────────────────────────────────────────
def forecast(model: Prophet, periods: int) -> pd.DataFrame:
    """Generate future dataframe and predict."""
    future   = model.make_future_dataframe(periods=periods, freq="MS")
    forecast = model.predict(future)
    return forecast


# ─────────────────────────────────────────────────────────────────────────────
# 4. CROSS-VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
def run_cross_validation(model: Prophet, df: pd.DataFrame):
    """Run time-series CV and return performance metrics."""
    n_months = len(df)
    if n_months < 18:
        print(f"Only {n_months} months — skipping CV (need ≥ 18)")
        return None, None

    horizon    = "90 days"
    initial    = f"{int(n_months * 0.6 * 30)} days"
    period     = "30 days"

    print(f"Running cross-validation: initial={initial}, period={period}, horizon={horizon}")
    df_cv  = cross_validation(model, initial=initial, period=period, horizon=horizon)
    df_pm  = performance_metrics(df_cv)

    mae  = df_pm["mae"].mean()
    rmse = df_pm["rmse"].mean()
    mape = df_pm["mape"].mean() * 100

    print(f"  MAE  : ${mae:>10,.2f}")
    print(f"  RMSE : ${rmse:>10,.2f}")
    print(f"  MAPE : {mape:>9.2f}%")
    return df_cv, df_pm


# ─────────────────────────────────────────────────────────────────────────────
# 5. VISUALISATIONS
# ─────────────────────────────────────────────────────────────────────────────
PALETTE = {
    "actual"  : "#1e3a5f",
    "forecast": "#e84393",
    "band"    : "#e84393",
    "trend"   : "#f5a623",
    "grid"    : "#e5e7eb",
}

def fmt_millions(x, _):
    return f"${x/1e6:.1f}M" if abs(x) >= 1e6 else f"${x/1e3:.0f}K"


def plot_forecast(df_history: pd.DataFrame, df_forecast: pd.DataFrame, save: bool = True):
    """Main forecast chart with actual vs predicted."""
    fig, axes = plt.subplots(2, 1, figsize=(14, 10), facecolor="#f8fafc")
    fig.suptitle(
        "Retail Sales Forecast — Next 6 Months",
        fontsize=18, fontweight="bold", color="#1e3a5f", y=0.97
    )

    # ── Upper: Full series ────────────────────────────────────────────────────
    ax = axes[0]
    ax.set_facecolor("#f8fafc")

    # Confidence band
    ax.fill_between(
        df_forecast["ds"],
        df_forecast["yhat_lower"],
        df_forecast["yhat_upper"],
        alpha=0.25, color=PALETTE["band"], label=f"{int(CONFIDENCE*100)}% CI"
    )

    # Predicted line
    ax.plot(df_forecast["ds"], df_forecast["yhat"],
            color=PALETTE["forecast"], linewidth=2.2, label="Forecast", zorder=3)

    # Actuals
    ax.scatter(df_history["ds"], df_history["y"],
               s=45, color=PALETTE["actual"], label="Actual", zorder=4)
    ax.plot(df_history["ds"], df_history["y"],
            color=PALETTE["actual"], linewidth=1.5, alpha=0.8, zorder=3)

    # Divider between history and forecast
    cutoff = df_history["ds"].max()
    ax.axvline(cutoff, color="#6b7280", linestyle="--", linewidth=1, alpha=0.7, label="Forecast Start")
    ax.annotate("← Actual | Forecast →",
                xy=(cutoff, ax.get_ylim()[1] * 0.92),
                fontsize=9, color="#6b7280", ha="center")

    ax.yaxis.set_major_formatter(mticker.FuncFormatter(fmt_millions))
    ax.set_title("Monthly Sales: Actual vs Forecast", fontsize=13, color="#374151", pad=8)
    ax.set_ylabel("Net Sales", fontsize=10)
    ax.legend(loc="upper left", fontsize=9, framealpha=0.9)
    ax.grid(axis="y", color=PALETTE["grid"], linewidth=0.8)
    ax.spines[["top", "right"]].set_visible(False)

    # ── Lower: Forecast-only period with value labels ─────────────────────────
    ax2 = axes[1]
    ax2.set_facecolor("#f8fafc")

    future_only = df_forecast[df_forecast["ds"] > cutoff].copy()
    x = range(len(future_only))
    months = future_only["ds"].dt.strftime("%b %Y")

    bars = ax2.bar(x, future_only["yhat"], color=PALETTE["forecast"], alpha=0.85, zorder=3)
    ax2.errorbar(
        x,
        future_only["yhat"],
        yerr=[
            future_only["yhat"] - future_only["yhat_lower"],
            future_only["yhat_upper"] - future_only["yhat"],
        ],
        fmt="none", color="#1e3a5f", capsize=5, linewidth=1.5, zorder=4,
    )

    for bar, val in zip(bars, future_only["yhat"]):
        ax2.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() * 1.02,
            fmt_millions(val, None),
            ha="center", va="bottom", fontsize=9, fontweight="bold", color="#1e3a5f"
        )

    ax2.set_xticks(list(x))
    ax2.set_xticklabels(months, fontsize=9)
    ax2.yaxis.set_major_formatter(mticker.FuncFormatter(fmt_millions))
    ax2.set_title("6-Month Forward Forecast with Confidence Intervals", fontsize=13, color="#374151", pad=8)
    ax2.set_ylabel("Predicted Sales", fontsize=10)
    ax2.grid(axis="y", color=PALETTE["grid"], linewidth=0.8)
    ax2.spines[["top", "right"]].set_visible(False)

    plt.tight_layout(rect=[0, 0, 1, 0.96])
    if save:
        path = os.path.join(OUTPUT_DIR, "sales_forecast.png")
        plt.savefig(path, dpi=150, bbox_inches="tight")
        print(f"Saved → {path}")
    plt.close()


def plot_components(model: Prophet, df_forecast: pd.DataFrame):
    """Prophet component decomposition."""
    fig = model.plot_components(df_forecast)
    fig.suptitle("Forecast Components: Trend & Seasonality", fontsize=14, fontweight="bold")
    path = os.path.join(OUTPUT_DIR, "forecast_components.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    print(f"Saved → {path}")
    plt.close(fig)


def plot_category_forecast(df_all: pd.DataFrame):
    """Fit and forecast per category, side by side."""
    categories = df_all["category"].dropna().unique() if "category" in df_all.columns else []
    if len(categories) == 0:
        return

    fig, axes = plt.subplots(1, len(categories), figsize=(6 * len(categories), 5),
                              facecolor="#f8fafc", sharey=False)
    if len(categories) == 1:
        axes = [axes]

    fig.suptitle("6-Month Sales Forecast by Category", fontsize=16, fontweight="bold",
                 color="#1e3a5f", y=1.02)

    colors = ["#1e3a5f", "#e84393", "#f5a623"]

    for ax, cat, col in zip(axes, categories, colors):
        cat_df = (
            df_all[df_all["category"] == cat]
            .groupby(pd.Grouper(key="order_date", freq="MS"))["sales"]
            .sum()
            .reset_index()
            .rename(columns={"order_date": "ds", "sales": "y"})
        )
        cat_df = cat_df[cat_df["y"] > 0]
        if len(cat_df) < 6:
            continue

        m = Prophet(yearly_seasonality=True, weekly_seasonality=False,
                    daily_seasonality=False, seasonality_mode="multiplicative",
                    interval_width=0.90, changepoint_prior_scale=0.05)
        m.fit(cat_df[["ds", "y"]])
        future    = m.make_future_dataframe(periods=6, freq="MS")
        fc        = m.predict(future)
        future_fc = fc[fc["ds"] > cat_df["ds"].max()]

        ax.fill_between(fc["ds"], fc["yhat_lower"], fc["yhat_upper"],
                        alpha=0.2, color=col)
        ax.plot(fc["ds"], fc["yhat"], color=col, linewidth=2)
        ax.scatter(cat_df["ds"], cat_df["y"], s=30, color=col)
        ax.axvline(cat_df["ds"].max(), color="#9ca3af", linestyle="--", linewidth=1)
        ax.yaxis.set_major_formatter(mticker.FuncFormatter(fmt_millions))
        ax.set_title(cat, fontsize=12, color=col, fontweight="bold")
        ax.grid(axis="y", color="#e5e7eb")
        ax.spines[["top", "right"]].set_visible(False)

    plt.tight_layout()
    path = os.path.join(OUTPUT_DIR, "category_forecast.png")
    plt.savefig(path, dpi=150, bbox_inches="tight")
    print(f"Saved → {path}")
    plt.close()


# ─────────────────────────────────────────────────────────────────────────────
# 6. EXPORT FORECAST TABLE
# ─────────────────────────────────────────────────────────────────────────────
def export_forecast(df_history: pd.DataFrame, df_forecast: pd.DataFrame):
    cutoff = df_history["ds"].max()
    future = df_forecast[df_forecast["ds"] > cutoff].copy()

    future = future[["ds", "yhat", "yhat_lower", "yhat_upper"]].rename(columns={
        "ds"         : "forecast_month",
        "yhat"       : "predicted_sales",
        "yhat_lower" : "lower_bound",
        "yhat_upper" : "upper_bound",
    })
    future["predicted_sales"] = future["predicted_sales"].round(2)
    future["lower_bound"]     = future["lower_bound"].round(2)
    future["upper_bound"]     = future["upper_bound"].round(2)

    path = os.path.join(OUTPUT_DIR, "forecast_table.csv")
    future.to_csv(path, index=False)
    print(f"\nForecast table saved → {path}")

    print("\n" + "═"*52)
    print("  6-MONTH SALES FORECAST SUMMARY")
    print("═"*52)
    for _, row in future.iterrows():
        month = row["forecast_month"].strftime("%B %Y")
        print(f"  {month:<15} ${row['predicted_sales']:>10,.2f}"
              f"  (${row['lower_bound']:,.2f} – ${row['upper_bound']:,.2f})")
    print("═"*52)
    print(f"  Total 6-mo forecast : ${future['predicted_sales'].sum():>12,.2f}")
    print("═"*52 + "\n")
    return future


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
def main():
    print("\n" + "═"*52)
    print("  SALES FORECASTING ENGINE — STARTING")
    print("═"*52 + "\n")

    # Load raw data for category-level chart
    raw_df = pd.read_csv(DATA_PATH, parse_dates=["order_date"])

    # Aggregate to monthly
    monthly_df = load_and_aggregate(DATA_PATH)

    # Fit model
    model = build_model(monthly_df)

    # Forecast 6 months ahead
    df_fc = forecast(model, periods=FORECAST_MONTHS)

    # Cross-validation
    _, df_perf = run_cross_validation(model, monthly_df)

    # Plots
    plot_forecast(monthly_df, df_fc)
    plot_components(model, df_fc)
    plot_category_forecast(raw_df)

    # Export forecast table
    export_forecast(monthly_df, df_fc)

    print("Forecasting complete. Check /reports/ for outputs.")


if __name__ == "__main__":
    main()
