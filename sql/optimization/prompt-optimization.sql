-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Prompt Optimization
-- Detect rising prompt sizes and verbose token usage patterns
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role
-- FREQUENCY:     Monthly - detect prompt bloat trends
-- SAVINGS:       20-40% by trimming verbose prompts
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: Weekly Average Tokens per Call (Trend)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Rising avg_tokens_per_call = prompt bloat
-- ACTION: Investigate functions where token count is increasing
-- ─────────────────────────────────────────────────────────────────────────────

SELECT FUNCTION_NAME,
       DATE_TRUNC('week', USAGE_TIME)  AS week,
       AVG(TOKENS)                     AS avg_tokens_per_call,
       SUM(TOKEN_CREDITS)              AS weekly_credits,
       COUNT(*)                        AS call_count
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE  USAGE_TIME >= DATEADD('day', -60, CURRENT_TIMESTAMP())
GROUP  BY FUNCTION_NAME, week
ORDER  BY FUNCTION_NAME, week;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 2: High-Token Calls (Potential Oversized Prompts)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Individual calls with unusually high token counts
-- ACTION: Review these queries — are they sending entire documents?
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    QUERY_ID,
    MODEL_NAME,
    FUNCTION_NAME,
    TOKENS,
    TOKEN_CREDITS,
    USAGE_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND TOKENS > 50000  -- Calls using more than 50K tokens
ORDER BY TOKENS DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Granular Token Breakdown (Input vs Output vs Reasoning)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Whether cost is driven by prompt size, response length,
--               or chain-of-thought reasoning
-- ACTION: If input tokens dominate, trim prompts. If output dominates,
--         add max_tokens parameter.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    QUERY_ID,
    MODEL_NAME,
    TOKENS,
    TOKEN_CREDITS,
    TOKENS_GRANULAR,
    TOKEN_CREDITS_GRANULAR
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY TOKEN_CREDITS DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 4: Pre-Flight Token Estimation Pattern
-- ═══════════════════════════════════════════════════════════════════════════
-- USE THIS IN YOUR PIPELINES: Check token count before expensive calls
-- Prevents accidentally sending 500-page documents through AI functions
-- ─────────────────────────────────────────────────────────────────────────────

-- Example: Only process rows under 10K tokens
-- SELECT
--     id,
--     text_column,
--     SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', text_column) AS est_tokens
-- FROM my_table
-- WHERE SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', text_column) < 10000;
