# FinOps for Snowflake AI

**Understand, Track, Govern, and Optimize AI Spend on Snowflake.**

An open-source toolkit for managing the cost of Cortex AI, Cortex Search, Cortex Agents, Cortex Code, and Document AI workloads running on Snowflake. Includes a training curriculum, governance SQL, a Streamlit dashboard, shadow waste detection queries, and a Cortex Code skill file for AI-assisted cost management.

---

## Why This Exists

Snowflake AI services are serverless — there is no warehouse to watch. Credits are consumed per token, per query, or per indexing cycle. Traditional warehouse monitoring (Resource Monitors) does not cover AI costs. Without dedicated FinOps tooling:

- AI spend is invisible until the monthly bill arrives
- Shadow waste (idle Search services, oversized models, duplicate calls) drains credits silently
- No alerts fire, no queries fail — costs simply accumulate

This project gives practitioners the SQL, dashboards, skill files, and training materials to take control.

---

## What's Included

```
snowflake-ai-finops/
├── SKILL.md                    # Cortex Code skill file (governance + optimization)
├── training/                   # 9-module hands-on training (static HTML)
│   ├── index.html              # Training hub
│   ├── modules/                # AI Token Economy → Closing Note
│   └── sql/                    # Runnable SQL & Streamlit app
├── dashboard/                  # Standalone Streamlit AI cost dashboard
│   ├── streamlit_app.py        # Local or Snowflake-deployed
│   └── requirements.txt
├── sql/
│   ├── setup/                  # Environment bootstrap (DB, schema, warehouse, role)
│   ├── governance/             # Shadow waste detection, cost attribution, anomaly detection
│   ├── tracking/               # Token/credit usage monitoring queries
│   └── optimization/           # Model rightsizing, prompt optimization, idle service cleanup
├── docs/
│   ├── FINOPS_TRAINING_GUIDE.md    # Complete FinOps practitioner guide
│   ├── AI_SHADOW_WASTE_GUIDE.md    # Deep-dive on 8 shadow waste patterns
│   └── ARCHITECTURE.md             # How the pieces fit together
└── examples/
    └── cortex-agent/           # Cortex Agent spec for AI cost queries
```

---

## Quick Start

### 1. Run the Training

```bash
git clone https://github.com/<your-org>/snowflake-ai-finops.git
cd snowflake-ai-finops
open training/index.html
```

No build step, no server — modules are static HTML with copy-to-clipboard SQL blocks.

### 2. Set Up Your Environment

Run `sql/setup/environment-setup.sql` in Snowsight to create:
- `cortex_lab` database + `ai_workshop` schema
- `cortex_wh` warehouse (SMALL, 60s auto-suspend)
- Resource Monitor (warehouse compute guard)
- `cortex_analyst` role with Cortex AI access

### 3. Deploy the Dashboard

**Option A: Streamlit in Snowflake**
```sql
-- In Snowsight: Projects → Streamlit → + Streamlit App
-- Paste training/sql/07-streamlit-app.py
```

**Option B: Local Streamlit**
```bash
cd dashboard
pip install -r requirements.txt
streamlit run streamlit_app.py
```

### 4. Use the Cortex Code Skill

Copy `SKILL.md` into your Cortex Code skill directory to get AI-assisted FinOps governance. Ask Cortex Code questions like:
- "What are my top AI cost drivers this week?"
- "Find shadow waste in my Cortex Search services"
- "Generate a cost attribution report by team"

---

## Key Concepts

### Two Cost Layers

AI workloads on Snowflake have two independent cost components:

| Layer | What It Covers | Control Mechanism |
|-------|---------------|-------------------|
| Warehouse compute credits | Running the query | Resource Monitors, auto-suspend |
| AI token credits | Cortex AI function itself | Budgets, RBAC, token budgets |

### Five AI Cost Categories

| Category | ACCOUNT_USAGE View | Credit Column |
|----------|-------------------|---------------|
| Cortex AI SQL | `CORTEX_AISQL_USAGE_HISTORY` | `TOKEN_CREDITS` |
| Cortex AI Functions | `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` | `CREDITS` |
| Cortex Search | `CORTEX_SEARCH_DAILY_USAGE_HISTORY` | `CREDITS` |
| Document AI | `DOCUMENT_AI_USAGE_HISTORY` | `CREDITS_USED` |
| AI Metering | `METERING_DAILY_HISTORY` | `CREDITS_BILLED` |

### Shadow Waste Patterns

| # | Pattern | Typical Savings |
|---|---------|----------------|
| 1 | Over-sized models | 40-70% |
| 2 | Redundant/duplicate calls | 50-90% |
| 3 | Verbose prompts | 20-40% |
| 4 | Idle Cortex Search services | 100% of idle cost |
| 5 | Uncontrolled agent loops | 30-60% |
| 6 | Dev/test in production | Variable |
| 7 | Week-over-week cost anomalies | Early detection |
| 8 | Missing cost attribution | Enables chargeback |

---

## Governance SQL Library

All queries are in `sql/` and categorized by function:

- **`sql/governance/shadow-waste-detection.sql`** — Detect all 8 waste patterns
- **`sql/governance/cost-attribution.sql`** — User/team/role-based cost allocation
- **`sql/governance/anomaly-detection.sql`** — Week-over-week spend spike detection
- **`sql/tracking/token-usage.sql`** — Core credit monitoring (by function, model, hour)
- **`sql/tracking/cortex-code-usage.sql`** — Snowflake CoCo CLI + Snowsight usage
- **`sql/optimization/model-rightsizing.sql`** — Find expensive models doing simple tasks
- **`sql/optimization/prompt-optimization.sql`** — Detect rising prompt sizes
- **`sql/optimization/idle-services.sql`** — Cortex Search services burning credits with no queries

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to:
- Add new governance strategies
- Contribute optimization queries
- Extend the SKILL.md with new cost control patterns
- Improve the training modules

We welcome contributions that help the community better manage Snowflake AI costs.

---

## Prerequisites

- Snowflake account (trial or enterprise)
- ACCOUNTADMIN or SYSADMIN role access
- Web browser with Snowsight access
- Terminal access for Snowflake CoCo CLI (optional)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    FinOps for Snowflake AI                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐   ┌──────────────┐   ┌────────────────────────┐  │
│  │ SKILL.md │   │  SQL Library │   │  Streamlit Dashboard   │  │
│  │          │   │              │   │                        │  │
│  │ Cortex   │   │ Governance   │   │ KPIs + Trends +        │  │
│  │ Code     │◀──│ Tracking     │──▶│ Drill-downs            │  │
│  │ Agent    │   │ Optimization │   │                        │  │
│  └──────────┘   └──────────────┘   └────────────────────────┘  │
│       │                │                       │                │
│       └────────────────┼───────────────────────┘                │
│                        ▼                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │         SNOWFLAKE.ACCOUNT_USAGE Views                   │    │
│  │  CORTEX_AISQL_USAGE_HISTORY                             │    │
│  │  CORTEX_AI_FUNCTIONS_USAGE_HISTORY                      │    │
│  │  CORTEX_SEARCH_DAILY_USAGE_HISTORY                      │    │
│  │  DOCUMENT_AI_USAGE_HISTORY                              │    │
│  │  METERING_DAILY_HISTORY                                 │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## License

Apache 2.0 — see [LICENSE](LICENSE).

---

## Disclaimer

This project is based on personal learning and community contribution. It does not reflect any interest from any employer or from Snowflake Inc. Use at your own discretion and validate against your specific Snowflake contract and pricing.

---

## Acknowledgments

- Snowflake Documentation and Credit Consumption Table
- FinOps Foundation
- Community contributors and LinkedIn practitioners sharing AI cost insights
