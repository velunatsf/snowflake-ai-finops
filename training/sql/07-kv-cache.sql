-- ═══════════════════════════════════════════════════════════════════════════
-- AI for FinOps Training - Module 07: KV Cache Optimization
-- FinOps for Snowflake AI
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PURPOSE: Weekly prompt cache (KV cache) KPIs for CoCo, CoWork, and Cortex
--          Agents. These are the only cache queries in the workshop; general
--          usage and attribution queries live in 06-usage-tracking.sql.
--
-- THE FOUR TOKEN TYPES INSIDE TOKENS_GRANULAR:
--   input             new, non-cached prompt tokens processed this turn
--   output            tokens the model generated in response
--   cache_write_input context written into the prompt cache on the first turn
--   cache_read_input  cached context reused later, billed at a reduced rate
--
-- THE KPI: cache_read_pct_of_prompt should climb after turn 1 on long
--          sessions. A ratio stuck near zero means users keep starting fresh
--          sessions or rewriting large prompts, and you are re-paying full
--          price for the same context on every turn.
--
-- WHICH CoCo VIEW: use SNOWFLAKE_COCO_USAGE_HISTORY for account-wide KPIs. It
--          covers CLI, Desktop, and Snowsight and exposes INTERFACE for
--          slicing. Use CORTEX_CODE_CLI_USAGE_HISTORY only for CLI-only
--          drill-down, and never sum the two together.
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;  -- required for account_usage views

-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 1: Prompt Cache (KV Cache) Metrics - CoCo (unified, preferred KPI)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly FinOps KPI (account-wide CoCo)
-- PREFERRED VIEW: SNOWFLAKE_COCO_USAGE_HISTORY (CLI + Desktop + Snowsight)
--   Slice by INTERFACE if needed. Do NOT also sum interface-specific views.
-- DRILL-DOWN: CORTEX_CODE_CLI_USAGE_HISTORY for CLI-only (same OBJECT shape)
-- VIEW SHAPE: TOKENS_GRANULAR / CREDITS_GRANULAR are OBJECTS keyed by model
-- DOCS: https://docs.snowflake.com/en/sql-reference/account-usage/snowflake_coco_usage_history
-- CLI:  https://docs.snowflake.com/en/sql-reference/account-usage/cortex_code_cli_usage_history
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    h.INTERFACE,
    f.key                                               AS model_name,
    SUM(COALESCE(f.value:input::NUMBER, 0))             AS input_tokens,
    SUM(COALESCE(f.value:cache_read_input::NUMBER, 0))  AS cache_read_tokens,
    SUM(COALESCE(f.value:cache_write_input::NUMBER, 0)) AS cache_write_tokens,
    SUM(COALESCE(f.value:output::NUMBER, 0))            AS output_tokens,
    ROUND(
      100.0 * SUM(COALESCE(f.value:cache_read_input::NUMBER, 0))
      / NULLIF(
          SUM(COALESCE(f.value:input::NUMBER, 0)
            + COALESCE(f.value:cache_read_input::NUMBER, 0)
            + COALESCE(f.value:cache_write_input::NUMBER, 0)), 0),
      1)                                                AS cache_read_pct_of_prompt,
    SUM(h.TOKEN_CREDITS)                                AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWFLAKE_COCO_USAGE_HISTORY h,
     LATERAL FLATTEN(input => h.TOKENS_GRANULAR) f
WHERE h.USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY total_credits DESC;

-- Credits split (same window)
SELECT
    h.INTERFACE,
    f.key AS model_name,
    SUM(COALESCE(f.value:input::NUMBER, 0))             AS input_credits,
    SUM(COALESCE(f.value:cache_read_input::NUMBER, 0))  AS cache_read_credits,
    SUM(COALESCE(f.value:cache_write_input::NUMBER, 0)) AS cache_write_credits,
    SUM(COALESCE(f.value:output::NUMBER, 0))            AS output_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWFLAKE_COCO_USAGE_HISTORY h,
     LATERAL FLATTEN(input => h.CREDITS_GRANULAR) f
WHERE h.USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY (input_credits + cache_read_credits + cache_write_credits + output_credits) DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 2: Prompt Cache (KV Cache) Metrics - CoWork (org or account)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly FinOps KPI for CoWork / Intelligence sessions
-- VIEW SHAPE: TOKENS_GRANULAR is an ARRAY:
--   [{ <request_id>: { <service_type>: { <model>: {input, cache_*, output} },
--                      start_time: ... } }, ...]
-- Needs nested FLATTEN (unlike CoCo's model-keyed OBJECT).
-- DOCS (org):  https://docs.snowflake.com/en/sql-reference/organization-usage/snowflake_cowork_usage_history
-- DOCS (acct): https://docs.snowflake.com/en/sql-reference/account-usage/snowflake_cowork_usage_history_view
-- NOTE: Org view is only in the organization account. Swap schema as needed.
-- ─────────────────────────────────────────────────────────────────────────────

-- Organization Usage (all accounts) - run in the organization account
SELECT
    svc.key                                             AS service_type,
    mdl.key                                             AS model_name,
    SUM(COALESCE(mdl.value:input::NUMBER, 0))           AS input_tokens,
    SUM(COALESCE(mdl.value:cache_read_input::NUMBER, 0))  AS cache_read_tokens,
    SUM(COALESCE(mdl.value:cache_write_input::NUMBER, 0)) AS cache_write_tokens,
    SUM(COALESCE(mdl.value:output::NUMBER, 0))          AS output_tokens,
    ROUND(
      100.0 * SUM(COALESCE(mdl.value:cache_read_input::NUMBER, 0))
      / NULLIF(
          SUM(COALESCE(mdl.value:input::NUMBER, 0)
            + COALESCE(mdl.value:cache_read_input::NUMBER, 0)
            + COALESCE(mdl.value:cache_write_input::NUMBER, 0)), 0),
      1)                                                AS cache_read_pct_of_prompt,
    SUM(h.TOKEN_CREDITS)                                AS total_credits
FROM SNOWFLAKE.ORGANIZATION_USAGE.SNOWFLAKE_COWORK_USAGE_HISTORY h,
     LATERAL FLATTEN(input => h.TOKENS_GRANULAR) tg,
     LATERAL FLATTEN(input => tg.value) req,
     LATERAL FLATTEN(input => req.value) svc,
     LATERAL FLATTEN(input => svc.value) mdl
WHERE h.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND svc.key <> 'start_time'
  AND TYPEOF(mdl.value) = 'OBJECT'
GROUP BY 1, 2
ORDER BY total_credits DESC;

-- Account Usage equivalent (same nested flatten; START_TIME filter):
-- FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWFLAKE_COWORK_USAGE_HISTORY h, ...


-- ═══════════════════════════════════════════════════════════════════════════
-- QUERY 3: Prompt Cache (KV Cache) Metrics - Cortex Agents
-- ═══════════════════════════════════════════════════════════════════════════
-- WHEN TO RUN: Weekly FinOps KPI for Agents (non-CoWork)
-- VIEW SHAPE: same nested ARRAY as CoWork
-- DOCS: https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history
-- NOTE: CoWork-originated agent traffic is in SNOWFLAKE_COWORK_USAGE_HISTORY
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    h.AGENT_NAME,
    svc.key                                               AS service_type,
    mdl.key                                               AS model_name,
    SUM(COALESCE(mdl.value:input::NUMBER, 0))             AS input_tokens,
    SUM(COALESCE(mdl.value:cache_read_input::NUMBER, 0))  AS cache_read_tokens,
    SUM(COALESCE(mdl.value:cache_write_input::NUMBER, 0)) AS cache_write_tokens,
    SUM(COALESCE(mdl.value:output::NUMBER, 0))            AS output_tokens,
    ROUND(
      100.0 * SUM(COALESCE(mdl.value:cache_read_input::NUMBER, 0))
      / NULLIF(
          SUM(COALESCE(mdl.value:input::NUMBER, 0)
            + COALESCE(mdl.value:cache_read_input::NUMBER, 0)
            + COALESCE(mdl.value:cache_write_input::NUMBER, 0)), 0),
      1)                                                  AS cache_read_pct_of_prompt,
    SUM(h.TOKEN_CREDITS)                                  AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY h,
     LATERAL FLATTEN(input => h.TOKENS_GRANULAR) tg,
     LATERAL FLATTEN(input => tg.value) req,
     LATERAL FLATTEN(input => req.value) svc,
     LATERAL FLATTEN(input => svc.value) mdl
WHERE h.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND svc.key <> 'start_time'
  AND TYPEOF(mdl.value) = 'OBJECT'
GROUP BY 1, 2, 3
ORDER BY total_credits DESC;
