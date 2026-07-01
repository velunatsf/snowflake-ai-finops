-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Model Rightsizing
-- Find where cheaper models or task-specific functions would suffice
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: ACCOUNTADMIN role
-- FREQUENCY:     Monthly optimization review
-- SAVINGS:       40-75% by switching to task-specific functions
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: Credits per 1M Tokens by Model
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Relative cost efficiency of each model
-- ACTION: High credits_per_1m_tokens on simple tasks = oversized
-- ─────────────────────────────────────────────────────────────────────────────

SELECT MODEL_NAME, FUNCTION_NAME,
       SUM(TOKENS)        AS total_tokens,
       SUM(TOKEN_CREDITS)  AS total_credits,
       ROUND(SUM(TOKEN_CREDITS)
             / NULLIF(SUM(TOKENS),0) * 1000000, 2) AS credits_per_1m_tokens
FROM   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE  USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP  BY MODEL_NAME, FUNCTION_NAME
ORDER  BY credits_per_1m_tokens DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 2: AI_COMPLETE Used Where Task-Specific Functions Exist
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: AI_COMPLETE calls that could be AI_SENTIMENT, AI_CLASSIFY, etc.
-- ACTION: Review query text for sentiment/classification/extraction patterns
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    FUNCTION_NAME,
    MODEL_NAME,
    COUNT(*) AS call_count,
    SUM(CREDITS) AS total_credits,
    ROUND(AVG(CREDITS), 6) AS avg_credits_per_call,
    ROUND(SUM(CREDITS) * 3, 2) AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND FUNCTION_NAME IN ('COMPLETE', 'AI_COMPLETE')
GROUP BY FUNCTION_NAME, MODEL_NAME
ORDER BY total_credits DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Model Cost Comparison Table
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IT SHOWS: Side-by-side comparison of all models used
-- ACTION: Replace premium models with standard/budget for simple tasks
--
-- Reference cost tiers:
--   Budget:   mistral-7b, gemma-7b              (~1x)
--   Standard: llama3-70b, mistral-large         (~5-10x)
--   Premium:  claude-3-5-sonnet, llama3.1-405b  (~20-50x)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    MODEL_NAME,
    COUNT(*) AS total_calls,
    SUM(TOKENS) AS total_tokens,
    SUM(TOKEN_CREDITS) AS total_credits,
    ROUND(SUM(TOKEN_CREDITS) / NULLIF(SUM(TOKENS), 0) * 1000000, 2) AS credits_per_1m_tokens,
    ROUND(SUM(TOKEN_CREDITS) * 3, 2) AS est_dollars,
    CASE
        WHEN SUM(TOKEN_CREDITS) / NULLIF(SUM(TOKENS), 0) * 1000000 < 2.0 THEN 'Budget'
        WHEN SUM(TOKEN_CREDITS) / NULLIF(SUM(TOKENS), 0) * 1000000 < 5.0 THEN 'Standard'
        ELSE 'Premium'
    END AS cost_tier
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY MODEL_NAME
ORDER BY credits_per_1m_tokens DESC;
