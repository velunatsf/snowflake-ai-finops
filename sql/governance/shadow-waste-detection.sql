-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Shadow Waste Detection Queries
-- Detect the 8 most common patterns of hidden AI credit waste
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role (required for account_usage views)
-- FREQUENCY:     Run monthly for comprehensive waste audit
-- NOTE:          account_usage views have ~45 minute latency
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- WASTE 1: Over-Sized Model Detection
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - find where cheaper models would suffice
-- WHAT IT SHOWS: Cost per 1M tokens by model - high values = oversized
-- SAVINGS: Replace AI_COMPLETE misuse with task-specific functions (40-75%)
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
-- WASTE 2: Redundant / Duplicate AI Calls
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
-- WASTE 3: Verbose / Bloated Prompts
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
-- WASTE 4: Idle Cortex Search Services
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - hunt for wasted Search indexing spend
-- WHAT IT SHOWS: Services that consume indexing credits but get few/no queries
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
-- WASTE 5: Uncontrolled Agent Loops
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
-- WASTE 6: Dev/Test in Production
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Monthly - detect experiments draining prod credits
-- WHAT IT SHOWS: AI spend by role - non-prod roles using prod AI = waste
-- FIX: RBAC (REVOKE USE AI FUNCTIONS from dev roles), separate accounts
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
-- WASTE 7: Missing Cost Attribution (Tagging Coverage)
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
