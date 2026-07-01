-- ═══════════════════════════════════════════════════════════════════════════
-- FinOps for Snowflake AI — Cortex Agent Example
-- A Cortex Agent that answers AI cost questions using natural language
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES:
--   - ACCOUNTADMIN role
--   - Database and schema exist (e.g., DEMO_DB.AGENTS)
--   - Warehouse available (e.g., COMPUTE_WH)
--
-- DEPLOYMENT:
--   1. Run the stored procedure creation below
--   2. Run the agent creation
--   3. Query the agent via AGENT_RUN or AGENT_PREVIEW
--
-- NOTE: AGENT_RUN is not available on trial accounts.
--       The stored procedure works independently.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS DEMO_DB;
CREATE SCHEMA IF NOT EXISTS DEMO_DB.AGENTS;
USE SCHEMA DEMO_DB.AGENTS;


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1: Create the AI Cost Usage Stored Procedure
-- ═══════════════════════════════════════════════════════════════════════════
-- This procedure queries SNOWFLAKE.ACCOUNT_USAGE views and returns
-- AI cost data in a standardized format.
--
-- Supported report_type values:
--   'summary'                  → Overall AI cost summary across all services
--   'cortex_aisql_by_model'    → AI SQL costs by model
--   'ai_functions_by_model'    → AI Functions costs by function/model
--   'cortex_search_by_service' → Cortex Search costs by service
--   'daily_trend'              → Daily AI cost trend
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DEMO_DB.AGENTS.GET_AI_COST_USAGE(
    REPORT_TYPE VARCHAR,
    DAYS_BACK FLOAT
)
RETURNS TABLE(
    category VARCHAR,
    detail_1 VARCHAR,
    total_calls NUMBER,
    total_credits FLOAT
)
LANGUAGE SQL
AS
$$
BEGIN
    IF (:REPORT_TYPE = 'summary') THEN
        RETURN TABLE(
            SELECT 'Cortex AI SQL' AS category,
                   NULL AS detail_1,
                   COUNT(*) AS total_calls,
                   SUM(TOKEN_CREDITS) AS total_credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
            WHERE USAGE_TIME >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            UNION ALL
            SELECT 'Cortex AI Functions',
                   NULL,
                   COUNT(*),
                   SUM(CREDITS)
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
            WHERE START_TIME >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            UNION ALL
            SELECT 'Cortex Search',
                   NULL,
                   NULL,
                   SUM(CREDITS)
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
            WHERE USAGE_DATE >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            UNION ALL
            SELECT 'Document AI',
                   NULL,
                   COUNT(*),
                   SUM(CREDITS_USED)
            FROM SNOWFLAKE.ACCOUNT_USAGE.DOCUMENT_AI_USAGE_HISTORY
            WHERE START_TIME >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            UNION ALL
            SELECT 'AI Metering',
                   SERVICE_TYPE,
                   NULL,
                   SUM(CREDITS_BILLED)
            FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
            WHERE SERVICE_TYPE IN ('AI_SERVICES','CORTEX_AGENTS','CORTEX_CODE_CLI',
                                   'CORTEX_CODE_SNOWSIGHT','SNOWFLAKE_INTELLIGENCE')
              AND USAGE_DATE >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            GROUP BY SERVICE_TYPE
        );

    ELSEIF (:REPORT_TYPE = 'cortex_aisql_by_model') THEN
        RETURN TABLE(
            SELECT MODEL_NAME AS category,
                   FUNCTION_NAME AS detail_1,
                   COUNT(*) AS total_calls,
                   SUM(TOKEN_CREDITS) AS total_credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
            WHERE USAGE_TIME >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            GROUP BY MODEL_NAME, FUNCTION_NAME
            ORDER BY total_credits DESC
        );

    ELSEIF (:REPORT_TYPE = 'ai_functions_by_model') THEN
        RETURN TABLE(
            SELECT FUNCTION_NAME AS category,
                   MODEL_NAME AS detail_1,
                   COUNT(*) AS total_calls,
                   SUM(CREDITS) AS total_credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
            WHERE START_TIME >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            GROUP BY FUNCTION_NAME, MODEL_NAME
            ORDER BY total_credits DESC
        );

    ELSEIF (:REPORT_TYPE = 'cortex_search_by_service') THEN
        RETURN TABLE(
            SELECT SERVICE_NAME AS category,
                   DATABASE_NAME || '.' || SCHEMA_NAME AS detail_1,
                   NULL AS total_calls,
                   SUM(CREDITS) AS total_credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
            WHERE USAGE_DATE >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            GROUP BY SERVICE_NAME, DATABASE_NAME, SCHEMA_NAME
            ORDER BY total_credits DESC
        );

    ELSEIF (:REPORT_TYPE = 'daily_trend') THEN
        RETURN TABLE(
            SELECT USAGE_DATE::VARCHAR AS category,
                   NULL AS detail_1,
                   NULL AS total_calls,
                   SUM(CREDITS_BILLED) AS total_credits
            FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
            WHERE SERVICE_TYPE IN ('AI_SERVICES','CORTEX_AGENTS','CORTEX_CODE_CLI',
                                   'CORTEX_CODE_SNOWSIGHT','SNOWFLAKE_INTELLIGENCE')
              AND USAGE_DATE >= DATEADD('day', -:DAYS_BACK, CURRENT_TIMESTAMP())
            GROUP BY USAGE_DATE
            ORDER BY USAGE_DATE
        );

    ELSE
        RETURN TABLE(
            SELECT 'ERROR' AS category,
                   'Invalid report_type. Use: summary, cortex_aisql_by_model, ai_functions_by_model, cortex_search_by_service, daily_trend' AS detail_1,
                   NULL AS total_calls,
                   NULL AS total_credits
        );
    END IF;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2: Create the Cortex Agent
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE AGENT DEMO_DB.AGENTS.AI_COST_AGENT
    WAREHOUSE = 'COMPUTE_WH'
    EXTERNAL_ACCESS_INTEGRATIONS = ()
    COMMENT = 'FinOps agent for querying Snowflake AI cost data'
    AS $$
name: AI Cost Agent
description: >
  An AI agent that answers questions about Snowflake AI credit consumption,
  cost trends, and optimization opportunities.

orchestration:
  budget:
    seconds: 120
    tokens: 50000

tools:
  - name: get_ai_cost_usage
    type: procedure
    identifier: DEMO_DB.AGENTS.GET_AI_COST_USAGE
    description: >
      Retrieves AI cost usage data from Snowflake ACCOUNT_USAGE views.
      Parameters: report_type (string), days_back (number).
      Report types: summary, cortex_aisql_by_model, ai_functions_by_model,
      cortex_search_by_service, daily_trend.

response_instructions: |
  You are an AI FinOps advisor for Snowflake. When answering questions:
  1. Always call get_ai_cost_usage to get real data before responding
  2. Present costs in both credits and estimated dollars (at ~$3/credit)
  3. Highlight any anomalies or optimization opportunities
  4. Recommend specific actions when costs seem high
  5. If asked about trends, use the daily_trend report type
  6. If asked about specific services, use the appropriate report type
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 3: Test the Agent
-- ═══════════════════════════════════════════════════════════════════════════

-- Option 1: Call the stored procedure directly
CALL DEMO_DB.AGENTS.GET_AI_COST_USAGE('summary', 30);

-- Option 2: Invoke the agent (not available on trial accounts)
-- SELECT SNOWFLAKE.CORTEX.AGENT_RUN(
--     '{"agent": "DEMO_DB.AGENTS.AI_COST_AGENT", "messages": [{"role": "user", "content": [{"type": "text", "text": "What are my AI costs for the last 30 days?"}]}]}'
-- ) AS response;

-- Option 3: Agent preview
-- SELECT SNOWFLAKE.CORTEX.AGENT_PREVIEW(
--     '{"agent": "DEMO_DB.AGENTS.AI_COST_AGENT", "messages": [{"role": "user", "content": [{"type": "text", "text": "Show me a cost breakdown by model"}]}]}'
-- ) AS response;
