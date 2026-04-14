# dr-bc-simulation

Disaster recovery and business continuity simulation built in a home lab using Proxmox VMs. The goal was to actually test failover and measure RTO/RPO against defined targets — not just document a theoretical plan, but run the scenarios, record the numbers, and iterate on what broke.

The environment has a primary site (three VMs: web, database, and a pfSense firewall/router) and a simulated secondary site on a separate Proxmox node. Backups go to a local NAS via rsync and a secondary copy goes to Backblaze B2. Network failover is simulated by toggling the VLAN trunk on the primary switch.

## Project Series

This is **Project 5 of 5** in a production enterprise environment build. Each project builds on the previous one.

| # | Project | What It Adds |
|---|---------|-------------|
| 1 | [Enterprise Network Segmentation](https://github.com/calvinanglo/enterprise-network-segmentation) | VLANs, OSPF, ACLs, pfSense firewall |
| 2 | [Wazuh SIEM Deployment](https://github.com/calvinanglo/wazuh-siem-deployment) | Centralized log collection, threat detection, incident response |
| 3 | [Compliance Hardening Pipeline](https://github.com/calvinanglo/compliance-hardening-pipeline) | Automated CIS benchmarks across all devices |
| 4 | [Network Monitoring Stack](https://github.com/calvinanglo/network-monitoring-stack) | Prometheus, Grafana, SNMP monitoring, SLA dashboards |
| 5 | [DR & BC Simulation](https://github.com/calvinanglo/dr-bc-simulation) | Disaster recovery testing, backup validation, RTO/RPO measurement |

### Prerequisites
- **Complete [Projects 1-4](https://github.com/calvinanglo/enterprise-network-segmentation) first** — the full environment must be operational:
  - Network segmentation with VLANs, OSPF, and pfSense (Project 1)
  - Wazuh SIEM collecting syslog from all devices (Project 2)
  - CIS hardening applied to all hosts (Project 3)
  - Prometheus/Grafana monitoring with SLA dashboards (Project 4)
- Proxmox VE with at least 2 nodes (primary + DR site)
- NAS storage accessible on VLAN 20 for backups
- PostgreSQL database and web application on primary site VMs

## what's in this repo

```
dr-bc-simulation/
  runbooks/
    dr-failover-runbook.md        # step-by-step failover procedure with timing checkpoints
    bc-communication-plan.md      # stakeholder comms during an outage
    backup-restore-procedure.md   # backup validation and restore testing steps
  scripts/
    backup-validate.sh            # automated backup integrity checks
    failover-test.sh              # orchestrates the DR test scenario
    rto-timer.sh                  # tracks and logs RTO measurement per test run
  test-results/
    dr-test-2024-10-01.md         # full test run results with RTO/RPO actuals
    dr-test-2024-11-15.md         # second test run after fixing gaps from first
  docs/
    itil-service-continuity.md    # ITIL SCM practice implementation notes
    environment-topology.md       # lab environment diagram and device inventory
```

## RTO and RPO targets

These were defined before any testing started, based on what a realistic small enterprise would target:

| service | RTO target | RPO target |
|---|---|---|
| web tier | 2 hours | 1 hour |
| database | 4 hours | 15 minutes |
| network connectivity | 30 minutes | N/A |
| DNS / internal services | 1 hour | N/A |

The database RPO being 15 minutes drove the decision to run WAL archiving on PostgreSQL every 10 minutes rather than relying on daily full backups alone.

## test scenarios covered

**scenario 1 — primary site network failure:** Simulated by shutting down the uplink VLAN on the pfSense VM. Measures time from outage detection to secondary site serving traffic.

**scenario 2 — database server failure:** Killed the primary DB VM hard (pulled vCPU). Measured time to restore from most recent backup and verify data integrity. This scenario exposed that the automated backup job was writing to the failed VM's local disk instead of the NAS — fixed in test 2.

**scenario 3 — full primary site loss:** Shut down all primary site VMs simultaneously. Full failover to secondary site, DNS cutover, service validation. This is the longest scenario — measured against the 4-hour RTO for database.

**scenario 4 — backup restore validation:** Monthly test where backups are actually restored to an isolated VM and verified. Checks file integrity, database consistency, and application startup. Automated with `scripts/backup-validate.sh`.

## actual test results summary

First test run (2024-10-01): database RTO came in at 5h 12m — missed the 4-hour target. Root cause was the backup misconfiguration (writing to local disk instead of NAS) plus the restore procedure didn't account for PostgreSQL WAL replay time. Both were fixed before the second test.

Second test run (2024-11-15): all targets met. Database RTO was 3h 48m, web tier RTO was 1h 22m, network was 18 minutes.

## ITIL service continuity management

This project covers the ITIL 4 Service Continuity Management practice. The DR plan is a living document that gets updated after each test run. The test scenarios map to ITIL's continuity testing types — walkthrough tests for the runbooks, simulation tests for scenario 1 and 2, and a full failover test for scenario 3.

The ITIL SCM practice also requires regular reviews to make sure the plan reflects current infrastructure. After the first test exposed the backup misconfiguration, that gap was logged in the risk register and a change request was raised to fix the backup target configuration.

See `docs/itil-service-continuity.md` for the full practice implementation.

## certifications this covers

CCNA 200-301 — network failover, VLAN manipulation during DR scenarios, understanding of routing convergence during site failover
CompTIA Security+ — backup integrity, data confidentiality during recovery, secure off-site storage (B2 with encryption at rest)
ISC2 CC — availability as a core principle of the CIA triad, risk management tied to RTO/RPO definitions, business impact analysis
ITIL 4 Foundation — Service Continuity Management practice, continual improvement loop between test runs, incident and change management integration
