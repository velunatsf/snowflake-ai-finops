-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Anomaly Detection Queries
-- Catch spend spikes before the monthly bill arrives
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role
-- FREQUENCY:     Weekly - catch spikes early
-- SIGNAL:        wow_pct > 200 = spend tripled - investigate immediately
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: Week-over-Week Cost Anomaly Detection
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Daily AI credits vs same day last week, % change
-- FIX: Budget email alerts, low-latency refresh (1hr vs 6.5hr)
-- ─────────────────────────────────────────────────────────────────────────────

WITH daily AS (
    SELECT USAGE_DATE::DATE AS day,
           SUM(CREDITS_BILLED) AS credits
    FROM   SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
    WHERE  SERVICE_TYPE IN ('AI_SERVICES','CORTEX_CODE_CLI','CORTEX_CODE_SNOWSIGHT',
                            'CORTEX_AGENTS','SNOWFLAKE_INTELLIGENCE')
      AND  USAGE_DATE >= DATEADD('day', -60, CURRENT_DATE())
    GROUP  BY day
)
SELECT day, credits,
       LAG(credits, 7) OVER (ORDER BY day)   AS last_week,
       ROUND((credits - LAG(credits, 7) OVER (ORDER BY day))
             / NULLIF(LAG(credits, 7) OVER (ORDER BY day), 0)
             * 100, 1)                         AS wow_pct
FROM   daily
ORDER  BY day DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 2: Hourly AI Spend Trend (Last 24 Hours)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Hourly breakdown of AI calls and credit consumption
-- USE FOR: Identifying sudden usage spikes within a single day
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    DATE_TRUNC('hour', START_TIME)              AS hour_bucket,
    FUNCTION_NAME,
    COUNT(*)                                    AS ai_calls,
    ROUND(SUM(CREDITS), 4)                      AS ai_credits,
    ROUND(SUM(CREDITS) * 3, 2)                  AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -1, CURRENT_TIMESTAMP)
GROUP BY 1, 2
ORDER BY 1 DESC, ai_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Daily AI Metering Trend (Last 90 Days)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Long-term daily credit trend across all AI service types
-- USE FOR: Spotting gradual creep or sudden step changes
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    USAGE_DATE::DATE AS day,
    SERVICE_TYPE,
    SUM(CREDITS_BILLED) AS daily_credits,
    SUM(CREDITS_USED) AS daily_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE SERVICE_TYPE IN ('AI_SERVICES','CORTEX_CODE_CLI','CORTEX_CODE_SNOWSIGHT',
                       'CORTEX_AGENTS','SNOWFLAKE_INTELLIGENCE')
  AND USAGE_DATE >= DATEADD('day', -90, CURRENT_DATE())
GROUP BY day, SERVICE_TYPE
ORDER BY day DESC, daily_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 4: User Spend Anomaly (Sudden Increase by User)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Users whose spend this week is 3x+ their average
-- ─────────────────────────────────────────────────────────────────────────────

WITH user_weekly AS (
    SELECT
        u.NAME AS user_name,
        DATE_TRUNC('week', h.START_TIME) AS week,
        SUM(h.CREDITS) AS weekly_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
    WHERE h.START_TIME >= DATEADD('day', -60, CURRENT_TIMESTAMP())
    GROUP BY u.NAME, week
)
SELECT
    user_name,
    week,
    weekly_credits,
    AVG(weekly_credits) OVER (PARTITION BY user_name ORDER BY week ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS avg_prev_4_weeks,
    ROUND(weekly_credits / NULLIF(AVG(weekly_credits) OVER (PARTITION BY user_name ORDER BY week ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING), 0), 1) AS multiplier
FROM user_weekly
QUALIFY multiplier > 3
ORDER BY week DESC, weekly_credits DESC;
