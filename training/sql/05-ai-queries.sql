-- ═══════════════════════════════════════════════════════════════════════════
-- AI for FinOps Training - Module 05: AI SQL Hands-On Exercises
-- FinOps for Snowflake AI · Snowflake AI FinOps Training
-- ═══════════════════════════════════════════════════════════════════════════
--
-- PREREQUISITES: Complete Module 04 setup first
-- USE CONTEXT:   cortex_lab.ai_workshop schema, cortex_wh warehouse
-- KEY HABIT:     After EVERY exercise, check Module 06 tracking queries
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE cortex_analyst;
USE WAREHOUSE cortex_wh;
USE SCHEMA cortex_lab.ai_workshop;

-- ═══════════════════════════════════════════════════════════════════════════
-- EXERCISE 1: Sentiment Analysis (Budget Function)
-- ═══════════════════════════════════════════════════════════════════════════
-- Function:      AI_SENTIMENT() [new] or SNOWFLAKE.CORTEX.SENTIMENT() [legacy]
-- Cost tier:     LOWEST - uses Snowflake-optimized internal model
-- Expected rows: 20
-- Cost check:    Run Module 06 Query 1 after this exercise
-- ─────────────────────────────────────────────────────────────────────────────

-- Approach A: New AI_SENTIMENT (returns OBJECT with category strings)
SELECT
    customer_id,
    customer_name,
    LEFT(feedback_text, 80)                     AS feedback_preview,
    AI_SENTIMENT(feedback_text)                 AS sentiment_result,
    AI_SENTIMENT(
        feedback_text
    ):categories[0]:sentiment::VARCHAR          AS sentiment_label
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 20;

-- Approach B: Legacy SENTIMENT (returns numeric score -1 to 1)
SELECT
    customer_id,
    customer_name,
    LEFT(feedback_text, 80)                     AS feedback_preview,
    SNOWFLAKE.CORTEX.SENTIMENT(
        feedback_text
    )                                           AS sentiment_score,
    CASE
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(feedback_text) > 0.3
             THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(feedback_text) < -0.3
             THEN 'Negative'
        ELSE 'Neutral'
    END                                         AS sentiment_label
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 20;

-- ★ Cost Check: Record credits used before next exercise.
-- NOTE: AI_SENTIMENT returns {"categories":[{"name":"overall","sentiment":"positive"}]}
-- Legacy SENTIMENT returns a float -1 to 1. Both are highly cost-efficient.


-- ═══════════════════════════════════════════════════════════════════════════
-- EXERCISE 2: Classification (Budget Function)
-- ═══════════════════════════════════════════════════════════════════════════
-- Function:      AI_CLASSIFY()
-- Cost tier:     LOW-MEDIUM - cheaper than AI_COMPLETE() for classification
-- Expected rows: 20
-- Cost check:    Compare to Exercise 1 - how did the cost differ?
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    customer_id,
    market_segment,
    LEFT(feedback_text, 80)                     AS feedback_preview,
    AI_CLASSIFY(
        feedback_text,
        ['billing',
         'technical_issue',
         'general_inquiry',
         'complaint',
         'praise']
    ):labels[0]::VARCHAR                        AS category
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 20;

-- ★ Cost Check: How did this compare to Exercise 1?
-- TIP: AI_CLASSIFY() is significantly cheaper than using AI_COMPLETE() with
-- a prompt asking for classification. Always use the specialized function
-- when available.


-- ═══════════════════════════════════════════════════════════════════════════
-- EXERCISE 3: Text Extraction (Medium Function)
-- ═══════════════════════════════════════════════════════════════════════════
-- Function:      AI_COMPLETE() with mistral-7b (budget model)
-- Cost tier:     MEDIUM - general LLM, but using budget-tier model
-- Expected rows: 10
-- Cost check:    Compare AI_COMPLETE() cost vs AI_CLASSIFY()
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    customer_id,
    feedback_text,
    AI_COMPLETE(
        'mistral-7b',
        CONCAT(
            'Extract the main complaint topic from this customer ',
            'feedback in 3 words or less. ',
            'Reply with only the topic, nothing else. ',
            'Feedback: ', feedback_text
        )
    )                                           AS extracted_topic
FROM cortex_lab.ai_workshop.customer_feedback
WHERE LENGTH(feedback_text) > 50
LIMIT 10;

-- ★ Cost Check: Compare AI_COMPLETE() cost vs AI_CLASSIFY().
-- WARNING: We use mistral-7b - the budget tier model. For a simple 3-word
-- extraction task, a premium model would cost 10–20× more with no quality gain.


-- ═══════════════════════════════════════════════════════════════════════════
-- EXERCISE 4: Model Cost Comparison (FinOps Exercise)
-- ═══════════════════════════════════════════════════════════════════════════
-- Context:       Same prompt, three models, three cost points
-- Cost tier:     VARIES - this IS the lesson
-- Expected rows: 3 per query
-- Cost check:    This is the core FinOps exercise - fill in the table below
-- ─────────────────────────────────────────────────────────────────────────────

-- Run each query separately and note cost in token tracking between runs.

-- Model A: Budget Tier (mistral-7b)
SELECT 
    'mistral-7b' AS model_used,
    customer_id,
    AI_COMPLETE(
        'mistral-7b',
        CONCAT('Summarize in one sentence: ', feedback_text)
    ) AS summary_budget
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 3;

-- ★ Record credits used: _______________


-- Model B: Standard Tier (llama3-70b)
SELECT 
    'llama3-70b' AS model_used,
    customer_id,
    AI_COMPLETE(
        'llama3-70b',
        CONCAT('Summarize in one sentence: ', feedback_text)
    ) AS summary_standard
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 3;

-- ★ Record credits used: _______________


-- Model C: Premium Tier (claude-4-sonnet)
SELECT 
    'claude-4-sonnet' AS model_used,
    customer_id,
    AI_COMPLETE(
        'claude-4-sonnet',
        CONCAT('Summarize in one sentence: ', feedback_text)
    ) AS summary_premium
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 3;

-- ★ Record credits used: _______________


-- ─────────────────────────────────────────────────────────────────────────────
-- EXERCISE 4 COMPARISON TABLE (fill in after running all three)
-- ─────────────────────────────────────────────────────────────────────────────
-- Model              | Quality (subjective) | Credits Used | Cost Index
-- ──────────────────────────────────────────────────────────────────────────
-- mistral-7b         | [observe]            | [from tracking] | 1×
-- llama3-70b         | [observe]            | [from tracking] | ?×
-- claude-4-sonnet   | [observe]            | [from tracking] | ?×
-- ─────────────────────────────────────────────────────────────────────────────

-- KEY INSIGHT: This comparison is the single most important FinOps exercise
-- in this training. The right model choice for your use case can reduce AI
-- spend by 80–90% with equivalent output quality.


-- ═══════════════════════════════════════════════════════════════════════════
-- EXERCISE 5: Summarization at Scale Simulation
-- ═══════════════════════════════════════════════════════════════════════════
-- Context:       Understand cost before running at scale
-- Pattern:       Test small → Measure → Project → Decide
-- Expected rows: 5
-- Cost check:    Use this to project to full dataset
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1: Run on 5 rows, check cost
SELECT
    customer_id,
    AI_COMPLETE(
        'mistral-7b',
        CONCAT('Summarize this feedback in 2 sentences: ', feedback_text)
    ) AS summary
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 5;

-- Step 2: Query cost for those 5 rows (see Module 06 Query 6)

-- Step 3: Project to full dataset
-- If 5 rows = X credits
-- 500 rows = X × 100 credits
-- 500,000 rows = X × 100,000 credits = $?

-- ★ COST PROJECTION WORKSHEET:
-- Credits for 5 rows:     _______________
-- Credits per row:        _______________
-- Projected 500 rows:     _______________
-- Projected 50,000 rows:  _______________
-- Projected 500,000 rows: _______________
-- Estimated $ at $3/credit: $____________


-- ═══════════════════════════════════════════════════════════════════════════
-- BONUS: Translation Exercise
-- ═══════════════════════════════════════════════════════════════════════════
-- Function:      AI_TRANSLATE()
-- Cost tier:     MODERATE
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    customer_id,
    LEFT(feedback_text, 100) AS original_text,
    AI_TRANSLATE(
        feedback_text,
        'en',
        'es'
    ) AS spanish_translation
FROM cortex_lab.ai_workshop.customer_feedback
LIMIT 5;


-- ═══════════════════════════════════════════════════════════════════════════
-- EXERCISE 6: Boolean Filtering with AI_FILTER
-- ═══════════════════════════════════════════════════════════════════════════
-- Function:      AI_FILTER() (can also use SNOWFLAKE.CORTEX.AI_FILTER)
-- Cost tier:     LOWER - cheaper than AI_COMPLETE() for yes/no filtering
-- Use case:      Filter rows using natural language conditions
-- NOTE:          Takes CONCAT(text, description) as single argument
-- ─────────────────────────────────────────────────────────────────────────────

-- 6A. AI_FILTER in SELECT: See boolean result for each row
SELECT
    O_ORDERKEY,
    O_ORDERPRIORITY,
    O_COMMENT,
    SNOWFLAKE.CORTEX.AI_FILTER(CONCAT(
        O_COMMENT,
        'This text mentions a delay, complaint, or urgent issue'))
FROM cortex_lab.ai_workshop.ORDERS
LIMIT 10;

-- 6B. AI_FILTER in WHERE: Return only matching rows
SELECT
    O_ORDERKEY,
    O_ORDERPRIORITY,
    O_COMMENT
FROM cortex_lab.ai_workshop.ORDERS
WHERE SNOWFLAKE.CORTEX.AI_FILTER(CONCAT(
    O_COMMENT,
    'This text mentions a delay, complaint, or urgent issue'))
LIMIT 10;

-- ★ Key Points:
-- - Can use AI_FILTER directly or SNOWFLAKE.CORTEX.AI_FILTER (fully qualified)
-- - Single argument: CONCAT(column, 'natural language condition')
-- - Returns boolean TRUE/FALSE
-- - Much cheaper than AI_COMPLETE() for simple yes/no filtering


-- ═══════════════════════════════════════════════════════════════════════════
-- KEY TAKEAWAYS FROM THIS MODULE
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. AI_SENTIMENT() is the cheapest function - use it for sentiment, not AI_COMPLETE()
-- 2. AI_CLASSIFY() is cheaper than AI_COMPLETE() for classification tasks
-- 3. AI_FILTER() is cheaper than AI_COMPLETE() for boolean yes/no filtering
-- 4. Model choice can mean 10-50x cost difference for the same task
-- 5. ALWAYS test on small sample, measure cost, then project before scaling
-- 6. The right model is the CHEAPEST one that meets your quality requirements
-- ═══════════════════════════════════════════════════════════════════════════
