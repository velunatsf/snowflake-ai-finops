-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Cost Attribution Queries
-- Allocate AI spend by user, team, role, and project
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role
-- FREQUENCY:     Weekly for chargeback and team cost allocation
-- NOTE:          account_usage views have ~45 minute latency
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: AI Spend by User (Team Attribution)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Real AI credit consumption broken down by user
-- SOURCE: CORTEX_AI_FUNCTIONS_USAGE_HISTORY + USERS JOIN
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
-- QUERY 2: AI Spend by Role
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Which roles consume the most AI credits
-- USE FOR: Identifying prod vs dev spend, unauthorized usage
-- ─────────────────────────────────────────────────────────────────────────────

SELECT r.VALUE::STRING   AS role_name,
       h.FUNCTION_NAME,
       COUNT(*)           AS calls,
       SUM(h.CREDITS)     AS total_credits,
       ROUND(SUM(h.CREDITS) * 3, 2) AS est_dollars
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h,
       LATERAL FLATTEN(input => h.ROLE_NAMES) r
WHERE  h.START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP  BY role_name, h.FUNCTION_NAME
ORDER  BY total_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: AI Spend by Query Tag (Project Attribution)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Cost by QUERY_TAG for project/department chargeback
-- PREREQUISITE: Teams must set QUERY_TAG before running AI calls
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    QUERY_TAG,
    SUM(TOKEN_CREDITS) AS total_credits,
    COUNT(*) AS call_count,
    ROUND(AVG(TOKEN_CREDITS), 6) AS avg_per_call,
    ROUND(SUM(TOKEN_CREDITS) * 3, 2) AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND QUERY_TAG IS NOT NULL
  AND QUERY_TAG != ''
GROUP BY QUERY_TAG
ORDER BY total_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 4: Most Expensive Individual AI Calls
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Top 20 highest-cost individual AI calls with user names
-- USE FOR: Identifying runaway queries, agent loops, or oversized prompts
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
-- QUERY 5: AI Credits Transition - New SERVICE_TYPE Billing
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Four AI services with their own SERVICE_TYPE:
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
    'AI_SERVICES',
    'CORTEX_AGENTS',
    'CORTEX_CODE_CLI',
    'CORTEX_CODE_SNOWSIGHT',
    'SNOWFLAKE_INTELLIGENCE'
)
GROUP BY SERVICE_TYPE
ORDER BY total_credits_billed DESC;
