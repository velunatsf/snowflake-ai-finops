-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Cortex Code Usage Tracking
-- Monitor Snowflake CoCo CLI and Snowsight AI assistant usage
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role
-- FREQUENCY:     Weekly - track developer AI assistant costs
-- NOTE:          These are separate views from general query_history
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: Snowflake CoCo CLI Usage
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Token and credit breakdown for CLI-based AI assistant usage
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    user_name,
    DATE_TRUNC('day', event_timestamp)          AS usage_date,
    COUNT(*)                                    AS sessions,
    SUM(total_tokens)                           AS total_tokens,
    ROUND(SUM(total_credits), 4)                AS total_credits,
    ROUND(SUM(total_credits) * 3, 2)            AS est_dollars
FROM snowflake.account_usage.cortex_code_cli_usage_history
WHERE event_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY 1, 2
ORDER BY 2 DESC, total_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 2: Cortex Code Snowsight Usage
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Token and credit breakdown for in-browser AI assistant usage
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    user_name,
    DATE_TRUNC('day', event_timestamp)          AS usage_date,
    COUNT(*)                                    AS sessions,
    SUM(total_tokens)                           AS total_tokens,
    ROUND(SUM(total_credits), 4)                AS total_credits,
    ROUND(SUM(total_credits) * 3, 2)            AS est_dollars
FROM snowflake.account_usage.cortex_code_snowsight_usage_history
WHERE event_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY 1, 2
ORDER BY 2 DESC, total_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Combined Cortex Code Spend (CLI + Snowsight)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Total Cortex Code AI spend from metering view
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    SERVICE_TYPE,
    USAGE_DATE,
    SUM(CREDITS_BILLED) AS credits_billed,
    SUM(CREDITS_USED) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE SERVICE_TYPE IN ('CORTEX_CODE_CLI', 'CORTEX_CODE_SNOWSIGHT')
  AND USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY SERVICE_TYPE, USAGE_DATE
ORDER BY USAGE_DATE DESC, SERVICE_TYPE;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 4: Top Cortex Code Users (Last 30 Days)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Which developers consume the most AI credits via Cortex Code
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    user_name,
    SUM(total_tokens) AS total_tokens,
    ROUND(SUM(total_credits), 4) AS total_credits,
    ROUND(SUM(total_credits) * 3, 2) AS est_dollars,
    COUNT(*) AS total_sessions
FROM (
    SELECT user_name, total_tokens, total_credits
    FROM snowflake.account_usage.cortex_code_cli_usage_history
    WHERE event_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP)
    UNION ALL
    SELECT user_name, total_tokens, total_credits
    FROM snowflake.account_usage.cortex_code_snowsight_usage_history
    WHERE event_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP)
) combined
GROUP BY user_name
ORDER BY total_credits DESC;
