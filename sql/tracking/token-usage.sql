-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Token & Credit Usage Tracking
-- Core monitoring queries for AI spend visibility
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role (required for account_usage views)
-- FREQUENCY:     Daily/weekly as part of FinOps review
-- NOTE:          account_usage views have ~45 minute latency
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: My AI Queries in the Last Hour
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: First query every practitioner should run
-- WHAT IT SHOWS: Your recent Cortex queries with credit consumption
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    query_id,
    LEFT(query_text, 120)                       AS query_preview,
    start_time,
    ROUND(total_elapsed_time / 1000, 2)         AS seconds,
    ROUND(credits_used_cloud_services, 6)       AS credits_used
FROM snowflake.account_usage.query_history
WHERE start_time    >= DATEADD(hour, -1, CURRENT_TIMESTAMP)
  AND query_text    ILIKE ANY ('%AI_COMPLETE%', '%AI_SENTIMENT%', '%AI_CLASSIFY%',
                               '%AI_TRANSLATE%', '%AI_SUMMARIZE%', '%AI_EMBED%',
                               '%AI_FILTER%', '%AI_EXTRACT%', '%SNOWFLAKE.CORTEX%')
  AND user_name     = CURRENT_USER()
ORDER BY start_time DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 2: AI Credits by Cortex Function
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly FinOps review
-- WHAT IT SHOWS: Which Cortex functions consume the most AI token credits
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY (dedicated view with real AI credits)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    FUNCTION_NAME,
    COUNT(*)                                    AS call_count,
    ROUND(SUM(CREDITS), 4)                      AS total_ai_credits,
    ROUND(AVG(CREDITS), 6)                      AS avg_credits_per_call,
    ROUND(MIN(CREDITS), 6)                      AS min_credits,
    ROUND(MAX(CREDITS), 6)                      AS max_credits,
    ROUND(SUM(CREDITS) * 3, 2)                  AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY FUNCTION_NAME
ORDER BY total_ai_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Model Cost Comparison
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: After running multi-model experiments
-- WHAT IT SHOWS: Real AI credit cost per model from your session
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    MODEL_NAME,
    FUNCTION_NAME,
    COUNT(*)                                    AS calls,
    ROUND(SUM(CREDITS), 4)                      AS total_ai_credits,
    ROUND(AVG(CREDITS), 6)                      AS credits_per_call,
    ROUND(SUM(CREDITS) * 3, 2)                  AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(hour, -2, CURRENT_TIMESTAMP)
  AND FUNCTION_NAME IN ('COMPLETE', 'AI_COMPLETE')
GROUP BY MODEL_NAME, FUNCTION_NAME
ORDER BY total_ai_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 4: Resource Monitor Status
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: During active sessions to check remaining quota
-- WHAT IT SHOWS: Current warehouse credit usage vs quota
-- NOTE: Resource Monitors cover WAREHOUSE compute only, NOT AI token credits
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    name                                        AS monitor_name,
    credit_quota,
    ROUND(credits_used, 2)                      AS credits_used,
    ROUND(credits_used / credit_quota * 100, 2) AS pct_used,
    ROUND(credits_used_compute, 2)              AS credits_used_compute,
    ROUND(credits_used_cloud_services, 4)       AS credits_used_cloud_services
FROM snowflake.account_usage.resource_monitors
WHERE name = 'CORTEX_LAB_MONITOR';


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 5: Hourly AI Spend Trend
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: To identify usage patterns and anomalies
-- WHAT IT SHOWS: Hourly breakdown of AI calls and real AI credit consumption
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
-- QUERY 6: Cost Projection
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: BEFORE running AI at scale
-- WHAT IT SHOWS: Projected cost based on real AI credits from test queries
-- HOW TO USE: Replace query_id placeholders with your actual test query IDs
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1: Find your recent AI call costs:
SELECT
    QUERY_ID,
    FUNCTION_NAME,
    MODEL_NAME,
    ROUND(CREDITS, 6)                           AS ai_credits,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(hour, -1, CURRENT_TIMESTAMP)
ORDER BY START_TIME DESC
LIMIT 10;

-- Step 2: Project costs at scale (replace query IDs):
WITH sample_cost AS (
    SELECT
        SUM(CREDITS)   AS sample_credits,
        COUNT(*)       AS sample_calls
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
    WHERE QUERY_ID IN (
        -- *** PASTE YOUR TEST QUERY IDs HERE ***
        '01234567-89ab-cdef-0123-456789abcdef'
    )
)
SELECT
    sample_credits,
    sample_calls,
    ROUND(sample_credits / NULLIF(sample_calls, 0), 6) AS credits_per_call,
    ROUND(sample_credits * 100, 4)              AS projected_500_rows,
    ROUND(sample_credits * 10000, 2)            AS projected_50k_rows,
    ROUND(sample_credits * 100000, 2)           AS projected_500k_rows,
    ROUND(sample_credits * 100000 * 3, 2)       AS projected_500k_dollars
FROM sample_cost;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 7: Real-Time Monitoring (Current Session)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: When you need immediate visibility (no 45-min latency)
-- SOURCE: INFORMATION_SCHEMA (no latency, but limited to current session)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    query_id,
    LEFT(query_text, 100) AS query_preview,
    start_time,
    total_elapsed_time / 1000 AS seconds
FROM TABLE(information_schema.query_history(result_limit => 50))
WHERE query_text ILIKE ANY ('%AI_COMPLETE%', '%AI_SENTIMENT%', '%AI_CLASSIFY%',
                            '%AI_TRANSLATE%', '%AI_SUMMARIZE%', '%AI_EMBED%',
                            '%AI_FILTER%', '%AI_EXTRACT%', '%SNOWFLAKE.CORTEX%')
ORDER BY start_time DESC;
