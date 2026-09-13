-- ═══════════════════════════════════════════════════════════════════════════
-- Module 07: Tag-based AI Feature Budgets (shared resources)
-- ═══════════════════════════════════════════════════════════════════════════
-- Docs: https://docs.snowflake.com/en/user-guide/budgets/budget-shared-resources
--
-- Domains:
--   AI FUNCTION              → AISQL / Cortex AI Functions
--   CORTEX CODE              → Snowflake CoCo (CLI, Snowsight, Desktop)
--   CORTEX AGENT             → Cortex Agents
--   SNOWFLAKE INTELLIGENCE   → Snowflake CoWork (product name)
-- ─────────────────────────────────────────────────────────────────────────────

-- STEP 1: Tag users for cost-center attribution
CREATE TAG IF NOT EXISTS cost_center;

-- Replace with real usernames in your account
-- ALTER USER ds_jane SET TAG cost_center = 'DataScience';
-- ALTER USER fin_john SET TAG cost_center = 'FinanceTeam';
-- ALTER USER USER_COCO SET TAG cost_center = 'DataScience';

-- STEP 1b: Tag the AGENT object for per-use-case attribution
-- Tagging users answers "which team spent this". Tagging the agent answers
-- "which use case spent this", regardless of who invoked it. This tag is what
-- appears in AGENT_TAGS (see QUERY 22 in 06-usage-tracking.sql).
-- Requires APPLY TAG on the account, or APPLY on the tag + OWNERSHIP of agent.
-- ALTER AGENT IF EXISTS my_support_agent SET TAG cost_center = 'CustomerSupport';
-- ALTER AGENT my_support_agent UNSET TAG cost_center;
--
-- To cap a single use case rather than a team, scope the budget to the agent
-- tag with SET_RESOURCE_TAGS instead of the SET_USER_TAGS call in STEP 3.
-- NOTE: tag changes can take up to 8 hours to be reflected in budgets.

-- STEP 2: Create budget instance and notifications
CREATE OR REPLACE SNOWFLAKE.CORE.BUDGET my_ai_budget();

CALL my_ai_budget!SET_LIMIT(5000);
CALL my_ai_budget!SET_EMAIL_NOTIFICATIONS('finops-alerts@yourcompany.com');

-- STEP 3: Scope by user tags (UNION = match any tag)
-- Adjust TAG FQN if your tag lives in a specific database.schema
CALL my_ai_budget!SET_USER_TAGS(
  [
    [(SELECT SYSTEM$REFERENCE('TAG', 'cost_center', 'SESSION', 'APPLYBUDGET')),
     'DataScience']
  ],
  'UNION'
);

-- STEP 4: Add shared AI feature domains
CALL my_ai_budget!ADD_SHARED_RESOURCE('AI FUNCTION');
CALL my_ai_budget!ADD_SHARED_RESOURCE('CORTEX CODE');
CALL my_ai_budget!ADD_SHARED_RESOURCE('CORTEX AGENT');
CALL my_ai_budget!ADD_SHARED_RESOURCE('SNOWFLAKE INTELLIGENCE');

-- Optional verification
-- CALL my_ai_budget!GET_BUDGET_SCOPE();
-- SELECT SYSTEM$SHOW_BUDGET_SHARED_RESOURCE_CANDIDATES();

-- STEP 5 (optional): CoCo hard per-user credit limits
-- ALTER ACCOUNT SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 20;
-- ALTER ACCOUNT SET CORTEX_CODE_SNOWSIGHT_DAILY_EST_CREDIT_LIMIT_PER_USER = 20;
