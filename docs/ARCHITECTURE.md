# Architecture

This document explains how the components of FinOps for Snowflake AI fit together.

---

## System Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        Snowflake Account                                   │
│                                                                            │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────────────┐   │
│  │ Cortex AI SQL  │  │ Cortex AI Fns  │  │ Cortex Search / Doc AI     │   │
│  │ (Agents,       │  │ (AI_COMPLETE,  │  │ (Indexing + Query credits) │   │
│  │  Analyst,      │  │  AI_SENTIMENT, │  │                            │   │
│  │  Intelligence) │  │  AI_CLASSIFY)  │  │                            │   │
│  └───────┬────────┘  └───────┬────────┘  └──────────────┬─────────────┘   │
│          │                   │                           │                 │
│          ▼                   ▼                           ▼                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │              SNOWFLAKE.ACCOUNT_USAGE (45-min latency)               │   │
│  │                                                                     │   │
│  │  • CORTEX_AISQL_USAGE_HISTORY        → TOKEN_CREDITS               │   │
│  │  • CORTEX_AI_FUNCTIONS_USAGE_HISTORY  → CREDITS                    │   │
│  │  • CORTEX_SEARCH_DAILY_USAGE_HISTORY  → CREDITS                    │   │
│  │  • DOCUMENT_AI_USAGE_HISTORY          → CREDITS_USED               │   │
│  │  • METERING_DAILY_HISTORY             → CREDITS_BILLED             │   │
│  │  • CORTEX_CODE_CLI_USAGE_HISTORY      → total_credits              │   │
│  │  • CORTEX_CODE_SNOWSIGHT_USAGE_HISTORY→ total_credits              │   │
│  └───────────────────────────┬─────────────────────────────────────────┘   │
│                              │                                             │
└──────────────────────────────┼─────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                     FinOps for Snowflake AI Toolkit                           │
│                                                                              │
│  ┌────────────────┐  ┌──────────────────┐  ┌────────────────────────────┐   │
│  │   SKILL.md     │  │   SQL Library    │  │   Streamlit Dashboard      │   │
│  │                │  │                  │  │                            │   │
│  │  Cortex Code   │  │  sql/governance/ │  │  dashboard/                │   │
│  │  AI Assistant  │  │  sql/tracking/   │  │  streamlit_app.py          │   │
│  │  FinOps Advisor│  │  sql/optimization│  │                            │   │
│  └────────────────┘  └──────────────────┘  └────────────────────────────┘   │
│                                                                              │
│  ┌────────────────┐  ┌──────────────────┐                                   │
│  │   Training     │  │   Docs           │                                   │
│  │                │  │                  │                                   │
│  │  9 HTML modules│  │  FinOps Guide    │                                   │
│  │  + SQL scripts │  │  Shadow Waste    │                                   │
│  └────────────────┘  └──────────────────┘                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

1. **AI services execute** — Users call Cortex AI functions, agents run, Search services index
2. **Usage recorded** — Snowflake records token/credit consumption in ACCOUNT_USAGE views (~45 min delay)
3. **Queries monitor** — SQL scripts in `sql/` query these views to surface costs
4. **Dashboard visualizes** — Streamlit app provides ongoing KPI tracking
5. **Skill advises** — SKILL.md enables Cortex Code to provide AI-assisted governance recommendations

---

## Component Details

### SQL Library (`sql/`)

Organized by function:

| Directory | Purpose | Frequency |
|-----------|---------|-----------|
| `sql/setup/` | Bootstrap environment (DB, warehouse, role, grants) | One-time |
| `sql/governance/` | Shadow waste detection, cost attribution, anomaly alerts | Weekly/Monthly |
| `sql/tracking/` | Core usage monitoring (by function, model, user, time) | Daily/Weekly |
| `sql/optimization/` | Model rightsizing, prompt optimization, idle service cleanup | Monthly |

### SKILL.md

A Cortex Code skill file that encodes all governance knowledge. When loaded into Cortex Code, it enables natural language queries like:

- "What are my shadow waste patterns?"
- "Generate a cost attribution report"
- "Which models should I downgrade?"

The skill is designed for community extension — new strategies and patterns can be added by following the documented format.

### Training (`training/`)

A 9-module, 90-minute hands-on curriculum:

```
Module 01: AI Token Economy (Concept)
Module 02: Cortex AI Capabilities (Concept)
Module 03: Environment Setup (Setup)
Module 04: Cortex Code Setup (Setup)
Module 05: AI SQL Hands-On (Lab)
Module 06: Token Usage Tracking (Lab)
Module 07: Spend Controls (Lab)
Module 08: Streamlit Dashboard (Lab)
Module 09: Closing Note (Wrap-up)
```

Static HTML — open `training/index.html` in any browser. No build step required.

### Dashboard (`dashboard/`)

Two deployment options:

1. **Streamlit in Snowflake** — Use `training/sql/07-streamlit-app.py` (queries ACCOUNT_USAGE directly via Snowpark session)
2. **Local Streamlit** — Use `dashboard/streamlit_app.py` (calls a stored procedure via Snowflake connector)

### Cortex Agent Example (`examples/cortex-agent/`)

A ready-to-deploy Cortex Agent specification that uses a stored procedure to answer AI cost questions in natural language.

---

## Key Design Decisions

1. **Static training** — No build tools, no server. HTML files with CSS/JS from CDN or local. Maximum portability.
2. **SQL-first** — All governance logic is in SQL. No Python dependencies for core monitoring.
3. **Skill-based extension** — SKILL.md is the single source of governance knowledge, designed for community contribution.
4. **Two-layer separation** — Training teaches concepts; SQL library provides production queries. They reference each other but work independently.
5. **Account_usage dependency** — All queries target `SNOWFLAKE.ACCOUNT_USAGE` views, which require ACCOUNTADMIN and have ~45 min latency. The architecture acknowledges this constraint and provides `INFORMATION_SCHEMA` alternatives where needed.

---

## Extension Points

| What to extend | Where to add | How |
|---------------|-------------|-----|
| New waste pattern | `SKILL.md` + `sql/governance/shadow-waste-detection.sql` | Add `### Waste N:` section |
| New governance strategy | `SKILL.md` | Add `### Strategy N:` section |
| New optimization query | `sql/optimization/` | New file or append to existing |
| New training module | `training/modules/` | Follow HTML template pattern |
| New dashboard view | `dashboard/streamlit_app.py` | Add new tab/section |
| New agent capability | `examples/cortex-agent/` | Extend stored procedure |
