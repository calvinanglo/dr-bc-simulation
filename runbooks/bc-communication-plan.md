# Business Continuity Communication Plan

The technical failover is only half the job. During a real outage, unclear or late communication creates almost as much business impact as the outage itself. This plan defines who gets notified, when, and what the message says.

## stakeholder tiers and notification timing

**T+0 to T+15 minutes — internal IT team**
The on-call engineer and team lead are notified immediately via PagerDuty/phone when the DeviceUnreachable critical alert fires. At T+15, if the outage is still ongoing, the IT manager gets a call.

**T+30 minutes — management and service owners**
If failover has been initiated, the IT director and department heads are notified. The message at this point should include: what's affected, what we're doing, and an estimated time to restore.

**T+60 minutes — broader business stakeholders**
If services are still degraded, all staff who use the affected systems get an email. Keep it non-technical — "the [system] is unavailable, we're working on restoring it, estimated restoration by [time]."

**T+RTO — service restored notification**
When services are back, notify all tiers in reverse order. Include a summary of what happened, what data may have been lost (RPO impact), and when a full incident report will be available.

## contact list

| role | name | primary contact | backup contact |
|---|---|---|---|
| on-call engineer | rotation | PagerDuty | mobile |
| IT team lead | [team lead] | mobile | email |
| IT manager | [manager] | mobile | email |
| IT director | [director] | email | mobile |
| service owner - web | [owner] | email | |
| service owner - db | [owner] | email | |

Keep this table updated. During a DR event is the worst time to discover the contact list is stale.

## message templates

### initial alert — T+15 (internal, IT manager)

Subject: [OUTAGE ACTIVE] Primary site services unavailable — failover initiated

We have a confirmed outage affecting the primary site (site-a). Services impacted: web tier, database. Failover to site-b has been initiated per the DR runbook. Current status: phase 1 (network cutover) in progress.

Estimated RTO: 4 hours from incident start (database is the bottleneck).
RPO risk: up to 15 minutes of database transactions may not be recoverable.

Next update in 30 minutes or when phase 1 is complete.

### status update — T+60 (management and service owners)

Subject: [OUTAGE UPDATE] Services partially restored — database restore in progress

Network failover is complete (phase 1 done, T+18 minutes). Web server is online on site-b. Database restore is in progress, currently at the WAL replay stage. Estimated database restoration: [time].

Users may be able to access read-only functionality if the app supports it, but writes will fail until the database is online.

### service restored — post-RTO

Subject: [RESOLVED] Services restored on secondary site

All services are restored on site-b as of [time]. Total outage duration: [X hours Y minutes]. Estimated data loss: [N] minutes of transactions (within our 15-minute RPO target / we exceeded our RPO target by [X] minutes).

A full post-incident report will be available within 5 business days. The report will include root cause analysis, timeline, and corrective actions to prevent recurrence.

## during the outage — what not to do

Don't give specific ETAs you can't commit to. If the database restore is taking longer than expected, saying "10 more minutes" and then missing it twice destroys confidence. Better to say "within the next 2 hours" and beat it.

Don't go silent. Regular updates — even "still working on it, no change" — are better than nothing. Silence makes people assume the worst.

Don't use technical jargon in stakeholder communications. "PostgreSQL WAL replay is in progress" means nothing to the finance team. "We're rebuilding the database from backups" is clear enough.

## post-incident review

Within 5 business days of any DR event (real or test), schedule a post-incident review with the IT team. The agenda covers:

1. Timeline reconstruction — what happened, when was it detected, what was done
2. 2. RTO/RPO actuals vs. targets
   3. 3. What went well
      4. 4. What broke or was slower than expected
         5. 5. Action items with owners and due dates
           
            6. Action items from the review feed back into updating the DR runbook, backup configuration, or environment changes. This is the ITIL continual improvement loop applied to service continuity.
