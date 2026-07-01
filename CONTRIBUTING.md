# Contributing to FinOps for Snowflake AI

We welcome contributions that help the community better manage Snowflake AI costs. This document explains how to contribute governance strategies, optimization queries, training modules, and skill file extensions.

---

## Ways to Contribute

### 1. Add Governance Strategies

Add new cost control strategies to `SKILL.md` and optionally to `sql/governance/`:

1. Add a `### Strategy N:` section in `SKILL.md` under **Governance Strategies**
2. Include the SQL or configuration needed
3. Explain when to use it and expected outcome
4. If the SQL is complex, also add it to `sql/governance/` as a standalone file

### 2. Add Shadow Waste Detection Patterns

1. Add a `### Waste N:` section in `SKILL.md` under **Shadow Waste Detection**
2. Include the detection query targeting `SNOWFLAKE.ACCOUNT_USAGE` views
3. Document the fix/workaround and typical savings percentage
4. Add the query to `sql/governance/shadow-waste-detection.sql`

### 3. Add Optimization Queries

Add new queries to `sql/optimization/`:

- Model rightsizing strategies → `model-rightsizing.sql`
- Prompt optimization patterns → `prompt-optimization.sql`
- Service cleanup patterns → `idle-services.sql`
- Or create a new file for a new optimization category

### 4. Improve the Training

- Add new modules to `training/modules/` following the existing HTML template
- Update `training/index.html` agenda table
- Add corresponding SQL in `training/sql/`
- Update the progress bar in `training/js/main.js`

### 5. Improve the Dashboard

- Add new tabs or metrics to `dashboard/streamlit_app.py`
- Add new report types to the stored procedure
- Create alternative dashboards (Grafana, Tableau connectors, etc.)

---

## How to Submit

1. Fork this repository
2. Create a feature branch: `git checkout -b add-budget-action-strategy`
3. Make your changes
4. Test your SQL queries against your own Snowflake account
5. Submit a Pull Request with:
   - Description of what you added
   - Which files were modified
   - Expected savings or governance improvement

---

## Code Style

### SQL Files

- Use `SNOWFLAKE.ACCOUNT_USAGE` fully qualified view names
- Include header comments with:
  - WHEN TO RUN (frequency)
  - WHAT IT SHOWS (description)
  - SOURCE (which view)
- Use `DATEADD('day', -N, CURRENT_TIMESTAMP())` for time filtering
- Round credit values: `ROUND(credits, 4)` for totals, `ROUND(credits, 6)` for per-call
- Include dollar estimates at `$3/credit` (note this is approximate)

### SKILL.md

- Each strategy or pattern gets its own `###` section
- Include runnable SQL in fenced code blocks
- Keep explanations concise — practitioners reading this want to act, not read essays
- Include a table when comparing approaches

### Training HTML

- Follow the existing module template structure
- Use CSS classes from `css/theme.css` (no inline styles except where necessary)
- Include copy-to-clipboard buttons on all code blocks
- Add timing badges and section letters

---

## Testing Your Contributions

Before submitting:

1. **SQL queries**: Run against your own Snowflake account and verify results
2. **Training modules**: Open in a browser and verify navigation links work
3. **SKILL.md changes**: Ensure the skill file remains well-structured and parseable
4. **Dashboard changes**: Test locally with `streamlit run streamlit_app.py`

---

## What We're Looking For

High-value contributions include:

- New waste patterns discovered in production environments
- Budget automation strategies (stored procedure actions)
- Integration with alerting systems (Slack, Teams, PagerDuty)
- Multi-account or organization-level governance queries
- Cost allocation and chargeback frameworks
- Provisioned throughput optimization strategies
- Cortex Agent cost guardrails beyond token budgets
- Data quality checks that prevent wasted AI calls on bad data

---

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
