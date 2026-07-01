"""
Snowflake AI Cost Usage Dashboard

Displays AI credit consumption across Cortex AI SQL, Cortex AI Functions,
Cortex Search, Document AI, and AI Metering services. Data is fetched via
the DEMO_DB.AGENTS.GET_AI_COST_USAGE stored procedure on Snowflake.
"""

from datetime import date, timedelta

import altair as alt
import pandas as pd
import streamlit as st

st.set_page_config(
    page_title="AI cost usage",
    page_icon=":material/monetization_on:",
    layout="wide",
)

CHART_HEIGHT = 350
TIME_RANGES = ["7d", "14d", "30d", "60d", "90d"]


# =============================================================================
# Snowflake connection and data loading
# =============================================================================


def get_connection():
    try:
        return st.connection("snowflake")
    except Exception as e:
        st.error(f"Failed to connect to Snowflake: {e}")
        st.info(
            "Configure your Snowflake connection in `.streamlit/secrets.toml` "
            "or via environment variables."
        )
        st.stop()


def days_from_range(time_range: str) -> int:
    return int(time_range.replace("d", ""))


def _call_procedure(report_type: str, days_back: int) -> pd.DataFrame:
    conn = get_connection()
    session = conn.session()
    sp_df = session.sql(
        f"CALL DEMO_DB.AGENTS.GET_AI_COST_USAGE('{report_type}', {days_back}::FLOAT)"
    )
    df = sp_df.to_pandas()
    df.columns = df.columns.str.lower()
    return df


@st.cache_data(ttl=600, show_spinner="Loading summary...")
def load_summary(days_back: int) -> pd.DataFrame:
    return _call_procedure("summary", days_back)


@st.cache_data(ttl=600, show_spinner="Loading AI SQL breakdown...")
def load_aisql_by_model(days_back: int) -> pd.DataFrame:
    return _call_procedure("cortex_aisql_by_model", days_back)


@st.cache_data(ttl=600, show_spinner="Loading AI functions breakdown...")
def load_ai_functions(days_back: int) -> pd.DataFrame:
    return _call_procedure("ai_functions_by_model", days_back)


@st.cache_data(ttl=600, show_spinner="Loading search breakdown...")
def load_search(days_back: int) -> pd.DataFrame:
    return _call_procedure("cortex_search_by_service", days_back)


@st.cache_data(ttl=600, show_spinner="Loading daily trend...")
def load_daily_trend(days_back: int) -> pd.DataFrame:
    return _call_procedure("daily_trend", days_back)


# =============================================================================
# Chart helpers
# =============================================================================


def make_bar_chart(df: pd.DataFrame, x: str, y: str, color: str | None = None) -> alt.Chart:
    encoding = {
        "x": alt.X(f"{x}:N", sort="-y", title=None),
        "y": alt.Y(f"{y}:Q", title="Credits"),
        "tooltip": [
            alt.Tooltip(f"{x}:N"),
            alt.Tooltip(f"{y}:Q", title="Credits", format=",.4f"),
        ],
    }
    if color:
        encoding["color"] = alt.Color(f"{color}:N", legend=alt.Legend(orient="bottom"))
        encoding["tooltip"].append(alt.Tooltip(f"{color}:N"))

    return alt.Chart(df).mark_bar().encode(**encoding).properties(height=CHART_HEIGHT)


def make_line_chart(df: pd.DataFrame, x: str, y: str) -> alt.Chart:
    return (
        alt.Chart(df)
        .mark_line(point=True)
        .encode(
            x=alt.X(f"{x}:T", title=None),
            y=alt.Y(f"{y}:Q", title="Credits"),
            tooltip=[
                alt.Tooltip(f"{x}:T", title="Date", format="%Y-%m-%d"),
                alt.Tooltip(f"{y}:Q", title="Credits", format=",.4f"),
            ],
        )
        .properties(height=CHART_HEIGHT)
        .interactive()
    )


# =============================================================================
# Page header
# =============================================================================

def render_header():
    with st.container(
        horizontal=True, horizontal_alignment="distribute", vertical_alignment="center"
    ):
        st.markdown("# :material/monetization_on: AI cost usage")
        if st.button(":material/restart_alt: Reset", type="tertiary"):
            st.session_state.clear()
            st.rerun()


# =============================================================================
# Layout
# =============================================================================

get_connection()
render_header()

# Sidebar controls
with st.sidebar:
    st.markdown("### :material/tune: Controls")
    time_range = st.segmented_control(
        "Time range", TIME_RANGES, default="30d", key="time_range"
    )
    days_back = days_from_range(time_range or "30d")
    st.caption(f"Showing last {days_back} days of AI usage")

# -- Load all data --
summary = load_summary(days_back)
daily_trend = load_daily_trend(days_back)
aisql = load_aisql_by_model(days_back)
ai_funcs = load_ai_functions(days_back)
search = load_search(days_back)

# =============================================================================
# Row 1: KPI metrics
# =============================================================================

total_credits = summary["total_credits"].sum() if not summary.empty else 0
total_calls = summary["total_calls"].sum() if not summary.empty else 0
categories_active = summary[summary["total_credits"].notna() & (summary["total_credits"] > 0)].shape[0] if not summary.empty else 0

with st.container(horizontal=True):
    st.metric("Total AI credits", f"{total_credits:,.4f}", border=True)
    st.metric("Total API calls", f"{int(total_calls):,}", border=True)
    st.metric("Active services", f"{categories_active}", border=True)

# =============================================================================
# Row 2: Summary table + daily trend
# =============================================================================

col_summary, col_trend = st.columns(2)

with col_summary:
    with st.container(border=True):
        st.markdown("**Cost by service category**")
        if not summary.empty:
            display_df = summary[["category", "total_calls", "total_credits"]].copy()
            display_df = display_df.rename(columns={
                "category": "Service",
                "total_calls": "Calls",
                "total_credits": "Credits",
            })
            st.dataframe(
                display_df,
                hide_index=True,
                column_config={
                    "Credits": st.column_config.NumberColumn(format="%.4f"),
                },
                height=CHART_HEIGHT,
            )
        else:
            st.info("No AI usage data found for this period.")

with col_trend:
    with st.container(border=True):
        st.markdown("**Daily credit trend**")
        if not daily_trend.empty:
            trend_df = daily_trend[["category", "total_credits"]].copy()
            trend_df = trend_df.rename(columns={"category": "date", "total_credits": "credits"})
            trend_df["date"] = pd.to_datetime(trend_df["date"])
            trend_df = trend_df.sort_values("date")
            st.altair_chart(make_line_chart(trend_df, "date", "credits"))
        else:
            st.info("No daily trend data found for this period.")

# =============================================================================
# Row 3: AI SQL breakdown + AI Functions breakdown
# =============================================================================

col_aisql, col_funcs = st.columns(2)

with col_aisql:
    with st.container(border=True):
        st.markdown("**Cortex AI SQL by model**")
        if not aisql.empty:
            view = st.segmented_control(
                "View",
                [":material/bar_chart:", ":material/table:"],
                default=":material/bar_chart:",
                key="aisql_view",
                label_visibility="collapsed",
            )
            chart_df = aisql[["category", "detail_1", "total_credits"]].copy()
            chart_df = chart_df.rename(columns={
                "category": "model",
                "detail_1": "function",
                "total_credits": "credits",
            })
            if "table" in (view or ""):
                st.dataframe(
                    chart_df,
                    hide_index=True,
                    column_config={"credits": st.column_config.NumberColumn(format="%.4f")},
                    height=CHART_HEIGHT,
                )
            else:
                st.altair_chart(make_bar_chart(chart_df, "function", "credits", "model"))
        else:
            st.info("No Cortex AI SQL usage found.")

with col_funcs:
    with st.container(border=True):
        st.markdown("**AI functions by model**")
        if not ai_funcs.empty:
            view = st.segmented_control(
                "View",
                [":material/bar_chart:", ":material/table:"],
                default=":material/bar_chart:",
                key="funcs_view",
                label_visibility="collapsed",
            )
            chart_df = ai_funcs[["category", "detail_1", "total_credits"]].copy()
            chart_df = chart_df.rename(columns={
                "category": "function",
                "detail_1": "model",
                "total_credits": "credits",
            })
            if "table" in (view or ""):
                st.dataframe(
                    chart_df,
                    hide_index=True,
                    column_config={"credits": st.column_config.NumberColumn(format="%.4f")},
                    height=CHART_HEIGHT,
                )
            else:
                st.altair_chart(make_bar_chart(chart_df, "function", "credits", "model"))
        else:
            st.info("No AI functions usage found.")

# =============================================================================
# Row 4: Cortex Search + Raw data
# =============================================================================

col_search, col_raw = st.columns(2)

with col_search:
    with st.container(border=True):
        st.markdown("**Cortex Search by service**")
        if not search.empty and search["total_credits"].notna().any():
            chart_df = search[["category", "detail_1", "total_credits"]].copy()
            chart_df = chart_df.rename(columns={
                "category": "service",
                "detail_1": "database_schema",
                "total_credits": "credits",
            })
            st.altair_chart(make_bar_chart(chart_df, "service", "credits"))
        else:
            st.info("No Cortex Search usage found for this period.")

with col_raw:
    with st.container(border=True):
        st.markdown("**Full summary data**")
        if not summary.empty:
            st.dataframe(summary, hide_index=True, height=CHART_HEIGHT)
        else:
            st.info("No data available.")

st.caption(f":material/schedule: Data refreshed from SNOWFLAKE.ACCOUNT_USAGE views (up to 45 min latency)")
