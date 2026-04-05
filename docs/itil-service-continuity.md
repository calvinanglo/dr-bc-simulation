# ITIL Service Continuity Management

This document covers how ITIL 4 Service Continuity Management (SCM) is implemented in this DR project. SCM isn't just about having a DR plan — it's about having a plan that's been tested, maintained, and continuously improved based on real test results.

## what ITIL SCM actually requires

The SCM practice sits within the ITIL 4 service management practices and its purpose is to ensure that service availability can be maintained at required levels in the event of a disaster or major disruption. The key outputs are a service continuity plan, tested recovery procedures, and evidence that the plan works.

The three things that separate a real SCM implementation from a document that lives in a shared drive are: regular testing (not just annual walkthroughs), documented test results including failures, and a feedback loop that updates the plan after each test. This repo is built around that structure.

## scope and service classification

The services in scope for this DR plan are classified by their criticality and the business impact of an extended outage:

Tier 1 (database) — financial and operational data. Extended loss means real business impact. 4-hour RTO, 15-minute RPO.

Tier 2 (web tier and application) — customer-facing services. Degraded but more recoverable than database. 2-hour RTO, 1-hour RPO.

Tier 3 (network infrastructure, DNS) — everything else depends on this. 30-minute RTO, N/A RPO.

These tiers drive the order of operations in the failover runbook. Tier 3 first (get the network up), then Tier 2 (web tier can come up before the database is ready), then Tier 1 (database restore is the longest phase).

## testing types and schedule

ITIL SCM defines several testing methods ranging from low-effort/low-confidence to high-effort/high-confidence. This project uses:

**Walkthrough testing** — the DR runbook is reviewed by the team every 6 months. This catches procedures that no longer match the actual environment (e.g., IP addresses that changed, services that were renamed, VM IDs that don't exist anymore). Low effort, but catches documentation drift.

**Simulation testing** — scenarios 1 and 2 in the runbook (network failure, database-only failure) are run quarterly. These are partial failovers that test specific components without taking down everything. Faster to execute and recover from.

**Full failover testing** — scenario 3 (full site loss) is run twice a year. This is the expensive test — it takes a full day and simulates the worst case. The October and November test results in `test-results/` are from this type.

## continual improvement loop

The ITIL improvement model maps directly to how DR testing should work. After each test, the process is: where are we now (current RTO/RPO actuals), where do we want to be (targets), how do we get there (corrective actions), take action (implement fixes), check (verify in next test).

The October 2024 test is a good example of this working correctly. The database RTO miss was identified with a clear root cause. Corrective actions were implemented within a week. The November test confirmed the fix worked and the RTO came in under target. That's the loop working as intended.

What makes this a SCM practice rather than just "DR testing" is the formalization: every test produces a written result, every result produces action items with owners and due dates, and every action item gets verified in the next test cycle. The risk register is updated to reflect both resolved and outstanding issues.

## risk register (current)

| risk | likelihood | impact | mitigation | status |
|---|---|---|---|---|
| NAS mount failure silently breaking backups | low | critical | mount check in backup-validate.sh + systemd automount | mitigated |
| WAL replay time exceeds DB RTO budget | medium | high | investigating streaming replication | open |
| site-b firewall config drift from site-a | low | medium | pfSense config backup on every change + quarterly comparison | mitigated |
| DB app config hardcoded in config file | medium | medium | documented in runbook as manual step, future: env variable | partial |

## relationship to other ITIL practices

Service Continuity Management doesn't work in isolation. It has dependencies on and feeds into several other ITIL practices:

Incident Management — when an outage triggers DR activation, the failover runbook runs in parallel with the incident management process. The incident ticket captures the timeline, and the post-incident review produces inputs for the next DR plan update.

Change Management — any change to the DR environment (new VM, updated IP, new backup target) requires a change ticket. Changes that affect RTO/RPO capability get flagged for re-testing before the next DR exercise. The two test runs in this repo were both preceded by change tickets for environment updates.

Availability Management — the SLA targets for each service tier come from the availability management practice. DR ensures that when planned availability fails, we can recover within the agreed windows. The RTO and RPO targets in this project are the availability commitments during a DR scenario.

Continual Improvement — the improvement loop described above is a direct application of the ITIL continual improvement practice. Each test run generates a service improvement item. The trend from test 1 to test 2 (database RTO from 5h 12m to 3h 48m) is a measurable improvement that can be reported to management.
