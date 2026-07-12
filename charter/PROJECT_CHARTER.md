# Project Charter — Merchant Settlement Reconciliation & Cash Visibility Platform

## 1. Fictional client and operating model

**Client:** Meridian Pay — a fictional SMB-focused payment facilitator (PayFac). Meridian underwrites and onboards small and mid-size merchants (retail, e-commerce, food service, professional services), processes their card and ACH transactions through a sponsor bank, and settles net proceeds to merchant bank accounts on a daily cycle.

**Operating model:**
- Merchants submit transactions throughout the day via Meridian's payment gateway.
- Meridian's processor batches and nets transactions per merchant into a **settlement batch** at end of day (gross volume − interchange/network fees − Meridian's processing fee − reserve holds +/− returns and adjustments).
- The sponsor bank moves funds via ACH to merchant accounts, typically landing **T+1 or T+2** business days after the batch date.
- Meridian's treasury/finance team must confirm that **expected settlement** (what the ledger says merchants are owed) matches **actual cash movement** (what the bank posts), every business day, for ~thousands of merchants.
- Today this reconciliation is spreadsheet-driven, reactive, and only escalates once a merchant complains about a missing payout — there is no proactive break detection, aging, or cash-at-risk visibility.

This project builds the data platform that gives Meridian's finance and treasury organization same-day visibility into settlement health, without relying on manual matching.

## 2. Stakeholder map

| Stakeholder | Role | What they need from this platform |
|---|---|---|
| CFO (executive sponsor) | Owns cash forecasting and board reporting | Daily, trustworthy cash position; no surprises on funding shortfalls |
| VP Treasury | Manages funding lines, cost of capital | Cash-at-risk and funding cost estimate to size credit facility draws |
| Controller / Accounting | Owns month-end close and GL accuracy | Auditable tie-out from bank cash to ledger; break aging for close adjustments |
| Head of Merchant Operations | Owns merchant relationships, payout disputes | Fast, root-caused break triage so merchant-facing teams aren't guessing |
| Risk & Compliance | Owns reserve policy, chargeback exposure | Visibility into reserve holds/releases and unusual break patterns |
| Data/Analytics Engineering | Builds and operates the platform | Clear KPI contract, testable pipelines, low on-call burden |
| BI consumers (finance analysts) | Self-serve reporting | A trustworthy Gold layer / semantic model they don't have to second-guess |

## 3. Pain points (status quo, pre-platform)

1. Reconciliation is manual (spreadsheets), performed 2–3 days after the fact — breaks are found late.
2. No standard definition of a "break" — different analysts apply different tolerance rules inconsistently.
3. No aging or severity model — a $50 break and a $50,000 break get the same triage priority.
4. Cash forecasting to the CFO is a gut-feel estimate, not a number traceable to source data.
5. No visibility into the **cost** of unresolved breaks (capital tied up, potential funding-line draws).
6. Audit trail from a reported number back to source transactions doesn't exist — every audit request is a fire drill.

## 4. Scope boundaries

**In scope:**
- Daily batch reconciliation (not real-time/streaming — settlement reconciles against a bank statement that posts once a day, so there is no real-time version of this problem).
- Synthetic operational data (transactions, settlement batches, fees, reserves, returns, bank postings) generated deterministically, informed by real macro/reference data (FRPS, CBP, CPI, FRED) for realism.
- Production-readiness controls: data quality gates, RBAC design, IaC, CI/CD, observability.

**Out of scope:**
- Real confidential processor/bank data feeds (everything is synthetic, by design, to keep the project fully self-contained and shareable).
- Full enterprise IAM federation (SSO/SCIM) — RBAC is modeled at the Databricks Unity Catalog level only.
- True real-time stream processing — this is a batch reconciliation platform by design (see Scope boundaries above).

## 5. Interview narratives

### 2-minute version
"I built a batch reconciliation platform for a fictional SMB payment processor — think of it as the finance-side discipline of knowing exactly where every dollar is, every day. Every day, a payment processor owes thousands of merchants money, and the bank doesn't always pay out exactly what the ledger expects, on exactly the day expected. I generated realistic synthetic settlement data — transactions, batches, fees, reserve holds, bank postings — with deliberately injected timing breaks like weekend lag and reserve delays, then built a Databricks lakehouse with a medallion architecture and a reconciliation engine that matches expected settlement to actual cash within amount and date tolerances. The Gold layer surfaces daily cash position, unresolved breaks, break aging, and a funding-cost estimate — the exact numbers a CFO or treasurer would need. I treated it like a real production system: dbt-style tested models, data quality gates that block bad data from reaching the Gold layer, Terraform-provisioned infrastructure, CI/CD with staged deploys, and a documented RBAC model separating treasury, finance, and engineering access."

### 5-minute version
Extends the above with:
- **Why this design:** reconciliation is a universal fintech problem — anyone processing third-party payouts (marketplaces, payment facilitators, gig platforms) has this exact break-detection and cash-visibility need. I chose batch over streaming here deliberately, because settlement reconciliation is inherently a T+1/T+2 problem — you're reconciling against a bank statement that posts once a day, not a real-time event stream. Picking the architecture that fits the problem, rather than defaulting to streaming everywhere, is itself the point.
- **Design tradeoffs:** amount-and-date-window tolerance matching versus exact-match — exact match sounds cleaner but produces false breaks from routine timing noise (weekend ACH lag, bank cut-off times), which would bury real breaks in noise. I made the tolerance policy a first-class, documented, testable contract rather than a magic number buried in a query.
- **Production readiness outcomes:** what's actually gated in CI (dbt tests, Terraform plan, data quality thresholds), what the RBAC matrix enforces, what the incident runbook covers (late data, failed tests, SLA breach).
- **Next-step roadmap:** what I'd add for a real deployment — real bank file formats (BAI2/NACHA parsing), multi-currency support, automated break-resolution suggestions using historical root-cause patterns.

## 6. Related documents

- [KPI Contract](../docs/kpi_contract.md)
- [Non-Functional Targets](../docs/non_functional_targets.md)
- [Source Contracts](../docs/source_contracts/) (FRPS, CBP, CPI, FRED)
