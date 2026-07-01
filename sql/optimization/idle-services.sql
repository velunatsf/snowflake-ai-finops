-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Idle Service Detection
-- Find Cortex Search services burning credits with no queries
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role
-- FREQUENCY:     Monthly - hunt for wasted Search indexing spend
-- SAVINGS:       100% of idle cost by dropping unused services
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: Idle Cortex Search Service Detection
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Services that consume indexing credits but get few/no queries
-- WHY IT MATTERS: Cortex Search has a STANDING cost model - indexing runs
--   even with zero queries. POC, demo, or abandoned services are pure waste.
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
-- QUERY 2: Cortex Search Services with Full Detail
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: All Search services with indexing vs query credit breakdown
-- ACTION: Services with high indexing and low query are candidates for cleanup
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    SERVICE_NAME,
    DATABASE_NAME,
    SCHEMA_NAME,
    CONSUMPTION_TYPE,
    SUM(CREDITS) AS total_credits,
    SUM(TOKENS) AS total_tokens,
    MIN(USAGE_DATE) AS first_usage,
    MAX(USAGE_DATE) AS last_usage
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY SERVICE_NAME, DATABASE_NAME, SCHEMA_NAME, CONSUMPTION_TYPE
ORDER BY total_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Cleanup Candidates (Services Not Queried in 14+ Days)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Services where last query was over 2 weeks ago
-- ACTION: Confirm with owners, then DROP SERVICE if abandoned
-- ─────────────────────────────────────────────────────────────────────────────

WITH last_query AS (
    SELECT SERVICE_NAME,
           MAX(CASE WHEN CONSUMPTION_TYPE = 'QUERY' THEN USAGE_DATE END) AS last_query_date,
           SUM(CASE WHEN CONSUMPTION_TYPE = 'INDEXING' THEN CREDITS ELSE 0 END) AS idx_credits_30d
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
    WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY SERVICE_NAME
)
SELECT SERVICE_NAME,
       last_query_date,
       DATEDIFF('day', last_query_date, CURRENT_DATE()) AS days_since_last_query,
       idx_credits_30d AS indexing_credits_wasted
FROM last_query
WHERE last_query_date IS NULL
   OR DATEDIFF('day', last_query_date, CURRENT_DATE()) > 14
ORDER BY idx_credits_30d DESC;
