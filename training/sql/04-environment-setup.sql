-- ═══════════════════════════════════════════════════════════════════════════
-- AI for FinOps Training - Module 04: Environment Setup
-- FinOps for Snowflake AI · Snowflake AI FinOps Training
-- ═══════════════════════════════════════════════════════════════════════════
--
-- EXECUTION ORDER: Run statements in sequence (1-6)
-- PREREQUISITES:   ACCOUNTADMIN or SYSADMIN role
-- ESTIMATED TIME:  5-7 minutes
-- EXPECTED OUTPUT: Database, schema, warehouse, resource monitor, role, and sample data
--
-- KEY PRINCIPLE: Two cost layers exist. Resource Monitors cap WAREHOUSE COMPUTE
-- credits. Cortex AI token credits are billed separately - use Budgets and
-- METERING_DAILY_HISTORY to track AI spend.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Create Database and Schema
-- ─────────────────────────────────────────────────────────────────────────────
-- WHY: Isolated namespace for all training objects. Keeps AI experiments
-- separate from production data.

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS cortex_lab
    COMMENT = 'AI for FinOps training environment - Cortex AI experiments';

CREATE SCHEMA IF NOT EXISTS cortex_lab.ai_workshop
    COMMENT = 'Hands-on lab schema for Cortex AI exercises';

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Create Warehouse with FinOps Settings
-- ─────────────────────────────────────────────────────────────────────────────
-- WHY: 60-second auto-suspend minimizes idle compute costs.
-- SMALL size is sufficient for training workloads.

CREATE WAREHOUSE IF NOT EXISTS cortex_wh
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'AI workshop warehouse - 60s auto-suspend for cost control';

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Create Resource Monitor (Warehouse Compute Guard)
-- ─────────────────────────────────────────────────────────────────────────────
-- WHY: Resource Monitors control WAREHOUSE COMPUTE credits only.
-- They do NOT cap Cortex AI token credits, which are billed separately.
-- SUSPEND_IMMEDIATE at 90% prevents the warehouse from running up
-- compute costs during training. To track AI spend, query
-- METERING_DAILY_HISTORY or use Snowflake Budgets.

CREATE RESOURCE MONITOR IF NOT EXISTS cortex_lab_monitor
    WITH CREDIT_QUOTA = 50
    TRIGGERS
        ON 50 PERCENT DO NOTIFY
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO SUSPEND_IMMEDIATE;

-- Attach the monitor to the warehouse
ALTER WAREHOUSE cortex_wh
    SET RESOURCE_MONITOR = cortex_lab_monitor;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Create Role with Cortex Access
-- ─────────────────────────────────────────────────────────────────────────────
-- WHY: Dedicated role for training participants. Grants Cortex access
-- through the SNOWFLAKE.CORTEX_USER database role.

CREATE ROLE IF NOT EXISTS cortex_analyst
    COMMENT = 'Role for Cortex AI training participants';

-- Grant Cortex AI capabilities
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER
    TO ROLE cortex_analyst;

-- Grant access to training resources
GRANT USAGE ON WAREHOUSE cortex_wh
    TO ROLE cortex_analyst;

GRANT USAGE ON DATABASE cortex_lab
    TO ROLE cortex_analyst;

GRANT ALL ON SCHEMA cortex_lab.ai_workshop
    TO ROLE cortex_analyst;

-- Allow role to be used by your user (replace YOUR_USERNAME if needed)
GRANT ROLE cortex_analyst TO ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Load Sample Data
-- ─────────────────────────────────────────────────────────────────────────────
-- WHY: Customer feedback data for sentiment analysis and classification
-- exercises. Using SNOWFLAKE_SAMPLE_DATA which is available in all accounts.

USE SCHEMA cortex_lab.ai_workshop;
USE WAREHOUSE cortex_wh;

CREATE OR REPLACE TABLE cortex_lab.ai_workshop.customer_feedback AS
SELECT
    c.c_custkey                         AS customer_id,
    c.c_name                            AS customer_name,
    c.c_comment                         AS feedback_text,
    c.c_mktsegment                      AS market_segment,
    c.c_acctbal                         AS account_balance,
    n.n_name                            AS country,
    CURRENT_TIMESTAMP()                 AS loaded_at
FROM snowflake_sample_data.tpch_sf1.customer c
JOIN snowflake_sample_data.tpch_sf1.nation n
    ON c.c_nationkey = n.n_nationkey
LIMIT 500;

-- Grant table access to training role
GRANT SELECT ON TABLE cortex_lab.ai_workshop.customer_feedback
    TO ROLE cortex_analyst;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 6: Verify Setup
-- ─────────────────────────────────────────────────────────────────────────────
-- Run these queries to confirm everything is configured correctly.

-- Check Resource Monitor
SHOW RESOURCE MONITORS LIKE 'CORTEX_LAB_MONITOR';

-- Check Warehouse
SHOW WAREHOUSES LIKE 'CORTEX_WH';

-- Check sample data loaded
SELECT COUNT(*) AS row_count FROM cortex_lab.ai_workshop.customer_feedback;

-- Preview sample data
SELECT 
    customer_id,
    customer_name,
    LEFT(feedback_text, 80) AS feedback_preview,
    market_segment,
    country
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 5;

-- ═══════════════════════════════════════════════════════════════════════════
-- SETUP COMPLETE
-- ═══════════════════════════════════════════════════════════════════════════
-- You should see:
--   - Resource Monitor: cortex_lab_monitor (50 credit quota)
--   - Warehouse: cortex_wh (SMALL, 60s auto-suspend)
--   - Table: customer_feedback (500 rows)
--
-- Proceed to Module 05: AI SQL Hands-On Exercises
-- ═══════════════════════════════════════════════════════════════════════════
