# Shadow Waste in Snowflake AI -- Deep Dive Presentation Guide

**Audience**: Snowflake administrators, FinOps practitioners, data engineers, AI/ML teams
**Purpose**: Identify, trace, and eliminate hidden AI credit waste in Snowflake

---

## What is Shadow Waste?

Shadow waste is AI credit consumption that delivers **little or no business value**.
It is called "shadow" because:

- AI services are **serverless** -- there is no warehouse to watch
- Costs appear only in ACCOUNT_USAGE views with **45-minute latency**
- No query fails, no alert fires -- credits silently drain
- Traditional monitoring (resource monitors) **does not cover AI services**

**Real-world impact**: A single AI_FILTER call on 726,907 tokens consumed
1.01 credits in seconds. Multiply that by a scheduled pipeline running
hourly on a million-row table, and shadow waste can reach hundreds of
credits per day without anyone noticing.

---

## Shadow Waste Pattern 1: Over-Sized Models

### Problem statement

Developers default to the most capable (and most expensive) model for
every task. A sentiment analysis job using `claude-3-5-sonnet` via
AI_COMPLETE costs significantly more than the purpose-built
`AI_SENTIMENT` function, which uses an optimized smaller model internally.

**Example from real usage data:**

| Approach | Model | Credits/1M tokens | Task |
|----------|-------|-------------------|------|
| AI_COMPLETE | mistral-large2 | ~1.84 | Sentiment analysis |
| AI_SENTIMENT | (managed, optimized) | ~1.60 | Sentiment analysis |
| AI_COMPLETE | claude-3-5-sonnet | ~5.51 | Classification |
| AI_CLASSIFY | (managed, optimized) | ~1.39 | Classification |

Using AI_COMPLETE with a large model for classification costs **~4x more**
than AI_CLASSIFY.

### How to trace

```sql
-- Find AI_COMPLETE calls and compare against task-specific alternatives
SELECT
    FUNCTION_NAME,
    MODEL_NAME,
    COUNT(*) AS call_count,
    SUM(CREDITS) AS total_credits,
    AVG(CREDITS) AS avg_credits_per_call,
    SUM(CREDITS) / NULLIF(COUNT(*), 0) AS cost_per_call
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY FUNCTION_NAME, MODEL_NAME
ORDER BY total_credits DESC;
```

```sql
-- Compare token rates: are expensive models doing simple work?
SELECT
    MODEL_NAME,
    FUNCTION_NAME,
    SUM(TOKENS) AS total_tokens,
    SUM(TOKEN_CREDITS) AS total_credits,
    ROUND(SUM(TOKEN_CREDITS) / NULLIF(SUM(TOKENS), 0) * 1000000, 2) AS credits_per_1m_tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY MODEL_NAME, FUNCTION_NAME
ORDER BY credits_per_1m_tokens DESC;
```

### Solution / workaround / cost controls

1. **Replace AI_COMPLETE with task-specific functions** where possible:

   | Instead of | Use | Savings |
   |-----------|-----|---------|
   | `AI_COMPLETE(model, 'What is the sentiment...')` | `AI_SENTIMENT(text)` | 40-70% |
   | `AI_COMPLETE(model, 'Classify as A/B/C...')` | `AI_CLASSIFY(text, ['A','B','C'])` | 50-75% |
   | `AI_COMPLETE(model, 'Extract name and date...')` | `AI_EXTRACT(text, ['name','date'])` | 30-60% |
   | `AI_COMPLETE(model, 'Is this about X? Yes/No')` | `AI_FILTER(text, 'Is this about X?')` | 50-70% |

2. **Downsize models for simple tasks**: Use `mistral-7b` or `llama3.1-8b`
   instead of `claude-3-5-sonnet` or `llama3.1-70b` for straightforward
   extraction, summarization of short texts, or simple Q&A.

3. **Benchmark quality**: Run 100 sample rows through both the expensive
   and cheap approach. If accuracy is comparable, switch permanently.

### SQL to validate the fix

```sql
-- After migration: verify no AI_COMPLETE calls for tasks covered by
-- task-specific functions (run weekly)
SELECT
    FUNCTION_NAME,
    MODEL_NAME,
    COUNT(*) AS call_count,
    SUM(CREDITS) AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND FUNCTION_NAME = 'AI_COMPLETE'
GROUP BY FUNCTION_NAME, MODEL_NAME
ORDER BY total_credits DESC;
-- Expect: only legitimate generative use cases remain
```

### Key takeaways

- Task-specific functions (AI_SENTIMENT, AI_CLASSIFY, AI_FILTER) are
  purpose-built and cheaper than AI_COMPLETE for their specific task
- Model choice is the single largest cost lever -- a 4x rate difference
  is common between large and small models
- Always benchmark before choosing a model; the biggest model is rarely
  necessary

---

## Shadow Waste Pattern 2: Redundant / Duplicate AI Calls

### Problem statement

The same AI function is called repeatedly with identical inputs because:

- Pipelines re-process unchanged rows on every scheduled run
- No caching layer exists between the application and Snowflake
- Multiple users/notebooks run overlapping queries on the same data
- Retry logic re-submits successful calls

**Cost multiplier**: If a pipeline runs hourly and processes 10,000 rows
that haven't changed, you pay for the same tokens 24 times per day.

### How to trace

```sql
-- Find queries with high repetition counts on the same function
SELECT
    QUERY_TAG,
    FUNCTION_NAME,
    COUNT(*) AS repetitions,
    SUM(TOKEN_CREDITS) AS total_credits,
    MIN(USAGE_TIME) AS first_call,
    MAX(USAGE_TIME) AS last_call
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY QUERY_TAG, FUNCTION_NAME
HAVING COUNT(*) > 10
ORDER BY total_credits DESC;
```

```sql
-- Find repeated AI function calls by the same user on the same day
SELECT
    h.USER_ID,
    u.NAME AS user_name,
    h.FUNCTION_NAME,
    DATE_TRUNC('day', h.START_TIME) AS call_date,
    COUNT(*) AS daily_calls,
    SUM(h.CREDITS) AS daily_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h
JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY h.USER_ID, u.NAME, h.FUNCTION_NAME, call_date
HAVING COUNT(*) > 20
ORDER BY daily_credits DESC;
```

### Solution / workaround / cost controls

1. **Incremental processing**: Only process new or changed rows:

   ```sql
   -- Add a processed_at column and only process unprocessed rows
   SELECT id, AI_SENTIMENT(review_text) AS sentiment
   FROM customer_reviews
   WHERE ai_processed_at IS NULL;

   -- After processing, mark rows
   UPDATE customer_reviews
   SET ai_processed_at = CURRENT_TIMESTAMP()
   WHERE ai_processed_at IS NULL;
   ```

2. **Cache results in a table**: Store AI function output alongside the
   source data and re-query the cache instead of re-calling the function.

3. **Use query tagging**: Tag pipelines so duplicates are identifiable:

   ```sql
   ALTER SESSION SET QUERY_TAG = 'pipeline=sentiment_daily,run_id=20260407';
   ```

4. **Deduplicate inputs**: Before calling AI functions, deduplicate your
   input data to avoid processing the same text multiple times.

### SQL to validate the fix

```sql
-- After implementing incremental processing: check for duplicate calls
SELECT
    FUNCTION_NAME,
    DATE_TRUNC('day', START_TIME) AS day,
    COUNT(*) AS calls,
    SUM(CREDITS) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY FUNCTION_NAME, day
ORDER BY day DESC, credits DESC;
-- Expect: call counts should be stable or declining, not growing
```

### Key takeaways

- Incremental processing is the most effective way to eliminate duplicate
  AI calls
- Cache AI results in a column or table -- AI output is deterministic
  enough for most use cases
- Query tags make it trivial to identify which pipeline is duplicating

---

## Shadow Waste Pattern 3: Verbose / Bloated Prompts

### Problem statement

Developers write prompts with excessive instructions, redundant context,
or pass entire documents when only a paragraph is relevant. Every extra
token in the prompt costs money.

**Real example**: A 50-word filler prompt adds ~67 tokens per row. Over
100,000 rows at 1.84 credits/1M tokens, that is 12.3 credits wasted on
instructions the model doesn't need.

### How to trace

```sql
-- Find calls with unusually high token counts relative to credit spend
SELECT
    FUNCTION_NAME,
    MODEL_NAME,
    TOKENS,
    TOKEN_CREDITS,
    QUERY_ID,
    TOKENS_GRANULAR
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
ORDER BY TOKENS DESC
LIMIT 20;
```

```sql
-- Use AI_COUNT_TOKENS to audit prompt sizes before batch runs
SELECT
    id,
    SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', prompt_text) AS token_count
FROM my_prompts
ORDER BY token_count DESC
LIMIT 50;
```

### Solution / workaround / cost controls

1. **Trim prompts**: Remove filler phrases:

   | Before (wasteful) | After (lean) |
   |-------------------|-------------|
   | "You are an expert analyst. I need you to carefully analyze the following text and provide a detailed classification. Please be thorough." | "Classify:" |
   | "Please read the following text and tell me what the sentiment is. Make sure to consider context and nuance." | (use `AI_SENTIMENT()` directly) |

2. **Pre-filter data**: Truncate or extract the relevant portion before
   sending to the model:

   ```sql
   -- Only send first 500 characters instead of full document
   SELECT AI_SENTIMENT(LEFT(document_text, 500)) AS sentiment
   FROM long_documents;
   ```

3. **Use system prompts for repeated instructions**: When using
   AI_COMPLETE, put instructions in the system message (sent once) rather
   than prepending to every user message.

4. **Pre-flight token budget**: Reject rows that exceed a threshold:

   ```sql
   SELECT id, text_column
   FROM source_table
   WHERE SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', text_column) < 5000;
   ```

### SQL to validate the fix

```sql
-- Compare average tokens per call before and after prompt optimization
-- Run this after deploying optimized prompts
SELECT
    FUNCTION_NAME,
    DATE_TRUNC('week', USAGE_TIME) AS week,
    AVG(TOKENS) AS avg_tokens_per_call,
    SUM(TOKEN_CREDITS) AS weekly_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -60, CURRENT_TIMESTAMP())
GROUP BY FUNCTION_NAME, week
ORDER BY FUNCTION_NAME, week;
-- Expect: avg_tokens_per_call decreasing over time
```

### Key takeaways

- Every token costs money -- prompt engineering is cost engineering
- `AI_COUNT_TOKENS` is your pre-flight check; use it before batch runs
- Truncating input to relevant sections can cut costs 50%+ with no
  quality loss
- Task-specific functions eliminate prompt overhead entirely

---

## Shadow Waste Pattern 4: Idle Cortex Search Services

### Problem statement

Cortex Search services consume credits for **indexing** even when no
queries are made. A search service created for a POC, demo, or abandoned
project continues to index data on schedule, draining credits invisibly.

Unlike AI functions (pay per call), Search services have a **standing
cost** that accrues regardless of usage.

### How to trace

```sql
-- Find Search services with indexing cost but zero or low query volume
SELECT
    SERVICE_NAME,
    DATABASE_NAME,
    SCHEMA_NAME,
    CONSUMPTION_TYPE,
    SUM(CREDITS) AS total_credits,
    SUM(TOKENS) AS total_tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY SERVICE_NAME, DATABASE_NAME, SCHEMA_NAME, CONSUMPTION_TYPE
ORDER BY total_credits DESC;
```

```sql
-- Identify services: compare INDEXING vs QUERY credits
WITH service_costs AS (
    SELECT
        SERVICE_NAME,
        SUM(CASE WHEN CONSUMPTION_TYPE = 'INDEXING' THEN CREDITS ELSE 0 END) AS indexing_credits,
        SUM(CASE WHEN CONSUMPTION_TYPE = 'QUERY' THEN CREDITS ELSE 0 END) AS query_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
    WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY SERVICE_NAME
)
SELECT
    SERVICE_NAME,
    indexing_credits,
    query_credits,
    ROUND(query_credits / NULLIF(indexing_credits, 0) * 100, 1) AS query_to_index_pct
FROM service_costs
WHERE indexing_credits > 0
ORDER BY query_to_index_pct ASC;
-- Services with low query_to_index_pct are idle waste
```

### Solution / workaround / cost controls

1. **Drop unused Search services**:

   ```sql
   DROP CORTEX SEARCH SERVICE IF EXISTS DB.SCHEMA.ABANDONED_POC_SEARCH;
   ```

2. **Audit Search services quarterly**: Schedule a review to check
   whether each service is actively queried.

3. **Consolidate services**: If multiple services index overlapping data,
   merge them into one.

4. **Tag services by project/owner**: Use comments or naming conventions
   so ownership is traceable:

   ```sql
   COMMENT ON CORTEX SEARCH SERVICE DB.SCHEMA.MY_SEARCH IS
       'owner=data_team, project=customer_support, created=2026-01';
   ```

### SQL to validate the fix

```sql
-- After cleanup: confirm no idle services remain
SELECT SERVICE_NAME, SUM(CREDITS) AS monthly_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND CONSUMPTION_TYPE = 'INDEXING'
GROUP BY SERVICE_NAME
ORDER BY monthly_credits DESC;
-- Cross-reference with active project list; any unrecognized service is waste
```

### Key takeaways

- Cortex Search has a standing cost (indexing) unlike pay-per-call AI
  functions
- An idle Search service is 100% waste -- it provides zero value while
  consuming credits
- Quarterly audits of Search services should be a standard FinOps
  practice
- Name and comment services with ownership metadata for traceability

---

## Shadow Waste Pattern 5: Uncontrolled Agent Loops

### Problem statement

Cortex Agents orchestrate multi-step tool calls. Without budget
constraints, an agent can enter a loop -- repeatedly calling tools,
retrying failed operations, or over-thinking a simple question -- burning
tokens with every iteration.

**Worst case**: An agent with no token budget processing a complex
question could consume 100,000+ tokens in a single invocation, costing
0.18+ credits for one user question.

### How to trace

```sql
-- Find expensive individual AI SQL calls (potential agent loops)
SELECT
    QUERY_ID,
    FUNCTION_NAME,
    MODEL_NAME,
    TOKENS,
    TOKEN_CREDITS,
    TOKENS_GRANULAR,
    USAGE_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY TOKEN_CREDITS DESC
LIMIT 20;
```

```sql
-- Find users with disproportionately high per-call costs (agent users)
SELECT
    u.NAME AS user_name,
    COUNT(*) AS total_calls,
    SUM(h.TOKEN_CREDITS) AS total_credits,
    AVG(h.TOKEN_CREDITS) AS avg_credits_per_call,
    MAX(h.TOKEN_CREDITS) AS max_single_call
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY h
JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY u.NAME
HAVING AVG(h.TOKEN_CREDITS) > 0.01
ORDER BY avg_credits_per_call DESC;
```

### Solution / workaround / cost controls

1. **Set agent token and time budgets**:

   ```json
   "orchestration": {
       "budget": {
           "seconds": 120,
           "tokens": 50000
       }
   }
   ```

2. **Set query_timeout on agent tools**:

   ```json
   "tool_resources": {
       "sql_tool": {
           "execution_environment": {
               "query_timeout": 60
           }
       }
   }
   ```

3. **Limit tool iterations**: Design agent instructions to avoid open-ended
   loops. Be specific about when the agent should stop and return a result.

4. **Monitor agent-specific costs**: Tag agent queries and track them
   separately.

### SQL to validate the fix

```sql
-- After adding budgets: verify max per-call cost has decreased
SELECT
    DATE_TRUNC('day', USAGE_TIME) AS day,
    MAX(TOKEN_CREDITS) AS max_single_call,
    AVG(TOKEN_CREDITS) AS avg_per_call,
    COUNT(*) AS total_calls
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -14, CURRENT_TIMESTAMP())
GROUP BY day
ORDER BY day DESC;
-- Expect: max_single_call should be capped at your budget limit
```

### Key takeaways

- Agents without budgets are unbounded cost risks
- Token budgets and time limits are the primary controls
- High avg_credits_per_call for a user is a strong signal of agent loops
- Design agent instructions to be deterministic and bounded

---

## Shadow Waste Pattern 6: Dev/Test Workloads in Production

### Problem statement

Developers and data scientists experiment with AI functions using
production credentials and production-tier models. Notebook experiments,
ad-hoc queries, and prototype pipelines all consume production credits
without producing business value.

### How to trace

```sql
-- Find AI usage by role to identify non-production activity
SELECT
    r.VALUE::STRING AS role_name,
    h.FUNCTION_NAME,
    COUNT(*) AS calls,
    SUM(h.CREDITS) AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h,
    LATERAL FLATTEN(input => h.ROLE_NAMES) r
WHERE h.START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY role_name, h.FUNCTION_NAME
ORDER BY total_credits DESC;
```

```sql
-- Find users running AI functions outside business hours (likely dev/test)
SELECT
    u.NAME AS user_name,
    HOUR(h.USAGE_TIME) AS hour_of_day,
    COUNT(*) AS calls,
    SUM(h.TOKEN_CREDITS) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY h
JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY u.NAME, hour_of_day
ORDER BY credits DESC
LIMIT 30;
```

### Solution / workaround / cost controls

1. **Separate dev and prod accounts**: Use Snowflake Organizations to
   maintain separate accounts with separate credit pools.

2. **RBAC for AI functions**: Revoke AI access from dev roles in
   production:

   ```sql
   -- Remove AI access from developer roles in production
   REVOKE USE AI FUNCTIONS ON ACCOUNT FROM ROLE DEV_ROLE;
   REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE DEV_ROLE;

   -- Grant only to production pipeline roles
   GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE PROD_PIPELINE_ROLE;
   ```

3. **Custom budgets per environment**: Create separate budgets for dev
   and prod workloads:

   ```sql
   CREATE SNOWFLAKE.CORE.BUDGET IF NOT EXISTS ADMIN_DB.BUDGETS.DEV_AI_BUDGET();
   CALL ADMIN_DB.BUDGETS.DEV_AI_BUDGET!SET_SPENDING_LIMIT(50);
   ```

4. **Query tagging by environment**: Enforce tagging so costs are
   attributable:

   ```sql
   ALTER SESSION SET QUERY_TAG = 'env=dev,user=analyst1';
   ```

### SQL to validate the fix

```sql
-- After RBAC changes: confirm dev roles have no AI function access
SHOW GRANTS OF ROLE DEV_ROLE;
-- Expect: no USE AI FUNCTIONS privilege

-- Verify no AI calls from dev roles
SELECT
    r.VALUE::STRING AS role_name,
    SUM(h.CREDITS) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h,
    LATERAL FLATTEN(input => h.ROLE_NAMES) r
WHERE h.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND r.VALUE::STRING ILIKE '%DEV%'
GROUP BY role_name;
-- Expect: zero rows
```

### Key takeaways

- Dev/test AI usage in production is invisible unless you query for it
- RBAC is the strongest control -- revoke AI privileges from non-production
  roles
- Query tagging + cost attribution makes dev waste visible and
  accountable
- Separate budgets for dev vs prod prevent experimentation from draining
  production credits

---

## Shadow Waste Pattern 7: Cost Trend Anomalies (Spike Detection)

### Problem statement

A new pipeline, a code change, or a misconfigured schedule causes a
sudden spike in AI credit consumption. Without trend monitoring, the
spike goes unnoticed until the monthly bill arrives.

**Real scenario**: A developer changes a WHERE clause, and a pipeline
that previously processed 1,000 rows now processes 1,000,000 rows
through AI_FILTER. Daily cost jumps from 1 credit to 1,000 credits.

### How to trace

```sql
-- Daily AI cost trend with week-over-week comparison
WITH daily AS (
    SELECT
        USAGE_DATE::DATE AS day,
        SUM(CREDITS_BILLED) AS daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
    WHERE SERVICE_TYPE ILIKE '%AI%'
      AND USAGE_DATE >= DATEADD('day', -60, CURRENT_DATE())
    GROUP BY day
)
SELECT
    day,
    daily_credits,
    LAG(daily_credits, 7) OVER (ORDER BY day) AS same_day_last_week,
    ROUND((daily_credits - LAG(daily_credits, 7) OVER (ORDER BY day))
        / NULLIF(LAG(daily_credits, 7) OVER (ORDER BY day), 0) * 100, 1)
        AS wow_change_pct
FROM daily
ORDER BY day DESC;
-- Rows with wow_change_pct > 200% are anomalies
```

```sql
-- Per-function daily trend to isolate which function spiked
SELECT
    DATE_TRUNC('day', START_TIME) AS day,
    FUNCTION_NAME,
    COUNT(*) AS calls,
    SUM(CREDITS) AS daily_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY day, FUNCTION_NAME
ORDER BY day DESC, daily_credits DESC;
```

### Solution / workaround / cost controls

1. **Activate account budget with notifications**:

   ```sql
   CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!ACTIVATE();
   CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_SPENDING_LIMIT(5000);
   CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_EMAIL_NOTIFICATIONS(
       'finops@company.com'
   );
   ```

2. **Enable low-latency refresh** for faster spike detection (1 hour
   instead of 6.5 hours):

   ```sql
   CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_REFRESH_TIER('LOW_LATENCY');
   ```

3. **Custom budget actions** to auto-suspend when thresholds are hit.

4. **Build a Streamlit dashboard** (like the AI Cost Dashboard from this
   project) to visualize daily trends and make anomalies visible.

5. **Use the GET_AI_COST_USAGE stored procedure** for quick trend checks:

   ```sql
   CALL DEMO_DB.AGENTS.GET_AI_COST_USAGE('daily_trend', 30::FLOAT);
   ```

### SQL to validate the fix

```sql
-- After setting up budgets: verify budget is active and tracking
SELECT
    BUDGET_NAME,
    SPENDING_LIMIT,
    CREDIT_QUOTA
FROM SNOWFLAKE.DATA_SHARING_USAGE.BUDGET_SPENDING_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 5;
```

```sql
-- Verify daily trend is stable (no spikes > 3x average)
WITH daily AS (
    SELECT
        USAGE_DATE::DATE AS day,
        SUM(CREDITS_BILLED) AS credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
    WHERE SERVICE_TYPE ILIKE '%AI%'
      AND USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
    GROUP BY day
)
SELECT
    day,
    credits,
    AVG(credits) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7d_avg,
    credits / NULLIF(AVG(credits) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0) AS spike_ratio
FROM daily
ORDER BY day DESC;
-- spike_ratio > 3.0 = anomaly worth investigating
```

### Key takeaways

- AI cost spikes are invisible without trend monitoring
- Budgets with email notifications are the minimum viable control
- Low-latency refresh reduces detection delay from 6.5 hours to 1 hour
- Week-over-week comparison is the simplest anomaly detection method
- A Streamlit dashboard makes trends visible to non-SQL users

---

## Shadow Waste Pattern 8: Missing Cost Attribution

### Problem statement

Without tagging or role-based tracking, AI costs are a single aggregated
number. Nobody knows which team, project, or pipeline is responsible for
the spend. This makes it impossible to:

- Charge costs back to the right department
- Identify who should optimize
- Prioritize waste reduction efforts

### How to trace

```sql
-- Check how much AI spend has NO query tag (unattributed)
SELECT
    CASE WHEN QUERY_TAG IS NOT NULL AND QUERY_TAG != '' THEN 'Tagged' ELSE 'Untagged' END AS attribution,
    COUNT(*) AS calls,
    SUM(TOKEN_CREDITS) AS total_credits,
    ROUND(SUM(TOKEN_CREDITS) / (SELECT SUM(TOKEN_CREDITS)
        FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
        WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())) * 100, 1) AS pct_of_total
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY attribution;
```

```sql
-- Break down AI spend by user to identify unattributed consumers
SELECT
    u.NAME AS user_name,
    h.QUERY_TAG,
    COUNT(*) AS calls,
    SUM(h.TOKEN_CREDITS) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY h
JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND (h.QUERY_TAG IS NULL OR h.QUERY_TAG = '')
GROUP BY u.NAME, h.QUERY_TAG
ORDER BY credits DESC
LIMIT 20;
```

### Solution / workaround / cost controls

1. **Enforce query tagging** for all AI workloads:

   ```sql
   -- Set at session level for pipelines
   ALTER SESSION SET QUERY_TAG = 'team=data_science,project=churn_model,env=prod';

   -- Set at warehouse level as a default
   ALTER WAREHOUSE AI_WH SET QUERY_TAG = 'team=ai_platform';
   ```

2. **Create a tagging standard**: Define a consistent format:

   ```
   Format: team=<team>,project=<project>,env=<env>
   Example: team=marketing,project=sentiment_pipeline,env=prod
   ```

3. **Build cost attribution reports**:

   ```sql
   -- Monthly cost by team (using query tags)
   SELECT
       SPLIT_PART(QUERY_TAG, ',', 1) AS team_tag,
       SUM(TOKEN_CREDITS) AS monthly_credits
   FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
   WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
     AND QUERY_TAG IS NOT NULL
   GROUP BY team_tag
   ORDER BY monthly_credits DESC;
   ```

4. **Custom budgets per team**: Pair tagging with budgets for
   accountability:

   ```sql
   CREATE SNOWFLAKE.CORE.BUDGET IF NOT EXISTS ADMIN_DB.BUDGETS.MARKETING_AI();
   CALL ADMIN_DB.BUDGETS.MARKETING_AI!SET_SPENDING_LIMIT(200);
   ```

### SQL to validate the fix

```sql
-- After enforcing tagging: check tagging coverage rate
SELECT
    CASE WHEN QUERY_TAG IS NOT NULL AND QUERY_TAG != '' THEN 'Tagged' ELSE 'Untagged' END AS status,
    COUNT(*) AS calls,
    SUM(TOKEN_CREDITS) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY status;
-- Target: >90% of credits should be tagged
```

### Key takeaways

- Unattributed AI spend cannot be optimized -- you can't fix what you
  can't measure
- Query tagging is free and takes one line of SQL per session
- A consistent tagging standard enables automated cost reporting
- Combine tagging with custom budgets for team-level accountability

---

## Executive Summary: Shadow Waste at a Glance

| # | Pattern | Detection signal | Primary control | Potential savings |
|---|---------|-----------------|-----------------|-------------------|
| 1 | Over-sized models | High credits_per_1m_tokens on simple tasks | Switch to task-specific AI functions | 40-75% |
| 2 | Redundant calls | High repetition counts, stable input data | Incremental processing, caching | 50-90% |
| 3 | Verbose prompts | High token counts, low output value | Prompt engineering, AI_COUNT_TOKENS | 20-50% |
| 4 | Idle Search services | Indexing credits with zero query credits | Drop unused services | 100% of idle cost |
| 5 | Uncontrolled agents | High max per-call cost, agent loops | Token/time budgets in agent spec | 30-60% |
| 6 | Dev/test in production | Non-production roles consuming credits | RBAC, separate accounts/budgets | Variable |
| 7 | Cost spikes | >200% week-over-week increase | Budgets with notifications, trend monitoring | Prevents runaway costs |
| 8 | Missing attribution | >50% credits with no query tag | Enforce query tagging standard | Enables all other optimizations |

---

## Action Plan: Getting Started

**Week 1 -- Visibility**
- [ ] Activate account budget with email notifications
- [ ] Run the "top spenders" and "cost by function" queries
- [ ] Deploy the AI Cost Dashboard (Streamlit app)

**Week 2 -- Quick wins**
- [ ] Identify and drop idle Cortex Search services
- [ ] Replace obvious AI_COMPLETE misuse with task-specific functions
- [ ] Set token budgets on all Cortex Agents

**Week 3 -- Governance**
- [ ] Implement query tagging standard across teams
- [ ] Revoke AI function access from non-production roles
- [ ] Create custom budgets for each team/department

**Ongoing**
- [ ] Review weekly trend reports for anomalies
- [ ] Quarterly audit of Search services and agent configurations
- [ ] Benchmark new models vs. existing for cost/quality tradeoffs

---

## Quick Reference: Key ACCOUNT_USAGE Views

| View | What it tracks | Key columns |
|------|---------------|-------------|
| `CORTEX_AISQL_USAGE_HISTORY` | Cortex Analyst, Agents, Intelligence | `TOKEN_CREDITS`, `TOKENS`, `TOKENS_GRANULAR`, `QUERY_TAG`, `USER_ID` |
| `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` | AI_COMPLETE, AI_SENTIMENT, AI_CLASSIFY, etc. | `CREDITS`, `FUNCTION_NAME`, `MODEL_NAME`, `ROLE_NAMES`, `QUERY_TAG` |
| `CORTEX_SEARCH_DAILY_USAGE_HISTORY` | Cortex Search indexing and queries | `CREDITS`, `SERVICE_NAME`, `CONSUMPTION_TYPE` |
| `DOCUMENT_AI_USAGE_HISTORY` | Document AI extraction | `CREDITS_USED`, `MODEL_NAME` |
| `METERING_DAILY_HISTORY` | Aggregated daily metering | `CREDITS_BILLED`, `SERVICE_TYPE` (filter: `AI_SERVICES`) |
| `USERS` | User lookup (join on USER_ID) | `USER_ID`, `NAME` |
