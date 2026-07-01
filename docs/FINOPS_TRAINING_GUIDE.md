# FinOps for Snowflake AI -- Training Guide

A practitioner's guide to managing, optimizing, and controlling the cost
of AI and ML workloads running on Snowflake.

---

## 1. FinOps for Snowflake AI overview

### 1.1 What is FinOps?

FinOps (Financial Operations) is the practice of bringing financial
accountability to cloud spending. Applied to Snowflake AI, FinOps means:

- **Visibility**: Knowing exactly where AI credits are consumed.
- **Optimization**: Choosing the right model and function for the task.
- **Governance**: Enforcing budgets, roles, and limits before costs spiral.

### 1.2 How Snowflake AI billing works

Snowflake AI services are **serverless**. There is no warehouse to size
or schedule -- you pay per invocation based on tokens processed. Credits
are deducted from your Snowflake credit balance automatically.

This is fundamentally different from warehouse billing:

| Dimension | Warehouse compute | AI services (serverless) |
|-----------|-------------------|--------------------------|
| Billing unit | Credits per second of uptime | Credits per token processed |
| Scaling | Manual (resize warehouse) | Automatic (Snowflake-managed) |
| Idle cost | Yes (if warehouse is running) | No (pay only when called) |
| Cost control | Resource monitors, auto-suspend | Budgets, RBAC, token budgets |
| Metering view | `WAREHOUSE_METERING_HISTORY` | `CORTEX_AI_FUNCTIONS_USAGE_HISTORY`, `CORTEX_AISQL_USAGE_HISTORY`, etc. |

### 1.3 The five AI cost categories

| Category | What it covers | ACCOUNT_USAGE view | Credit column |
|----------|---------------|-------------------|---------------|
| **Cortex AI SQL** | Cortex Analyst, Cortex Agents, Snowflake Intelligence | `CORTEX_AISQL_USAGE_HISTORY` | `TOKEN_CREDITS` |
| **Cortex AI Functions** | AI_COMPLETE, AI_EXTRACT, AI_SENTIMENT, AI_CLASSIFY, AI_FILTER, AI_AGG, AI_TRANSLATE, AI_EMBED, AI_REDACT, AI_PARSE_DOCUMENT, AI_TRANSCRIBE | `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` | `CREDITS` |
| **Cortex Search** | Vector search services (indexing + querying) | `CORTEX_SEARCH_DAILY_USAGE_HISTORY` | `CREDITS` |
| **Document AI** | Document extraction models | `DOCUMENT_AI_USAGE_HISTORY` | `CREDITS_USED` |
| **AI Metering** | Aggregated AI_SERVICES metering | `METERING_DAILY_HISTORY` (filter `SERVICE_TYPE ILIKE '%AI%'`) | `CREDITS_BILLED` |

### 1.4 Data latency

ACCOUNT_USAGE views have up to **45 minutes** of latency. For
near-real-time monitoring, use Snowflake Budgets with low-latency refresh
(1-hour interval). Real-time, per-query cost is not available.

---

## 2. Token economy

### 2.1 What is a token?

A token is the fundamental billing unit for Snowflake AI services. Tokens
are sub-word units that LLMs use to process text:

- ~1 token = ~4 characters of English text
- ~1 token = ~0.75 words
- 1,000 tokens ~ 750 words

Snowflake charges **credits per token** processed. Both input tokens
(your prompt) and output tokens (the model's response) are counted.

### 2.2 Checking token counts before calling

Use `AI_COUNT_TOKENS` to estimate cost before making an expensive call:

```sql
-- Count tokens for a prompt against a specific model
SELECT SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('mistral-large2', 'Summarize the quarterly earnings report...');

-- Count tokens for a function-specific call
SELECT SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', 'This product is excellent quality');
```

This lets you pre-flight check whether a call will be expensive before
incurring the cost.

### 2.3 Credit rates by function and model

Different AI functions and models have different credit-per-token rates.
Below are real rates observed from `CORTEX_AISQL_USAGE_HISTORY`:

| Function | Model | Credits per 1M tokens | Typical use case |
|----------|-------|----------------------|------------------|
| AI_COMPLETE | mistral-large2 | ~1.84 | General-purpose text generation |
| AI_FILTER | (managed) | ~1.39 | Boolean classification at scale |
| AI_AGG | (managed) | ~1.60 | Aggregating insights across rows |
| AI_CLASSIFY | (managed) | ~1.39 | Multi-label categorization |
| AI_SENTIMENT | (managed) | ~1.60 | Sentiment scoring |
| AI_TRANSLATE | (managed) | ~1.50 | Language translation |
| AI_EXTRACT | arctic-extract | ~5.00 | Entity/field extraction |

**Key insight**: Task-specific functions (AI_SENTIMENT, AI_CLASSIFY) are
often cheaper per token than general-purpose AI_COMPLETE because they use
optimized, smaller models internally.

### 2.4 Granular token tracking

The `CORTEX_AISQL_USAGE_HISTORY` view includes two JSON columns for
fine-grained cost attribution:

| Column | Type | Contains |
|--------|------|----------|
| `TOKENS_GRANULAR` | OBJECT | Breakdown of tokens by input/output/reasoning |
| `TOKEN_CREDITS_GRANULAR` | OBJECT | Corresponding credit breakdown |

```sql
-- See granular token breakdown for recent AI SQL calls
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
```

### 2.5 The token cost formula

```
Cost of a call = (input_tokens + output_tokens) * credit_rate_per_token * price_per_credit
```

For example, with a $2/credit pricing:
- AI_COMPLETE call with mistral-large2 processing 10,000 tokens
- Credits = 10,000 * (1.84 / 1,000,000) = 0.0184 credits
- Dollar cost = 0.0184 * $2 = $0.0368

---

## 3. How FinOps for Snowflake AI helps price/performance

### 3.1 Right-size the model

The most impactful cost optimization is choosing the smallest model that
meets your quality requirements.

| Task | Expensive approach | Optimized approach | Savings |
|------|-------------------|-------------------|---------|
| Sentiment analysis | `AI_COMPLETE('claude-3-5-sonnet', 'What is the sentiment...')` | `AI_SENTIMENT('Great product!')` | 60-80% fewer tokens, optimized model |
| Classification | `AI_COMPLETE('llama3.1-70b', 'Classify this as...')` | `AI_CLASSIFY('text', ['cat_a', 'cat_b'])` | Purpose-built, lower credit rate |
| Entity extraction | `AI_COMPLETE('mistral-large2', 'Extract the name...')` | `AI_EXTRACT('text', ['name', 'date'])` | Structured output, no wasted tokens |
| Yes/No filtering | `AI_COMPLETE(model, 'Is this about finance? Answer yes or no')` | `AI_FILTER('text', 'Is this about finance?')` | Returns boolean directly, minimal tokens |

**Rule of thumb**: Use task-specific AI functions first. Fall back to
AI_COMPLETE only when you need free-form generation.

### 3.2 Optimize prompts

Every token in your prompt costs money. Reduce prompt size without
sacrificing quality:

```sql
-- EXPENSIVE: Verbose prompt with redundant instructions
SELECT AI_COMPLETE('mistral-large2',
    'You are an expert data analyst. I need you to carefully analyze the
     following text and provide a detailed summary. Please make sure to
     include all key points and be thorough in your analysis. Here is
     the text to analyze: ' || long_text_column
) FROM my_table;

-- OPTIMIZED: Concise prompt, same result
SELECT AI_COMPLETE('mistral-large2',
    'Summarize key points: ' || long_text_column
) FROM my_table;
```

**Prompt optimization checklist:**
- Remove filler phrases ("I need you to", "Please make sure to")
- Pre-filter input data before sending to the model
- Truncate irrelevant text before calling AI functions
- Use system prompts for repeated instructions (avoids per-row duplication)

### 3.3 Batch processing vs. interactive

Cortex AI Functions are optimized for batch throughput. Running
AI functions over entire tables is more cost-efficient per token than
one-off interactive calls:

```sql
-- BATCH: Process all rows in one query (efficient)
SELECT
    id,
    AI_SENTIMENT(review_text) AS sentiment
FROM product_reviews
WHERE review_date >= '2026-01-01';

-- INTERACTIVE: One row at a time (inefficient, higher overhead)
SELECT AI_SENTIMENT('This product is great');
```

### 3.4 Cortex Guard cost awareness

Cortex Guard (safety filtering) adds token processing overhead on top of
the base AI_COMPLETE call. Only enable it when safety filtering is
required:

```sql
-- WITH guard (extra cost for safety filtering)
SELECT AI_COMPLETE('mistral-large2',
    'Generate a response',
    {'guard': {'enabled': TRUE}}
);

-- WITHOUT guard (lower cost for internal/trusted use cases)
SELECT AI_COMPLETE('mistral-large2', 'Generate a response');
```

### 3.5 Agent budget controls

When building Cortex Agents, set explicit token and time budgets in the
agent specification to prevent runaway costs:

```json
"orchestration": {
    "budget": {
        "seconds": 120,
        "tokens": 50000
    }
}
```

A lower token budget forces the agent to be concise and limits the
maximum cost per invocation.

---

## 4. How to identify shadow waste in Snowflake AI

Shadow waste refers to AI credit consumption that delivers little or no
business value. It is often invisible because AI costs are serverless and
don't show up in warehouse monitoring.

### 4.1 Find your top AI spenders

```sql
-- Top users by AI credit consumption (last 30 days)
SELECT
    u.NAME AS user_name,
    SUM(h.TOKEN_CREDITS) AS total_credits,
    COUNT(*) AS total_calls,
    SUM(h.TOKENS) AS total_tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY h
JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY u.NAME
ORDER BY total_credits DESC
LIMIT 20;
```

### 4.2 Detect expensive models used for simple tasks

Look for high-cost models being used where cheaper alternatives exist:

```sql
-- Find AI_COMPLETE calls that could use task-specific functions
SELECT
    FUNCTION_NAME,
    MODEL_NAME,
    COUNT(*) AS call_count,
    SUM(CREDITS) AS total_credits,
    AVG(CREDITS) AS avg_credits_per_call
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY FUNCTION_NAME, MODEL_NAME
ORDER BY total_credits DESC;
```

**Warning signs:**
- High call counts on AI_COMPLETE where AI_CLASSIFY or AI_SENTIMENT
  would suffice
- Large models (claude-3-5-sonnet, llama3.1-70b) used for simple
  extraction tasks

### 4.3 Find duplicate or redundant calls

```sql
-- Queries making the same AI call repeatedly (cache misses)
SELECT
    QUERY_TAG,
    FUNCTION_NAME,
    COUNT(*) AS repetitions,
    SUM(TOKEN_CREDITS) AS wasted_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY QUERY_TAG, FUNCTION_NAME
HAVING COUNT(*) > 10
ORDER BY wasted_credits DESC;
```

### 4.4 Identify idle Cortex Search services

Cortex Search services incur indexing credits even when nobody queries
them:

```sql
-- Search services consuming credits but with low query volume
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

If a service shows high `INDEXING` credits but near-zero `QUERY` credits,
it is shadow waste.

### 4.5 Track AI cost trends for anomaly detection

```sql
-- Daily AI cost trend to spot spikes
SELECT
    USAGE_DATE::DATE AS day,
    SERVICE_TYPE,
    SUM(CREDITS_BILLED) AS daily_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE SERVICE_TYPE ILIKE '%AI%'
  AND USAGE_DATE >= DATEADD('day', -90, CURRENT_DATE())
GROUP BY day, SERVICE_TYPE
ORDER BY day DESC;
```

Sudden spikes often indicate:
- A new pipeline running AI functions on a large table without testing
- A developer experimenting with large models in production
- An agent loop making excessive tool calls

### 4.6 Shadow waste checklist

| Waste pattern | How to detect | Typical savings |
|--------------|--------------|-----------------|
| Over-sized models | AI_COMPLETE with large models for simple tasks | 40-70% |
| Redundant calls | Same prompt/data processed repeatedly | 50-90% |
| Idle Search services | Indexing credits with no queries | 100% of idle cost |
| Verbose prompts | High token counts relative to output value | 20-40% |
| Uncontrolled agents | No token budget, excessive tool loops | 30-60% |
| Dev/test in production | High AI spend from non-production roles | Variable |

---

## 5. Cost controls to address shadow waste

### 5.1 Budgets (primary control for AI costs)

Budgets are the primary mechanism for controlling AI serverless costs.
Resource monitors do **not** work for AI services -- they only cover
warehouses.

**Account budget** (monitors all credit usage including AI_SERVICES):

```sql
-- Activate the account budget with a monthly limit
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!ACTIVATE();
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_SPENDING_LIMIT(5000);
```

**Custom budget for AI workloads:**

```sql
-- Create a custom budget scoped to AI-heavy objects
CREATE SNOWFLAKE.CORE.BUDGET IF NOT EXISTS DEMO_DB.AGENTS.AI_COST_BUDGET();

-- Set a monthly spending limit
CALL DEMO_DB.AGENTS.AI_COST_BUDGET!SET_SPENDING_LIMIT(500);

-- Add notification emails
CALL DEMO_DB.AGENTS.AI_COST_BUDGET!SET_EMAIL_NOTIFICATIONS(
    'admin@company.com', 'finops@company.com'
);
```

**Budget actions** (auto-remediate when thresholds are hit):

Budgets support user-defined stored procedure actions that trigger
when spending reaches a threshold. For example, suspend warehouses or
send alerts when 80% of the budget is consumed.

**Low-latency budgets** (1-hour refresh):

By default, budgets refresh every 6.5 hours. For tighter control,
enable low-latency refresh at the cost of ~12x higher budget compute:

```sql
CALL my_budget!SET_REFRESH_TIER('LOW_LATENCY');
```

### 5.2 Role-based access control (RBAC)

Restrict who can call AI functions:

```sql
-- Remove AI access from all users by default
REVOKE USE AI FUNCTIONS ON ACCOUNT FROM ROLE PUBLIC;

-- Grant only to approved roles
GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE DATA_SCIENCE_ROLE;
GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE ANALYST_ROLE;

-- Also revoke the CORTEX_USER database role from PUBLIC
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE PUBLIC;
```

This prevents unauthorized or accidental AI function usage across the
account.

### 5.3 Agent orchestration budgets

Embed cost limits directly in agent specifications:

```json
"orchestration": {
    "budget": {
        "seconds": 120,
        "tokens": 50000
    }
}
```

And set query timeouts on tool execution:

```json
"tool_resources": {
    "my_tool": {
        "type": "procedure",
        "identifier": "DB.SCHEMA.MY_PROC",
        "execution_environment": {
            "type": "warehouse",
            "warehouse": "COMPUTE_WH",
            "query_timeout": 60
        }
    }
}
```

### 5.4 Pre-flight token estimation

Build guardrails into your pipelines:

```sql
-- Only process rows where token count is under a threshold
SELECT
    id,
    text_column,
    SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', text_column) AS est_tokens
FROM my_table
WHERE SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('ai_classify', text_column) < 10000;
```

This prevents accidentally sending a 500-page document through an AI
function.

### 5.5 Query tagging for cost attribution

Tag AI queries to enable downstream cost allocation:

```sql
-- Tag queries by department or project
ALTER SESSION SET QUERY_TAG = 'department=finance,project=risk_model';
SELECT AI_SENTIMENT(review) FROM customer_feedback;
ALTER SESSION UNSET QUERY_TAG;
```

Then analyze cost by tag:

```sql
SELECT
    QUERY_TAG,
    SUM(TOKEN_CREDITS) AS total_credits,
    COUNT(*) AS call_count
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND QUERY_TAG IS NOT NULL
GROUP BY QUERY_TAG
ORDER BY total_credits DESC;
```

### 5.6 Cost control summary

| Control | Scope | Prevents |
|---------|-------|----------|
| **Account budget** | Entire account | Overall spend overruns |
| **Custom budget** | Specific objects/groups | Department-level overruns |
| **Budget actions** | Threshold-triggered | Runaway costs (auto-suspend) |
| **RBAC** | Per role | Unauthorized AI usage |
| **Agent token budget** | Per agent invocation | Agent loop explosions |
| **AI_COUNT_TOKENS** | Per query | Oversized prompts |
| **Query tagging** | Per session/query | Unattributed spend |
| **Low-latency budget** | Per budget | Delayed detection (6.5h to 1h) |

---

## 6. What's new in Snowflake for AI cost control

### 6.1 Budgets with AI_SERVICES support

Snowflake Budgets now natively track **AI_SERVICES** as a supported
service type. This means both account budgets and custom budgets can
monitor Cortex AI spending alongside warehouse, serverless task, and
other compute costs. Previously, AI costs were only visible through
METERING_DAILY_HISTORY.

### 6.2 Custom budget actions

Budgets can now trigger **user-defined stored procedures** when spending
reaches a threshold. This enables automated remediation:

- Suspend warehouses when AI spend hits 80%
- Send Slack/Teams notifications via webhook
- Log cost events to an audit table
- Disable specific AI pipelines

Budget actions can also fire at **cycle start** (beginning of each
month) to reset configurations.

### 6.3 Low-latency budget refresh

The budget refresh interval can be reduced from the default 6.5 hours to
**1 hour** using `SET_REFRESH_TIER('LOW_LATENCY')`. This gives near
real-time cost visibility for AI workloads, though at ~12x the budget
compute cost.

### 6.4 Granular token tracking

`CORTEX_AISQL_USAGE_HISTORY` now includes:

- `TOKENS_GRANULAR` (OBJECT): Breakdown of input, output, and reasoning
  tokens per call
- `TOKEN_CREDITS_GRANULAR` (OBJECT): Corresponding credit breakdown

This enables precise attribution of whether costs are driven by prompt
size (input), response length (output), or chain-of-thought reasoning.

### 6.5 Expanded AI functions with cost-efficient alternatives

Snowflake has introduced purpose-built AI functions that are more
cost-effective than general-purpose AI_COMPLETE for specific tasks:

| New function | Replaces | Benefit |
|-------------|----------|---------|
| `AI_CLASSIFY` | AI_COMPLETE with classification prompts | Lower token usage, structured output |
| `AI_FILTER` | AI_COMPLETE with yes/no prompts | Returns boolean, minimal tokens |
| `AI_AGG` | Multiple AI_COMPLETE calls + manual aggregation | No context window limit, single call |
| `AI_SUMMARIZE_AGG` | Multiple SUMMARIZE calls | Aggregates across rows efficiently |
| `AI_SIMILARITY` | Manual embedding + distance calculation | Single function, optimized compute |
| `AI_REDACT` | AI_COMPLETE with PII extraction prompts | Purpose-built for compliance |
| `AI_TRANSCRIBE` | External transcription services | In-platform, no data egress |

### 6.6 Cortex Agent budget controls

Cortex Agents support embedded budget constraints in their specification:

- **Token budget**: Maximum tokens per agent invocation
- **Time budget**: Maximum seconds per invocation
- **Query timeout**: Per-tool execution timeout

These prevent runaway agent loops from consuming unlimited credits.

### 6.7 Provisioned throughput

For high-volume, predictable AI workloads, Snowflake offers
**provisioned throughput** -- dedicated AI compute capacity at a fixed
credit rate. This provides:

- Predictable pricing regardless of token volume
- Guaranteed throughput for latency-sensitive applications
- Cost savings at scale vs. per-token pricing

Provisioned throughput is suitable for production pipelines with
consistent, high-volume AI function calls.

### 6.8 Model lifecycle and deprecation policy

Snowflake now follows a formal model lifecycle:

```
Private Preview --> Public Preview --> GA --> Legacy --> End of Life
```

- **GA models**: At least 60 days notice before deprecation
- **Preview models**: May change or be deprecated with shorter notice

This matters for FinOps because model deprecation forces migration,
and replacement models may have different credit rates. Monitor
Snowflake's Behavior Change Releases (BCRs) for model changes.

---

## Appendix: FinOps maturity levels for Snowflake AI

| Level | Characteristics | Actions |
|-------|----------------|---------|
| **Crawl** | No visibility into AI costs; no budgets set | Activate account budget; query ACCOUNT_USAGE views monthly |
| **Walk** | Basic budgets in place; cost reviewed weekly | Add custom budgets per team; implement RBAC for AI functions; tag queries |
| **Run** | Automated alerts and actions; continuous optimization | Low-latency budgets; automated budget actions; token pre-flight checks; model right-sizing reviews |

---

## Quick reference: monitoring queries

```sql
-- 1. Total AI spend (last 30 days)
CALL DEMO_DB.AGENTS.GET_AI_COST_USAGE('summary', 30::FLOAT);

-- 2. Which functions cost the most?
CALL DEMO_DB.AGENTS.GET_AI_COST_USAGE('ai_functions_by_model', 30::FLOAT);

-- 3. Daily trend for anomaly detection
CALL DEMO_DB.AGENTS.GET_AI_COST_USAGE('daily_trend', 90::FLOAT);

-- 4. Token count before expensive call
SELECT SNOWFLAKE.CORTEX.AI_COUNT_TOKENS('mistral-large2', my_text)
FROM my_table LIMIT 10;

-- 5. Check budget status
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!GET_LINKED_RESOURCES();
```
