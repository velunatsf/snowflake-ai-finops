-- ═══════════════════════════════════════════════════════════════════════════
-- AI for FinOps Training - Module 06: Token & Credit Usage Tracking
-- FinOps for Snowflake AI · Snowflake AI FinOps Training
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PURPOSE: These queries are your real-time FinOps console for AI spend.
-- NOTE:    account_usage views have ~45 minute latency for recent queries.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;  -- Required for account_usage views

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
  AND query_text    ILIKE ANY ('%AI_COMPLETE%', '%AI_SENTIMENT%', '%AI_CLASSIFY%', '%AI_TRANSLATE%', '%AI_SUMMARIZE%', '%AI_EMBED%', '%AI_FILTER%', '%AI_EXTRACT%', '%SNOWFLAKE.CORTEX%')
  AND user_name     = CURRENT_USER()
ORDER BY start_time DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 2: AI Credits by Cortex Function
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly FinOps review
-- WHAT IT SHOWS: Which Cortex functions consume the most AI token credits
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY (dedicated view with real AI credits)
-- NOTE: Do NOT use query_history.credits_used_cloud_services - that measures
--       cloud services overhead (query compilation), not AI token cost.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    FUNCTION_NAME,
    COUNT(*)                                    AS call_count,
    ROUND(SUM(CREDITS), 4)                      AS total_ai_credits,
    ROUND(AVG(CREDITS), 6)                      AS avg_credits_per_call,
    ROUND(MIN(CREDITS), 6)                      AS min_credits,
    ROUND(MAX(CREDITS), 6)                      AS max_credits,
    ROUND(SUM(CREDITS) * 3, 2)                  AS est_dollars        -- ~$3/credit
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY FUNCTION_NAME
ORDER BY total_ai_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Model Cost Comparison
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: After Exercise 4 in Module 05
-- WHAT IT SHOWS: Real AI credit cost per model from your training session
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY - native MODEL_NAME column
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    MODEL_NAME,
    FUNCTION_NAME,
    COUNT(*)                                    AS calls,
    ROUND(SUM(CREDITS), 4)                      AS total_ai_credits,
    ROUND(AVG(CREDITS), 6)                      AS credits_per_call,
    ROUND(SUM(CREDITS) * 3, 2)                  AS est_dollars        -- ~$3/credit
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(hour, -2, CURRENT_TIMESTAMP)
  AND FUNCTION_NAME IN ('COMPLETE', 'AI_COMPLETE')
GROUP BY MODEL_NAME, FUNCTION_NAME
ORDER BY total_ai_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 4: Resource Monitor Status
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: During training to check remaining quota
-- WHAT IT SHOWS: Current credit usage vs quota for the lab monitor
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    name                                        AS monitor_name,
    credit_quota,
    ROUND(credits_used, 2)                      AS credits_used,
    ROUND(
        credits_used / credit_quota * 100,
        2
    )                                           AS pct_used,
    ROUND(credits_used_compute, 2)              AS credits_used_compute,
    ROUND(credits_used_cloud_services, 4)       AS credits_used_cloud_services
FROM snowflake.account_usage.resource_monitors
WHERE name = 'CORTEX_LAB_MONITOR';


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 5: Hourly AI Spend Trend
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: To identify usage patterns and anomalies
-- WHAT IT SHOWS: Hourly breakdown of AI calls and real AI credit consumption
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY - not cloud services overhead
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    DATE_TRUNC('hour', START_TIME)              AS hour_bucket,
    FUNCTION_NAME,
    COUNT(*)                                    AS ai_calls,
    ROUND(SUM(CREDITS), 4)                      AS ai_credits,
    ROUND(SUM(CREDITS) * 3, 2)                  AS est_dollars        -- ~$3/credit
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -1, CURRENT_TIMESTAMP)
GROUP BY 1, 2
ORDER BY 1 DESC, ai_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 6: Cost Projection Query
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: BEFORE running AI at scale - use after Module 05 Exercise 5
-- WHAT IT SHOWS: Projected cost based on real AI credits from test queries
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY - uses real CREDITS, not cloud
--         services overhead from query_history
-- HOW TO USE: Replace query_id placeholders with your actual test query IDs
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1: Find your recent AI call costs from the dedicated view:
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

-- Step 2: Project costs at scale using real AI credits:
WITH sample_cost AS (
    SELECT
        SUM(CREDITS)                            AS sample_credits,
        COUNT(*)                                AS sample_calls
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
    WHERE QUERY_ID IN (
        -- *** PASTE YOUR TEST QUERY IDs HERE ***
        '01234567-89ab-cdef-0123-456789abcdef',
        'fedcba98-7654-3210-fedc-ba9876543210'
    )
)
SELECT
    sample_credits,
    sample_calls,
    ROUND(sample_credits / NULLIF(sample_calls, 0), 6) 
                                                AS credits_per_call,
    -- Projections assuming each call processes ~1 row
    ROUND(sample_credits * 100, 4)              AS projected_500_rows,
    ROUND(sample_credits * 10000, 2)            AS projected_50k_rows,
    ROUND(sample_credits * 100000, 2)           AS projected_500k_rows,
    -- Dollar estimates at ~$3/credit
    ROUND(sample_credits * 100000 * 3, 2)       AS projected_500k_dollars
FROM sample_cost;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 7: AI Spend by User (Team Attribution)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: For chargeback and team cost allocation
-- WHAT IT SHOWS: Real AI credit consumption broken down by user
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY + USERS JOIN (USER_ID → NAME)
-- NOTE: Dedicated views have USER_ID (number), not USER_NAME - JOIN required
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    u.NAME                                      AS user_name,
    COUNT(*)                                    AS ai_call_count,
    ROUND(SUM(c.CREDITS), 4)                    AS total_ai_credits,
    ROUND(AVG(c.CREDITS), 6)                    AS avg_credits_per_call,
    MIN(c.START_TIME)                           AS first_call,
    MAX(c.START_TIME)                           AS last_call,
    ROUND(SUM(c.CREDITS) * 3, 2)                AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u
    ON c.USER_ID = u.USER_ID
WHERE c.START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY u.NAME
ORDER BY total_ai_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 8: Most Expensive AI Calls
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: To identify cost optimization opportunities
-- WHAT IT SHOWS: Top 20 highest-cost individual AI calls with user names
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY + USERS JOIN
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    c.QUERY_ID,
    u.NAME                                      AS user_name,
    c.FUNCTION_NAME,
    c.MODEL_NAME,
    ROUND(c.CREDITS, 6)                         AS ai_credits,
    ROUND(c.CREDITS * 3, 4)                     AS est_dollars,
    c.START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u
    ON c.USER_ID = u.USER_ID
WHERE c.START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP)
ORDER BY c.CREDITS DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 9: Cortex Code Usage (CLI + Snowsight)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: To track Cortex Code (CoCo) assistant usage
-- WHAT IT SHOWS: Token and credit breakdown for the AI coding assistant
-- NOTE: These are separate views from general query_history
-- ─────────────────────────────────────────────────────────────────────────────

-- Snowflake CoCo CLI Usage
SELECT
    user_name,
    DATE_TRUNC('day', event_timestamp)          AS usage_date,
    COUNT(*)                                    AS sessions,
    SUM(total_tokens)                           AS total_tokens,
    ROUND(SUM(total_credits), 4)                AS total_credits
FROM snowflake.account_usage.cortex_code_cli_usage_history
WHERE event_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY 1, 2
ORDER BY 2 DESC, 3 DESC;

-- Cortex Code Snowsight Usage
SELECT
    user_name,
    DATE_TRUNC('day', event_timestamp)          AS usage_date,
    COUNT(*)                                    AS sessions,
    SUM(total_tokens)                           AS total_tokens,
    ROUND(SUM(total_credits), 4)                AS total_credits
FROM snowflake.account_usage.cortex_code_snowsight_usage_history
WHERE event_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY 1, 2
ORDER BY 2 DESC, 3 DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 10: AI Credits Transition - Detect New SERVICE_TYPE Billing
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Immediately - check if your account shows the new types
-- WHAT IT SHOWS: Four AI services moving to their own SERVICE_TYPE:
--   CORTEX_AGENTS, CORTEX_CODE_CLI, CORTEX_CODE_SNOWSIGHT, SNOWFLAKE_INTELLIGENCE
-- WHY IT MATTERS: Dashboards filtering on AI_SERVICES will miss this spend
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    SERVICE_TYPE,
    MIN(USAGE_DATE)          AS first_seen,
    MAX(USAGE_DATE)          AS last_seen,
    SUM(CREDITS_BILLED)      AS total_credits_billed,
    SUM(CREDITS_USED)         AS total_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE SERVICE_TYPE IN (
    'CORTEX_AGENTS',
    'CORTEX_CODE_CLI',
    'CORTEX_CODE_SNOWSIGHT',
    'SNOWFLAKE_INTELLIGENCE'
)
GROUP BY SERVICE_TYPE
ORDER BY total_credits_billed DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 11: Idle Cortex Search Service Detection
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - hunt for wasted Search indexing spend
-- WHAT IT SHOWS: Services that consume indexing credits but get few/no queries
-- WHY IT MATTERS: Cortex Search has a STANDING cost model - indexing runs even
--   with zero queries. POC, demo, or abandoned services are pure waste.
-- KEY: query_pct near 0% = service is indexing but nobody is querying it
-- ─────────────────────────────────────────────────────────────────────────────

WITH costs AS (
    SELECT SERVICE_NAME,
           SUM(CASE WHEN CONSUMPTION_TYPE = 'INDEXING'
                    THEN CREDITS ELSE 0 END)  AS idx_credits,
           SUM(CASE WHEN CONSUMPTION_TYPE = 'QUERY'
                    THEN CREDITS ELSE 0 END)  AS qry_credits
    FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
    WHERE  USAGE_DATE >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP  BY SERVICE_NAME
)
SELECT SERVICE_NAME,
       idx_credits,
       qry_credits,
       ROUND(qry_credits / NULLIF(idx_credits, 0) * 100, 1) AS query_pct
FROM   costs
WHERE  idx_credits > 0
ORDER  BY query_pct ASC;


-- ═══════════════════════════════════════════════════════════════════════════
-- SHADOW WASTE DETECTION QUERIES
-- Source: AI Shadow Waste in Snowflake AI presentation
-- These queries detect the 8 most common patterns of hidden AI credit waste
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 12: Over-Sized Model Detection
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - find where cheaper models would suffice
-- WHAT IT SHOWS: Cost per 1M tokens by model - high values = oversized
-- SOURCE: CORTEX_AISQL_USAGE_HISTORY - has TOKENS + TOKEN_CREDITS granularity
-- SAVINGS: Replace AI_COMPLETE misuse with task-specific functions (40–75%)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT MODEL_NAME, FUNCTION_NAME,
       SUM(TOKENS)        AS total_tokens,
       SUM(TOKEN_CREDITS)  AS total_credits,
       ROUND(SUM(TOKEN_CREDITS)
             / NULLIF(SUM(TOKENS),0) * 1000000, 2)
                            AS credits_per_1m_tokens
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE  USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP  BY MODEL_NAME, FUNCTION_NAME
ORDER  BY credits_per_1m_tokens DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 13: Redundant / Duplicate AI Calls
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly - detect pipelines re-processing unchanged rows
-- WHAT IT SHOWS: Users making >20 AI calls/day per function = likely duplicates
-- FIX: Incremental processing (WHERE ai_processed_at IS NULL), cache results
-- ─────────────────────────────────────────────────────────────────────────────

SELECT h.USER_ID, u.NAME,
       h.FUNCTION_NAME,
       DATE_TRUNC('day', h.START_TIME)  AS day,
       COUNT(*)                         AS daily_calls,
       SUM(h.CREDITS)                   AS daily_credits
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h
JOIN   SNOWFLAKE.ACCOUNT_USAGE.USERS u
       ON h.USER_ID = u.USER_ID
WHERE  h.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP  BY h.USER_ID, u.NAME, h.FUNCTION_NAME, day
HAVING COUNT(*) > 20
ORDER  BY daily_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 14: Verbose / Bloated Prompts
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - detect rising prompt sizes over time
-- WHAT IT SHOWS: Weekly avg tokens/call by function - rising trend = bloat
-- FIX: Trim prompts, pre-filter with LEFT(), use AI_COUNT_TOKENS pre-flight
-- ─────────────────────────────────────────────────────────────────────────────

SELECT FUNCTION_NAME,
       DATE_TRUNC('week', USAGE_TIME)  AS week,
       AVG(TOKENS)                     AS avg_tokens_per_call,
       SUM(TOKEN_CREDITS)              AS weekly_credits
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE  USAGE_TIME >= DATEADD('day', -60, CURRENT_TIMESTAMP())
GROUP  BY FUNCTION_NAME, week
ORDER  BY FUNCTION_NAME, week;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 15: Uncontrolled Agent Loops
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly - agents without budgets can loop endlessly
-- WHAT IT SHOWS: MAX vs AVG per-call cost - large gap = unbounded loops
-- FIX: Token + time budgets, query_timeout on agent SQL tools
-- ─────────────────────────────────────────────────────────────────────────────

SELECT DATE_TRUNC('day', USAGE_TIME) AS day,
       MAX(TOKEN_CREDITS)            AS max_call,
       AVG(TOKEN_CREDITS)            AS avg_call,
       COUNT(*)                      AS total_calls
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE  USAGE_TIME >= DATEADD('day', -14, CURRENT_TIMESTAMP())
GROUP  BY day
ORDER  BY day DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 16: Dev/Test in Production
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - detect experiments draining prod credits
-- WHAT IT SHOWS: AI spend by role - non-prod roles using prod AI = waste
-- FIX: RBAC (REVOKE USE AI FUNCTIONS from dev roles), separate accounts
-- NOTE: ROLE_NAMES is an ARRAY - requires LATERAL FLATTEN
-- ─────────────────────────────────────────────────────────────────────────────

SELECT r.VALUE::STRING   AS role_name,
       h.FUNCTION_NAME,
       COUNT(*)           AS calls,
       SUM(h.CREDITS)     AS total_credits
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h,
       LATERAL FLATTEN(input => h.ROLE_NAMES) r
WHERE  h.START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP  BY role_name, h.FUNCTION_NAME
ORDER  BY total_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 17: Week-over-Week Cost Anomaly Detection
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly - catch spikes before the monthly bill arrives
-- WHAT IT SHOWS: Daily AI credits vs same day last week, % change
-- SIGNAL: wow_pct > 200 = spend tripled - investigate immediately
-- FIX: Budget email alerts, low-latency refresh (1hr vs 6.5hr)
-- ─────────────────────────────────────────────────────────────────────────────

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
ORDER  BY day DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 18: Missing Cost Attribution (Tagging Coverage)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - unattributed spend cannot be optimized
-- WHAT IT SHOWS: Tagged vs untagged AI calls and their credit share
-- TARGET: >90% of credits should be tagged
-- FIX: Enforce ALTER SESSION SET QUERY_TAG='team=X,project=Y,env=prod'
-- ─────────────────────────────────────────────────────────────────────────────

SELECT CASE WHEN QUERY_TAG IS NOT NULL AND QUERY_TAG != ''
            THEN 'Tagged' ELSE 'Untagged'
       END                              AS attribution,
       COUNT(*)                          AS calls,
       SUM(TOKEN_CREDITS)                AS credits,
       ROUND(SUM(TOKEN_CREDITS)
             / (SELECT SUM(TOKEN_CREDITS)
                FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
                WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP()))
             * 100, 1)                   AS pct_of_total
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE  USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP  BY attribution;


-- ═══════════════════════════════════════════════════════════════════════════
-- SNOWSIGHT NAVIGATION STEPS (for GUI-based monitoring)
-- ═══════════════════════════════════════════════════════════════════════════
-- Step 1: Admin → Cost Management → Consumption
-- Step 2: Service type filter → AI/ML Functions
-- Step 3: Drill into Cortex by function
-- Step 4: Set notification threshold under Admin → Notifications
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- LATENCY NOTE
-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTANT: account_usage views have approximately 45 minutes of latency.
-- Very recent queries may not appear immediately. For real-time monitoring
-- of a running session, use INFORMATION_SCHEMA.QUERY_HISTORY (no latency,
-- but limited to current session).
-- ═══════════════════════════════════════════════════════════════════════════

-- Real-time alternative (current session only):
SELECT
    query_id,
    LEFT(query_text, 100) AS query_preview,
    start_time,
    total_elapsed_time / 1000 AS seconds
FROM TABLE(information_schema.query_history(
    result_limit => 50
))
WHERE query_text ILIKE ANY ('%AI_COMPLETE%', '%AI_SENTIMENT%', '%AI_CLASSIFY%', '%AI_TRANSLATE%', '%AI_SUMMARIZE%', '%AI_EMBED%', '%AI_FILTER%', '%AI_EXTRACT%', '%SNOWFLAKE.CORTEX%')
ORDER BY start_time DESC;
