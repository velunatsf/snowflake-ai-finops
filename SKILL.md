# FinOps for Snowflake AI — Cortex Code Skill

## Purpose

This skill enables Cortex Code to act as an AI FinOps advisor for Snowflake environments. It provides governance strategies, optimization patterns, cost tracking queries, and shadow waste detection capabilities for managing Snowflake AI credit consumption.

## When to Use

Activate this skill when users ask about:
- AI cost monitoring, tracking, or reporting on Snowflake
- Cortex AI credit consumption or token economics
- Shadow waste detection or cost optimization
- Budget setup, RBAC controls, or spend governance
- Cost attribution, chargeback, or team allocation
- Model selection for cost efficiency
- Cortex Search, Cortex Agents, or Cortex Code cost management

---

## Core Knowledge

### Snowflake AI Billing Model

Snowflake AI services are **serverless** — no warehouse to size or schedule. You pay per invocation based on tokens processed. Credits are deducted automatically.

| Dimension | Warehouse Compute | AI Services (Serverless) |
|-----------|-------------------|--------------------------|
| Billing unit | Credits per second of uptime | Credits per token processed |
| Scaling | Manual (resize warehouse) | Automatic (Snowflake-managed) |
| Idle cost | Yes (if warehouse is running) | No (pay only when called) |
| Cost control | Resource monitors, auto-suspend | Budgets, RBAC, token budgets |

### Five AI Cost Categories

| Category | ACCOUNT_USAGE View | Credit Column | Latency |
|----------|-------------------|---------------|---------|
| Cortex AI SQL | `CORTEX_AISQL_USAGE_HISTORY` | `TOKEN_CREDITS` | ~45 min |
| Cortex AI Functions | `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` | `CREDITS` | ~45 min |
| Cortex Search | `CORTEX_SEARCH_DAILY_USAGE_HISTORY` | `CREDITS` | ~45 min |
| Document AI | `DOCUMENT_AI_USAGE_HISTORY` | `CREDITS_USED` | ~45 min |
| AI Metering | `METERING_DAILY_HISTORY` | `CREDITS_BILLED` | ~45 min |

### AI Credits Transition — New SERVICE_TYPEs

Four AI services now have their own SERVICE_TYPE in METERING_DAILY_HISTORY:
- `CORTEX_AGENTS`
- `CORTEX_CODE_CLI`
- `CORTEX_CODE_SNOWSIGHT`
- `SNOWFLAKE_INTELLIGENCE`

Dashboards filtering only on `AI_SERVICES` will miss this spend.

---

## Governance Strategies

### Strategy 1: Account Budget with AI_SERVICES

```sql
-- Activate the account budget with a monthly limit
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!ACTIVATE();
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_SPENDING_LIMIT(5000);
```

### Strategy 2: Custom Budget for AI Workloads

```sql
CREATE SNOWFLAKE.CORE.BUDGET IF NOT EXISTS <db>.<schema>.AI_COST_BUDGET();
CALL <db>.<schema>.AI_COST_BUDGET!SET_SPENDING_LIMIT(500);
CALL <db>.<schema>.AI_COST_BUDGET!SET_EMAIL_NOTIFICATIONS('admin@company.com');
```

### Strategy 3: Low-Latency Budget Refresh

Default budget refresh is 6.5 hours. For tighter AI cost control:

```sql
CALL my_budget!SET_REFRESH_TIER('LOW_LATENCY');  -- 1-hour refresh (~12x budget compute cost)
```

### Strategy 4: RBAC for AI Functions

```sql
-- Remove AI access from all users by default
REVOKE USE AI FUNCTIONS ON ACCOUNT FROM ROLE PUBLIC;
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE PUBLIC;

-- Grant only to approved roles
GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE DATA_SCIENCE_ROLE;
```

### Strategy 5: Agent Orchestration Budgets

Embed cost limits in Cortex Agent specifications:

```json
"orchestration": {
    "budget": {
        "seconds": 120,
        "tokens": 50000
    }
}
```

### Strategy 6: Pre-Flight Token Estimation

```sql
-- Only process rows where token count is under a safe threshold
SELECT id, text_column
FROM my_table
WHERE SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', text_column) < 10000;
```

### Strategy 7: Query Tagging for Cost Attribution

```sql
ALTER SESSION SET QUERY_TAG = 'department=finance,project=risk_model,env=prod';
-- Run AI queries here
ALTER SESSION UNSET QUERY_TAG;
```

### Strategy 8: Cortex Code Credit Guardrails

Monitor Cortex Code consumption via dedicated views:
- `cortex_code_cli_usage_history`
- `cortex_code_snowsight_usage_history`

---

## Optimization Patterns

### Pattern 1: Right-Size the Model

| Task | Expensive Approach | Optimized Approach | Savings |
|------|-------------------|-------------------|---------|
| Sentiment | `AI_COMPLETE('claude-3-5-sonnet', ...)` | `AI_SENTIMENT(text)` | 60-80% |
| Classification | `AI_COMPLETE('llama3.1-70b', ...)` | `AI_CLASSIFY(text, [...])` | 40-70% |
| Extraction | `AI_COMPLETE('mistral-large2', ...)` | `AI_EXTRACT(text, [...])` | 40-60% |
| Filtering | `AI_COMPLETE(model, 'yes or no...')` | `AI_FILTER(text, question)` | 50-70% |

**Rule**: Use task-specific AI functions first. Fall back to AI_COMPLETE only for free-form generation.

### Pattern 2: Optimize Prompts

```sql
-- EXPENSIVE: Verbose prompt
SELECT AI_COMPLETE('mistral-large2',
    'You are an expert analyst. I need you to carefully analyze...' || long_text
) FROM my_table;

-- OPTIMIZED: Concise prompt, same result
SELECT AI_COMPLETE('mistral-large2',
    'Summarize key points: ' || long_text
) FROM my_table;
```

### Pattern 3: Incremental Processing

```sql
-- Avoid re-processing unchanged rows
SELECT id, AI_SENTIMENT(feedback_text) AS sentiment
FROM customer_feedback
WHERE ai_processed_at IS NULL;  -- Only new rows
```

### Pattern 4: Batch Over Interactive

AI functions over entire tables are more cost-efficient per token than one-off calls.

### Pattern 5: Disable Cortex Guard When Unnecessary

Cortex Guard adds token overhead. Only enable for user-facing or untrusted content.

---

## Shadow Waste Detection

### Waste 1: Over-Sized Models

```sql
SELECT MODEL_NAME, FUNCTION_NAME,
       SUM(TOKENS) AS total_tokens,
       SUM(TOKEN_CREDITS) AS total_credits,
       ROUND(SUM(TOKEN_CREDITS) / NULLIF(SUM(TOKENS), 0) * 1000000, 2) AS credits_per_1m_tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY MODEL_NAME, FUNCTION_NAME
ORDER BY credits_per_1m_tokens DESC;
```

### Waste 2: Redundant / Duplicate Calls

```sql
SELECT h.USER_ID, u.NAME, h.FUNCTION_NAME,
       DATE_TRUNC('day', h.START_TIME) AS day,
       COUNT(*) AS daily_calls, SUM(h.CREDITS) AS daily_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h
JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY h.USER_ID, u.NAME, h.FUNCTION_NAME, day
HAVING COUNT(*) > 20
ORDER BY daily_credits DESC;
```

### Waste 3: Verbose / Bloated Prompts

```sql
SELECT FUNCTION_NAME,
       DATE_TRUNC('week', USAGE_TIME) AS week,
       AVG(TOKENS) AS avg_tokens_per_call,
       SUM(TOKEN_CREDITS) AS weekly_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -60, CURRENT_TIMESTAMP())
GROUP BY FUNCTION_NAME, week
ORDER BY FUNCTION_NAME, week;
```

### Waste 4: Idle Cortex Search Services

```sql
WITH costs AS (
    SELECT SERVICE_NAME,
           SUM(CASE WHEN CONSUMPTION_TYPE = 'INDEXING' THEN CREDITS ELSE 0 END) AS idx_credits,
           SUM(CASE WHEN CONSUMPTION_TYPE = 'QUERY' THEN CREDITS ELSE 0 END) AS qry_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
    WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY SERVICE_NAME
)
SELECT SERVICE_NAME, idx_credits, qry_credits,
       ROUND(qry_credits / NULLIF(idx_credits, 0) * 100, 1) AS query_pct
FROM costs
WHERE idx_credits > 0
ORDER BY query_pct ASC;
```

### Waste 5: Uncontrolled Agent Loops

```sql
SELECT DATE_TRUNC('day', USAGE_TIME) AS day,
       MAX(TOKEN_CREDITS) AS max_call,
       AVG(TOKEN_CREDITS) AS avg_call,
       COUNT(*) AS total_calls
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -14, CURRENT_TIMESTAMP())
GROUP BY day
ORDER BY day DESC;
```

### Waste 6: Dev/Test in Production

```sql
SELECT r.VALUE::STRING AS role_name, h.FUNCTION_NAME,
       COUNT(*) AS calls, SUM(h.CREDITS) AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h,
     LATERAL FLATTEN(input => h.ROLE_NAMES) r
WHERE h.START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY role_name, h.FUNCTION_NAME
ORDER BY total_credits DESC;
```

### Waste 7: Week-over-Week Anomaly Detection

```sql
WITH daily AS (
    SELECT USAGE_DATE::DATE AS day, SUM(CREDITS_BILLED) AS credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
    WHERE SERVICE_TYPE IN ('AI_SERVICES','CORTEX_CODE_CLI','CORTEX_CODE_SNOWSIGHT')
      AND USAGE_DATE >= DATEADD('day', -60, CURRENT_DATE())
    GROUP BY day
)
SELECT day, credits,
       LAG(credits, 7) OVER (ORDER BY day) AS last_week,
       ROUND((credits - LAG(credits, 7) OVER (ORDER BY day))
             / NULLIF(LAG(credits, 7) OVER (ORDER BY day), 0) * 100, 1) AS wow_pct
FROM daily
ORDER BY day DESC;
```

### Waste 8: Missing Cost Attribution

```sql
SELECT CASE WHEN QUERY_TAG IS NOT NULL AND QUERY_TAG != ''
            THEN 'Tagged' ELSE 'Untagged' END AS attribution,
       COUNT(*) AS calls,
       SUM(TOKEN_CREDITS) AS credits,
       ROUND(SUM(TOKEN_CREDITS)
             / (SELECT SUM(TOKEN_CREDITS)
                FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
                WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP()))
             * 100, 1) AS pct_of_total
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY attribution;
```

---

## Cost Tracking Queries

### Total AI Spend Summary

```sql
SELECT FUNCTION_NAME,
       COUNT(*) AS call_count,
       ROUND(SUM(CREDITS), 4) AS total_ai_credits,
       ROUND(AVG(CREDITS), 6) AS avg_credits_per_call,
       ROUND(SUM(CREDITS) * 3, 2) AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY FUNCTION_NAME
ORDER BY total_ai_credits DESC;
```

### Cost by User (Team Attribution)

```sql
SELECT u.NAME AS user_name,
       COUNT(*) AS ai_call_count,
       ROUND(SUM(c.CREDITS), 4) AS total_ai_credits,
       ROUND(SUM(c.CREDITS) * 3, 2) AS est_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY c
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON c.USER_ID = u.USER_ID
WHERE c.START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY u.NAME
ORDER BY total_ai_credits DESC;
```

### Cortex Code Usage Tracking

```sql
-- CLI usage
SELECT user_name, DATE_TRUNC('day', event_timestamp) AS usage_date,
       COUNT(*) AS sessions, SUM(total_tokens) AS total_tokens,
       ROUND(SUM(total_credits), 4) AS total_credits
FROM snowflake.account_usage.cortex_code_cli_usage_history
WHERE event_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY 1, 2 ORDER BY 2 DESC;

-- Snowsight usage
SELECT user_name, DATE_TRUNC('day', event_timestamp) AS usage_date,
       COUNT(*) AS sessions, SUM(total_tokens) AS total_tokens,
       ROUND(SUM(total_credits), 4) AS total_credits
FROM snowflake.account_usage.cortex_code_snowsight_usage_history
WHERE event_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY 1, 2 ORDER BY 2 DESC;
```

---

## FinOps Maturity Model

| Level | Characteristics | Actions |
|-------|----------------|---------|
| **Crawl** | No visibility into AI costs; no budgets | Activate account budget; query ACCOUNT_USAGE monthly |
| **Walk** | Basic budgets; cost reviewed weekly | Custom budgets per team; RBAC for AI functions; query tagging |
| **Run** | Automated alerts and actions; continuous optimization | Low-latency budgets; automated actions; token pre-flight; model right-sizing |

---

## Extensibility

This skill file is designed for community extension. To add new governance strategies:

1. Add a new `### Strategy N:` section under **Governance Strategies**
2. Include the SQL or configuration needed
3. Explain when to use it and expected savings
4. Submit a PR with your addition

To add new shadow waste patterns:

1. Add a new `### Waste N:` section under **Shadow Waste Detection**
2. Include the detection query
3. Document the fix/workaround
4. Include typical savings percentage

---

## References

- [Snowflake Credit Consumption Table (PDF)](https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf)
- [Snowflake CoCo CLI Getting Started](https://www.snowflake.com/en/developers/guides/getting-started-with-cortex-code-cli/)
- [Snowflake Budgets Documentation](https://docs.snowflake.com/en/user-guide/budgets)
- [FinOps Foundation](https://www.finops.org)
