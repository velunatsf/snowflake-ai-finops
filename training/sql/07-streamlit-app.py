# ═══════════════════════════════════════════════════════════════════════════
# Snowflake Cortex AI Cost Dashboard
# FinOps for Snowflake AI - Module 08
# ═══════════════════════════════════════════════════════════════════════════
#
# DEPLOYMENT:
#   1. Snowsight → Projects → Streamlit → + Streamlit App
#   2. Name: CORTEX_AI_COST_DASHBOARD
#   3. Database: cortex_lab | Schema: ai_workshop
#   4. Paste this code → Run
#
# NOTE: account_usage views have ~45 min latency for recent data
# ═══════════════════════════════════════════════════════════════════════════

import streamlit as st
import pandas as pd
import altair as alt
from snowflake.snowpark.context import get_active_session

# ─── Get Snowflake Session ────────────────────────────────────────────────────
session = get_active_session()

# ─── Page Configuration ───────────────────────────────────────────────────────
st.set_page_config(
    page_title="Cortex AI Cost Dashboard",
    page_icon="❄️",
    layout="wide"
)

# ─── Custom Styling ───────────────────────────────────────────────────────────
st.markdown("""
<style>
    .main-header {
        background: linear-gradient(135deg, #0B2B4E 0%, #1a4a7a 100%);
        padding: 1.5rem 2rem;
        border-radius: 12px;
        margin-bottom: 1.5rem;
    }
    .main-header h1 {
        color: #29B5E8;
        margin: 0;
        font-size: 1.8rem;
    }
    .main-header p {
        color: #C9EBF7;
        margin: 0.3rem 0 0;
        font-size: 0.9rem;
    }
    .cost-alert {
        background: rgba(239, 68, 68, 0.1);
        border-left: 4px solid #EF4444;
        padding: 1rem;
        border-radius: 8px;
        margin: 1rem 0;
    }
    .stMetric {
        background: white;
        padding: 1rem;
        border-radius: 10px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.05);
    }
</style>
""", unsafe_allow_html=True)

# ─── Header ───────────────────────────────────────────────────────────────────
st.markdown("""
<div class="main-header">
    <h1>❄️ Cortex AI Cost Dashboard</h1>
    <p>Real-time FinOps View · Snowflake Cortex Token & Credit Tracking</p>
</div>
""", unsafe_allow_html=True)

# ─── Sidebar Filters ──────────────────────────────────────────────────────────
st.sidebar.header("🔧 Filters")

days = st.sidebar.selectbox(
    "Time Range",
    options=[1, 7, 14, 30],
    index=1,
    format_func=lambda x: f"Last {x} days"
)

user_filter = st.sidebar.text_input(
    "Filter by User (optional)",
    placeholder="Enter username"
)

func_filter = st.sidebar.selectbox(
    "Cortex Function",
    ["All", "AI_COMPLETE", "AI_SENTIMENT", "AI_SUMMARIZE_AGG",
     "AI_CLASSIFY", "AI_TRANSLATE", "AI_EMBED"]
)

st.sidebar.markdown("---")
st.sidebar.markdown("""
**Note:** Account usage views have  
~45 min latency for recent data.
""")

# ─── Build Dynamic WHERE Clauses ──────────────────────────────────────────────
user_clause = f"AND u.NAME ILIKE '%{user_filter}%'" if user_filter else ""
func_clause = f"AND c.FUNCTION_NAME = '{func_filter}'" if func_filter != "All" else ""


# ═══════════════════════════════════════════════════════════════════════════════
#  ROW 1: KPI Metrics
# ═══════════════════════════════════════════════════════════════════════════════

try:
    kpi_query = f"""
        SELECT
            COUNT(*)                                    AS total_queries,
            COALESCE(ROUND(SUM(c.CREDITS), 4), 0)      AS total_credits,
            COALESCE(ROUND(AVG(c.CREDITS), 6), 0)      AS avg_credits,
            COUNT(DISTINCT u.NAME)                      AS unique_users,
            COALESCE(ROUND(SUM(c.CREDITS) * 3, 2), 0)  AS est_dollar_cost
        FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
        LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u
            ON c.USER_ID = u.USER_ID
        WHERE c.START_TIME >= DATEADD(day, -{days}, CURRENT_TIMESTAMP)
          {user_clause}
          {func_clause}
    """
    kpi_df = session.sql(kpi_query).to_pandas()

    k1, k2, k3, k4, k5 = st.columns(5)

    with k1:
        st.metric("AI Queries", f"{int(kpi_df['TOTAL_QUERIES'][0]):,}")
    with k2:
        st.metric("Total Credits", f"{kpi_df['TOTAL_CREDITS'][0]:,.4f}")
    with k3:
        st.metric("Avg Credits/Call", f"{kpi_df['AVG_CREDITS'][0]:,.6f}")
    with k4:
        st.metric("Unique Users", f"{int(kpi_df['UNIQUE_USERS'][0]):,}")
    with k5:
        st.metric("Est. Cost (@ $3/cr)", f"${kpi_df['EST_DOLLAR_COST'][0]:,.2f}")

except Exception as e:
    st.error(f"Error loading KPIs: {str(e)}")
    st.info("Ensure you have access to SNOWFLAKE.ACCOUNT_USAGE views.")

st.divider()


# ═══════════════════════════════════════════════════════════════════════════════
#  ROW 2: Hourly Credit Consumption + Credits by Function
# ═══════════════════════════════════════════════════════════════════════════════

left_col, right_col = st.columns([3, 2])

with left_col:
    st.subheader("📈 Hourly Credit Consumption")

    try:
        trend_query = f"""
            SELECT
                DATE_TRUNC('hour', c.START_TIME)        AS hour_bucket,
                COUNT(*)                                AS queries,
                COALESCE(ROUND(SUM(c.CREDITS), 4), 0)  AS credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
            LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u
                ON c.USER_ID = u.USER_ID
            WHERE c.START_TIME >= DATEADD(day, -{days}, CURRENT_TIMESTAMP)
              {user_clause}
            GROUP BY 1
            ORDER BY 1
        """
        trend_df = session.sql(trend_query).to_pandas()

        if not trend_df.empty:
            chart = alt.Chart(trend_df).mark_area(
                color='#29B5E8',
                opacity=0.7,
                line=True
            ).encode(
                x=alt.X('HOUR_BUCKET:T', title='Time', axis=alt.Axis(format='%m/%d %H:%M')),
                y=alt.Y('CREDITS:Q', title='Credits Used'),
                tooltip=[
                    alt.Tooltip('HOUR_BUCKET:T', title='Time', format='%Y-%m-%d %H:%M'),
                    alt.Tooltip('CREDITS:Q', title='Credits', format=',.4f'),
                    alt.Tooltip('QUERIES:Q', title='Queries')
                ]
            ).properties(height=300)

            st.altair_chart(chart, use_container_width=True)
        else:
            st.info("No Cortex queries found in the selected time range.")

    except Exception as e:
        st.error(f"Error loading trend data: {str(e)}")

with right_col:
    st.subheader("🎯 Credits by Function")

    try:
        func_query = f"""
            SELECT
                c.FUNCTION_NAME                         AS func_name,
                COUNT(*)                                AS calls,
                COALESCE(ROUND(SUM(c.CREDITS), 4), 0)  AS credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
            LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u
                ON c.USER_ID = u.USER_ID
            WHERE c.START_TIME >= DATEADD(day, -{days}, CURRENT_TIMESTAMP)
              {user_clause}
            GROUP BY 1
            HAVING SUM(c.CREDITS) > 0
            ORDER BY credits DESC
            LIMIT 10
        """
        func_df = session.sql(func_query).to_pandas()

        if not func_df.empty:
            bar_chart = alt.Chart(func_df).mark_bar(
                color='#29B5E8',
                cornerRadiusEnd=4
            ).encode(
                x=alt.X('CREDITS:Q', title='Credits'),
                y=alt.Y('FUNC_NAME:N', sort='-x', title='Function'),
                tooltip=[
                    alt.Tooltip('FUNC_NAME:N', title='Function'),
                    alt.Tooltip('CREDITS:Q', title='Credits', format=',.4f'),
                    alt.Tooltip('CALLS:Q', title='Calls')
                ]
            ).properties(height=300)

            st.altair_chart(bar_chart, use_container_width=True)
        else:
            st.info("No function breakdown available.")

    except Exception as e:
        st.error(f"Error loading function data: {str(e)}")

st.divider()


# ═══════════════════════════════════════════════════════════════════════════════
#  ROW 3: Cost by Model (COMPLETE calls)
# ═══════════════════════════════════════════════════════════════════════════════

st.subheader("🤖 Cost by Model (AI_COMPLETE calls)")

try:
    model_query = f"""
        SELECT
            c.MODEL_NAME                                AS model_name,
            COUNT(*)                                    AS calls,
            COALESCE(ROUND(SUM(c.CREDITS), 4), 0)      AS total_credits,
            COALESCE(ROUND(AVG(c.CREDITS), 6), 0)      AS credits_per_call
        FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
        LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u
            ON c.USER_ID = u.USER_ID
        WHERE c.START_TIME >= DATEADD(day, -{days}, CURRENT_TIMESTAMP)
          AND c.FUNCTION_NAME IN ('COMPLETE', 'AI_COMPLETE')
          {user_clause}
        GROUP BY 1
        HAVING SUM(c.CREDITS) > 0
        ORDER BY total_credits DESC
    """
    model_df = session.sql(model_query).to_pandas()

    if not model_df.empty:
        st.dataframe(
            model_df,
            use_container_width=True,
            hide_index=True,
            column_config={
                "MODEL_NAME": st.column_config.TextColumn("Model"),
                "CALLS": st.column_config.NumberColumn("Calls", format="%d"),
                "TOTAL_CREDITS": st.column_config.NumberColumn("Total Credits", format="%.4f"),
                "CREDITS_PER_CALL": st.column_config.NumberColumn("Credits/Call", format="%.6f")
            }
        )
    else:
        st.info("No AI_COMPLETE() calls found in the selected time range.")

except Exception as e:
    st.error(f"Error loading model data: {str(e)}")

st.divider()


# ═══════════════════════════════════════════════════════════════════════════════
#  ROW 4: Shadow Waste Detection (Attribution + WoW Anomaly)
# ═══════════════════════════════════════════════════════════════════════════════

st.subheader("🔍 Shadow Waste Detection")

sw_left, sw_right = st.columns(2)

# ─── Attribution Coverage (Tagged vs Untagged) ────────────────────────────────
with sw_left:
    st.markdown("##### Attribution Coverage")

    try:
        attr_query = f"""
            SELECT CASE WHEN QUERY_TAG IS NOT NULL AND QUERY_TAG != ''
                        THEN 'Tagged' ELSE 'Untagged'
                   END                              AS attribution,
                   COUNT(*)                          AS calls,
                   COALESCE(SUM(TOKEN_CREDITS), 0)   AS credits
            FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
            WHERE  USAGE_TIME >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
            GROUP  BY attribution
        """
        attr_df = session.sql(attr_query).to_pandas()

        if not attr_df.empty and float(attr_df['CREDITS'].sum()) > 0:
            total_cr = float(attr_df['CREDITS'].sum())
            attr_df['PCT'] = (attr_df['CREDITS'] / total_cr * 100).round(1)

            donut = alt.Chart(attr_df).mark_arc(
                innerRadius=50, outerRadius=90
            ).encode(
                theta=alt.Theta('CREDITS:Q'),
                color=alt.Color('ATTRIBUTION:N',
                    scale=alt.Scale(
                        domain=['Tagged', 'Untagged'],
                        range=['#00C49A', '#EF4444']
                    ),
                    legend=alt.Legend(title="")
                ),
                tooltip=[
                    alt.Tooltip('ATTRIBUTION:N', title='Status'),
                    alt.Tooltip('CREDITS:Q', title='Credits', format=',.4f'),
                    alt.Tooltip('CALLS:Q', title='Calls'),
                    alt.Tooltip('PCT:Q', title='% of Total', format='.1f')
                ]
            ).properties(height=220)

            st.altair_chart(donut, use_container_width=True)

            tagged_row = attr_df[attr_df['ATTRIBUTION'] == 'Tagged']
            tagged_pct = float(tagged_row['PCT'].iloc[0]) if not tagged_row.empty else 0
            tag_color = "#00C49A" if tagged_pct >= 90 else "#F59E0B" if tagged_pct >= 50 else "#EF4444"

            st.markdown(f"""
            <div style='text-align: center; padding: 0.5rem;'>
                <span style='font-size: 1.8rem; font-weight: 700; color: {tag_color};'>{tagged_pct:.1f}%</span>
                <span style='color: #6b7280; font-size: 0.85rem;'> tagged (target: >90%)</span>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.info("No CORTEX_AISQL data found. Attribution tracking requires QUERY_TAG usage.")

    except Exception as e:
        st.warning(f"Could not load attribution data: {str(e)}")

# ─── Week-over-Week Cost Anomaly Detection ────────────────────────────────────
with sw_right:
    st.markdown("##### Week-over-Week Anomaly Detection")

    try:
        wow_query = """
            WITH daily AS (
                SELECT USAGE_DATE::DATE AS day,
                       SUM(CREDITS_BILLED) AS credits
                FROM   SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
                WHERE  SERVICE_TYPE IN ('AI_SERVICES','CORTEX_CODE_CLI','CORTEX_CODE_SNOWSIGHT')
                  AND  USAGE_DATE >= DATEADD('day', -60, CURRENT_DATE())
                GROUP  BY day
            )
            SELECT day, credits,
                   LAG(credits, 7) OVER (ORDER BY day)   AS last_week,
                   ROUND((credits - LAG(credits, 7) OVER (ORDER BY day))
                         / NULLIF(LAG(credits, 7) OVER (ORDER BY day), 0)
                         * 100, 1)                         AS wow_pct
            FROM   daily
            ORDER  BY day DESC
            LIMIT 30
        """
        wow_df = session.sql(wow_query).to_pandas()

        if not wow_df.empty and wow_df['CREDITS'].sum() > 0:
            wow_chart = alt.Chart(wow_df.dropna(subset=['WOW_PCT'])).mark_bar(
                cornerRadiusEnd=3
            ).encode(
                x=alt.X('DAY:T', title='Date', axis=alt.Axis(format='%m/%d')),
                y=alt.Y('WOW_PCT:Q', title='WoW Change %'),
                color=alt.when(
                    alt.datum.WOW_PCT > 200
                ).then(alt.value('#EF4444')).when(
                    alt.datum.WOW_PCT > 50
                ).then(alt.value('#F59E0B')).otherwise(
                    alt.value('#29B5E8')
                ),
                tooltip=[
                    alt.Tooltip('DAY:T', title='Date', format='%Y-%m-%d'),
                    alt.Tooltip('CREDITS:Q', title='Credits', format=',.4f'),
                    alt.Tooltip('LAST_WEEK:Q', title='Last Week', format=',.4f'),
                    alt.Tooltip('WOW_PCT:Q', title='WoW %', format='+.1f')
                ]
            ).properties(height=220)

            rule = alt.Chart(pd.DataFrame({'y': [50]})).mark_rule(
                color='#F59E0B', strokeDash=[4, 4], strokeWidth=1.5
            ).encode(y='y:Q')

            st.altair_chart(wow_chart + rule, use_container_width=True)

            max_wow = wow_df['WOW_PCT'].max()
            if pd.notna(max_wow) and max_wow > 50:
                st.markdown(f"""
                <div class="cost-alert" style="padding: 0.5rem 1rem; margin-top: 0;">
                    Peak spike: <strong>+{max_wow:.1f}%</strong> vs prior week - review recent schedule changes.
                </div>
                """, unsafe_allow_html=True)
            else:
                st.caption("No significant anomalies detected (threshold: >50% WoW change).")
        else:
            st.info("No AI metering data found for anomaly detection.")

    except Exception as e:
        st.warning(f"Could not load anomaly data: {str(e)}")

st.divider()


# ═══════════════════════════════════════════════════════════════════════════════
#  DETAILS: Additional Panels (expandable)
# ═══════════════════════════════════════════════════════════════════════════════

with st.expander("📋 More Details", expanded=False):

    # ─── Most Expensive AI Queries ────────────────────────────────────────────
    st.subheader("💰 Most Expensive AI Queries")

    try:
        top_query = f"""
            SELECT
                c.QUERY_ID,
                u.NAME                                  AS user_name,
                c.FUNCTION_NAME,
                c.MODEL_NAME,
                ROUND(c.CREDITS, 6)                     AS credits,
                c.START_TIME
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
            LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u
                ON c.USER_ID = u.USER_ID
            WHERE c.START_TIME >= DATEADD(day, -{days}, CURRENT_TIMESTAMP)
              AND c.CREDITS > 0
              {user_clause}
              {func_clause}
            ORDER BY c.CREDITS DESC
            LIMIT 20
        """
        top_df = session.sql(top_query).to_pandas()

        if not top_df.empty:
            st.dataframe(
                top_df,
                use_container_width=True,
                hide_index=True,
                column_config={
                    "QUERY_ID": st.column_config.TextColumn("Query ID", width="small"),
                    "USER_NAME": st.column_config.TextColumn("User"),
                    "FUNCTION_NAME": st.column_config.TextColumn("Function"),
                    "MODEL_NAME": st.column_config.TextColumn("Model"),
                    "CREDITS": st.column_config.NumberColumn("Credits", format="%.6f"),
                    "START_TIME": st.column_config.DatetimeColumn("Time", format="MM/DD HH:mm")
                }
            )
        else:
            st.info("No expensive queries found in the selected time range.")

    except Exception as e:
        st.error(f"Error loading top queries: {str(e)}")

    st.divider()

    # ─── AI Credits Transition ────────────────────────────────────────────────
    st.subheader("⚡ AI Credits Transition - SERVICE_TYPE Breakdown")

    st.markdown("""
    <div class="cost-alert">
        <strong>Visibility Gap:</strong> AI spend is split across multiple
        <code>SERVICE_TYPE</code> values. If your dashboards only filter on
        <code>AI_SERVICES</code>, you will miss spend billed under the new types.
    </div>
    """, unsafe_allow_html=True)

    try:
        ai_credits_query = f"""
            SELECT
                SERVICE_TYPE,
                MIN(USAGE_DATE)                         AS first_seen,
                MAX(USAGE_DATE)                         AS last_seen,
                ROUND(SUM(CREDITS_BILLED), 4)           AS total_credits_billed,
                ROUND(SUM(CREDITS_USED), 4)             AS total_credits_used,
                ROUND(SUM(CREDITS_BILLED) * 3, 2)       AS est_dollar_cost
            FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
            WHERE SERVICE_TYPE IN (
                'AI_SERVICES',
                'CORTEX_AGENTS',
                'CORTEX_CODE_CLI',
                'CORTEX_CODE_SNOWSIGHT',
                'SNOWFLAKE_INTELLIGENCE'
            )
              AND USAGE_DATE >= DATEADD(day, -{days}, CURRENT_DATE)
              AND CREDITS_BILLED > 0
            GROUP BY SERVICE_TYPE
            ORDER BY total_credits_billed DESC
        """
        ai_credits_df = session.sql(ai_credits_query).to_pandas()

        if not ai_credits_df.empty:
            total_ai = float(ai_credits_df['TOTAL_CREDITS_BILLED'].sum())
            total_ai_dollar = float(ai_credits_df['EST_DOLLAR_COST'].sum())
            n_types = len(ai_credits_df)

            c1, c2, c3 = st.columns(3)
            with c1:
                st.metric("AI SERVICE_TYPEs Active", f"{n_types} of 5")
            with c2:
                st.metric("Total AI Credits", f"{total_ai:,.4f}")
            with c3:
                st.metric("Est. Cost (@ $3/cr)", f"${total_ai_dollar:,.2f}")

            st.dataframe(
                ai_credits_df,
                use_container_width=True,
                hide_index=True,
                column_config={
                    "SERVICE_TYPE": st.column_config.TextColumn("Service Type"),
                    "FIRST_SEEN": st.column_config.DateColumn("First Seen", format="YYYY-MM-DD"),
                    "LAST_SEEN": st.column_config.DateColumn("Last Seen", format="YYYY-MM-DD"),
                    "TOTAL_CREDITS_BILLED": st.column_config.NumberColumn("Credits Billed", format="%.4f"),
                    "TOTAL_CREDITS_USED": st.column_config.NumberColumn("Credits Used", format="%.4f"),
                    "EST_DOLLAR_COST": st.column_config.NumberColumn("Est. Cost", format="$%.2f")
                }
            )
        else:
            st.info("No AI Credit service types detected yet. "
                    "Tracked types: AI_SERVICES, CORTEX_AGENTS, "
                    "CORTEX_CODE_CLI, CORTEX_CODE_SNOWSIGHT, SNOWFLAKE_INTELLIGENCE.")

    except Exception as e:
        st.warning(f"Could not query METERING_DAILY_HISTORY: {str(e)}")


# ─── Footer ───────────────────────────────────────────────────────────────────
st.divider()

st.markdown("""
<div style='text-align: center; color: #6b7280; font-size: 0.85rem; padding: 1rem;'>
    <strong>FinOps for Snowflake AI</strong><br>
    <br>
    Pricing based on $3/credit estimate · Validate against your contract rate<br>
    Account usage views have ~45 min latency
</div>
""", unsafe_allow_html=True)
