# DR/BC Simulation Lab -- Setup Guide

This guide walks through the complete setup of Project 5 (dr-bc-simulation), from prerequisites through running your first disaster recovery test and documenting results.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Setting Up Primary Site VMs](#2-setting-up-primary-site-vms)
3. [Setting Up DR Site VMs](#3-setting-up-dr-site-vms)
4. [Configuring PostgreSQL Backups](#4-configuring-postgresql-backups)
5. [Running Backup Validation](#5-running-backup-validation)
6. [Running Your First DR Test](#6-running-your-first-dr-test)
7. [Documenting Test Results](#7-documenting-test-results)
8. [Post-Test Review and ITIL Continual Improvement](#8-post-test-review-and-itil-continual-improvement)
9. [Verification](#9-verification)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

Before starting Project 5, confirm the following are complete and operational.

### Projects 1-4 Complete

- **Project 1 (Proxmox Homelab):** Proxmox VE installed and accessible on both nodes.
- **Project 2 (Network Infrastructure):** pfSense routing, VLANs, and firewall rules configured.
- **Project 3 (NAS/Storage):** TrueNAS or equivalent NAS with SMB/NFS shares available for backups.
- **Project 4 (Monitoring):** Grafana, Prometheus, or equivalent monitoring stack running and collecting metrics.

### Hardware and Software Requirements

| Requirement | Detail |
|---|---|
| Proxmox VE Nodes | Minimum 2 (one primary site, one DR site) |
| NAS Storage | Accessible from both nodes via NFS or SMB |
| RAM per node | Enough to run 3 VMs per site (recommend 16 GB+) |
| Backblaze B2 | Account created, bucket provisioned, application key generated |
| SSH access | Key-based SSH between all VMs and the management host |

### Verify Proxmox Cluster Health

Log into the Proxmox web UI and confirm both nodes appear healthy under **Datacenter > Cluster**.

> Screenshot: Proxmox web UI showing Datacenter view with both nodes listed and status "Online"
> Save as: docs/screenshots/01-proxmox-cluster-nodes.png

---

## 2. Setting Up Primary Site VMs

Create the following three VMs on **Node 1** (primary site). Use your standard VM template or install from ISO.

### 2.1 web-server-a

| Setting | Value |
|---|---|
| VM Name | web-server-a |
| OS | Ubuntu Server 22.04 LTS (or your standard) |
| vCPUs | 2 |
| RAM | 2 GB |
| Disk | 20 GB |
| Network | VLAN for primary site servers |
| Purpose | Web application server (Apache/Nginx) |

1. Create the VM in Proxmox on Node 1.
2. Install the OS and apply updates: `sudo apt update && sudo apt upgrade -y`
3. Install your web server package (e.g., `sudo apt install nginx -y`).
4. Deploy your test web application or a placeholder index page.
5. Confirm the web server responds on its assigned IP.

### 2.2 db-server-a

| Setting | Value |
|---|---|
| VM Name | db-server-a |
| OS | Ubuntu Server 22.04 LTS |
| vCPUs | 2 |
| RAM | 4 GB |
| Disk | 40 GB |
| Network | VLAN for primary site servers |
| Purpose | PostgreSQL database server |

1. Create the VM in Proxmox on Node 1.
2. Install PostgreSQL: `sudo apt install postgresql postgresql-client -y`
3. Create your application database and user:
   ```bash
   sudo -u postgres createuser --pwprompt appuser
   sudo -u postgres createdb --owner=appuser appdb
   ```
4. Configure `pg_hba.conf` to allow connections from web-server-a.
5. Restart PostgreSQL and verify connectivity from web-server-a.

### 2.3 pfsense-a

| Setting | Value |
|---|---|
| VM Name | pfsense-a |
| OS | pfSense CE (latest stable) |
| vCPUs | 1 |
| RAM | 1 GB |
| Disk | 10 GB |
| Network | WAN + LAN interfaces for primary site |
| Purpose | Firewall and routing for primary site |

1. Create the VM with two network interfaces (WAN-facing and LAN-facing).
2. Install pfSense and complete the initial setup wizard.
3. Configure firewall rules to allow traffic between web-server-a and db-server-a.
4. Configure NAT rules for external access to web-server-a if needed.

> Screenshot: Proxmox VM list on Node 1 showing web-server-a, db-server-a, and pfsense-a all running
> Save as: docs/screenshots/02-primary-site-vms.png

---

## 3. Setting Up DR Site VMs

Create mirror VMs on **Node 2** (DR site). These should be identical in configuration to the primary site VMs but will remain in standby until a failover event.

### 3.1 web-server-b

1. Clone or recreate web-server-a's configuration on Node 2.
2. Install the same web server package and deploy the same application.
3. Assign an IP address on the DR site VLAN.
4. Leave the web server service stopped (or serving a maintenance page) until failover.

### 3.2 db-server-b

1. Clone or recreate db-server-a's configuration on Node 2.
2. Install the same PostgreSQL version.
3. Create the same database and user structure.
4. Leave the database empty for now -- it will be restored from backup during failover.

### 3.3 pfsense-b

1. Clone or recreate pfsense-a's configuration on Node 2.
2. Configure matching firewall and NAT rules for the DR site network.
3. Ensure routing between DR site VMs works correctly.

> Screenshot: Proxmox VM list on Node 2 showing web-server-b, db-server-b, and pfsense-b
> Save as: docs/screenshots/03-dr-site-vms.png

---

## 4. Configuring PostgreSQL Backups

All backup configuration happens on **db-server-a** (the primary database server).

### 4a. pg_dump Cron Job

Create a script to perform nightly full backups using `pg_dump`.

1. Create the backup script on db-server-a:
   ```bash
   sudo mkdir -p /opt/backups/scripts
   sudo nano /opt/backups/scripts/pg-backup.sh
   ```

2. Add the following content:
   ```bash
   #!/bin/bash
   TIMESTAMP=$(date +%Y%m%d_%H%M%S)
   BACKUP_DIR="/mnt/nas/backups/postgres"
   DB_NAME="appdb"
   LOG_FILE="/var/log/pg-backup.log"

   mkdir -p "$BACKUP_DIR"

   echo "[$TIMESTAMP] Starting pg_dump of $DB_NAME" >> "$LOG_FILE"

   pg_dump -U postgres -Fc "$DB_NAME" > "$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump" 2>> "$LOG_FILE"

   if [ $? -eq 0 ]; then
       echo "[$TIMESTAMP] Backup completed successfully" >> "$LOG_FILE"
   else
       echo "[$TIMESTAMP] ERROR: Backup failed" >> "$LOG_FILE"
       exit 1
   fi

   # Retain last 7 days of backups
   find "$BACKUP_DIR" -name "*.dump" -mtime +7 -delete
   ```

3. Make it executable and add the cron job:
   ```bash
   sudo chmod +x /opt/backups/scripts/pg-backup.sh
   sudo crontab -e
   ```

4. Add this line to run nightly at 2:00 AM:
   ```
   0 2 * * * /opt/backups/scripts/pg-backup.sh
   ```

### 4b. WAL Archiving Every 10 Minutes

WAL (Write-Ahead Log) archiving provides point-in-time recovery capability, reducing potential data loss to a 10-minute window.

1. Edit `postgresql.conf` on db-server-a:
   ```bash
   sudo nano /etc/postgresql/14/main/postgresql.conf
   ```

2. Set the following parameters:
   ```
   wal_level = replica
   archive_mode = on
   archive_command = 'cp %p /mnt/nas/backups/postgres/wal/%f'
   archive_timeout = 600
   ```

   The `archive_timeout` value of 600 seconds (10 minutes) forces a WAL segment switch even during low-activity periods, ensuring WAL files are archived at least every 10 minutes.

3. Create the WAL archive directory:
   ```bash
   sudo mkdir -p /mnt/nas/backups/postgres/wal
   sudo chown postgres:postgres /mnt/nas/backups/postgres/wal
   ```

4. Restart PostgreSQL to apply:
   ```bash
   sudo systemctl restart postgresql
   ```

5. Verify WAL archiving is active:
   ```bash
   sudo -u postgres psql -c "SELECT * FROM pg_stat_archiver;"
   ```

### 4c. NAS Mount Configuration

Mount the NAS backup share on db-server-a so both pg_dump and WAL archiving can write to it.

1. Install NFS utilities (if using NFS):
   ```bash
   sudo apt install nfs-common -y
   ```

2. Create the mount point and add to `/etc/fstab`:
   ```bash
   sudo mkdir -p /mnt/nas/backups
   ```

3. Add to `/etc/fstab` (adjust NAS IP and share path):
   ```
   192.168.1.50:/mnt/pool/backups  /mnt/nas/backups  nfs  defaults,_netdev  0  0
   ```

4. Mount and verify:
   ```bash
   sudo mount -a
   df -h /mnt/nas/backups
   ```

5. Also mount the NAS on **db-server-b** using the same steps so it can access backups during restore.

### 4d. Backblaze B2 Offsite Sync

Configure `rclone` to sync local NAS backups to Backblaze B2 for offsite protection.

1. Install rclone on the NAS or on db-server-a:
   ```bash
   sudo apt install rclone -y
   ```

2. Configure the B2 remote:
   ```bash
   rclone config
   ```
   - Choose "New remote"
   - Name: `b2-offsite`
   - Type: Backblaze B2
   - Enter your Account ID and Application Key
   - Accept defaults for remaining options

3. Test the connection:
   ```bash
   rclone ls b2-offsite:your-bucket-name
   ```

4. Create a sync script:
   ```bash
   sudo nano /opt/backups/scripts/b2-sync.sh
   ```

   ```bash
   #!/bin/bash
   TIMESTAMP=$(date +%Y%m%d_%H%M%S)
   LOG_FILE="/var/log/b2-sync.log"

   echo "[$TIMESTAMP] Starting B2 sync" >> "$LOG_FILE"

   rclone sync /mnt/nas/backups/postgres b2-offsite:your-bucket-name/postgres \
       --transfers 4 \
       --log-file "$LOG_FILE" \
       --log-level INFO

   echo "[$TIMESTAMP] B2 sync complete" >> "$LOG_FILE"
   ```

5. Schedule the sync to run after the nightly backup:
   ```
   30 2 * * * /opt/backups/scripts/b2-sync.sh
   ```

---

## 5. Running Backup Validation

The `backup-validate.sh` script checks that all backup components are working correctly.

1. Navigate to the scripts directory:
   ```bash
   cd /path/to/dr-bc-simulation/scripts
   ```

2. Run the validation script:
   ```bash
   sudo bash backup-validate.sh
   ```

3. The script checks:
   - NAS mount is accessible and writable
   - Recent pg_dump file exists (within last 24 hours)
   - WAL archive files are being generated (within last 10 minutes)
   - B2 offsite sync is current
   - Backup file integrity (checksums)
   - Restore test on db-server-b completes successfully

4. Review the output. All checks should show **PASS**.

> Screenshot: Terminal output of backup-validate.sh showing all checks passing with PASS status
> Save as: docs/screenshots/04-backup-validation-output.png

If any checks fail, resolve the issue before proceeding to DR testing. See [Troubleshooting](#10-troubleshooting) for common failures.

---

## 6. Running Your First DR Test

### 6a. Pre-Flight Checks

Before running a failover test, confirm:

- [ ] All primary site VMs are running and healthy
- [ ] All DR site VMs exist and are accessible (powered on or ready to start)
- [ ] Backup validation passes all checks (Step 5)
- [ ] Monitoring is active and collecting baseline metrics
- [ ] You have documented the current state (IPs, service status, last backup timestamp)
- [ ] Stakeholders are notified (even in a lab, practice the communication step)

### 6b. Scenario Selection

Choose a test scenario for your first run. Start simple and increase complexity over time:

| Scenario | Description | Difficulty |
|---|---|---|
| Database failover | Restore PostgreSQL to db-server-b from backup | Low |
| Full site failover | Fail over all services to DR site | Medium |
| Partial failure | Simulate single-VM failure (e.g., web server only) | Medium |
| Network partition | Simulate loss of connectivity between sites | High |
| Cascading failure | Multiple simultaneous component failures | High |

For your first test, select **Database failover** to validate the backup and restore pipeline end-to-end.

### 6c. Running failover-test.sh

1. Navigate to the scripts directory:
   ```bash
   cd /path/to/dr-bc-simulation/scripts
   ```

2. Run the failover test script with your chosen scenario:
   ```bash
   sudo bash failover-test.sh --scenario database-failover
   ```

3. The script will:
   - Verify pre-conditions
   - Stop the primary database service (simulating failure)
   - Locate the most recent backup on the NAS
   - Restore the backup to db-server-b
   - Apply any available WAL files for point-in-time recovery
   - Reconfigure web-server-b to point to db-server-b
   - Run connectivity and data-integrity checks
   - Report results

> Screenshot: Terminal output of failover-test.sh showing each step completing with status indicators
> Save as: docs/screenshots/05-failover-test-output.png

### 6d. Using rto-timer.sh for Timing

Run the RTO timer alongside the failover test to measure recovery time.

1. In a separate terminal, start the timer before initiating failover:
   ```bash
   sudo bash scripts/rto-timer.sh --start
   ```

2. The timer runs in the foreground, showing elapsed time.

3. When the failover test completes and services are confirmed operational, stop the timer:
   ```bash
   sudo bash scripts/rto-timer.sh --stop
   ```

4. The script outputs:
   - Total elapsed time (RTO actual)
   - Comparison against your RTO target
   - PASS/FAIL based on whether the target was met

> Screenshot: Terminal output of rto-timer.sh showing elapsed time, RTO target, and PASS/FAIL result
> Save as: docs/screenshots/06-rto-timer-results.png

---

## 7. Documenting Test Results

Record every DR test in the `test-results/` directory. Each test should include:

1. **Test metadata:** Date, scenario, personnel involved.
2. **Timeline:** Start time, key milestones, end time.
3. **RTO/RPO measurements:**
   - **RTO (Recovery Time Objective):** How long until services were restored.
   - **RPO (Recovery Point Objective):** How much data was lost (difference between last backup and failure time).
3. **Issues encountered:** Any errors, delays, or unexpected behavior.
4. **Pass/Fail determination:** Did the test meet defined RTO and RPO targets?

Use the template in `test-results/` or create a new entry:

```bash
cp test-results/template.md test-results/YYYY-MM-DD-scenario-name.md
```

Fill in all sections. Be specific about what went wrong and what went right.

> Screenshot: Completed test results file or comparison table showing RTO/RPO targets vs actuals across multiple tests
> Save as: docs/screenshots/07-test-results-comparison.png

---

## 8. Post-Test Review and ITIL Continual Improvement

After each DR test, conduct a review following ITIL continual improvement principles.

### 8.1 Immediate Post-Test Actions

1. **Restore primary site:** Bring primary site services back online and confirm normal operation.
2. **Compare results to targets:** Document whether RTO and RPO targets were met.
3. **Collect feedback:** Note observations from anyone involved.

### 8.2 Problem Analysis

For any issues encountered during the test:

1. **Root cause analysis:** Identify why the issue occurred.
2. **Impact assessment:** How did it affect recovery time or data loss?
3. **Categorize:** Is this a process issue, configuration issue, tooling gap, or knowledge gap?

### 8.3 Improvement Actions

Apply the ITIL continual improvement model (Plan-Do-Check-Act):

| Phase | Action |
|---|---|
| **Plan** | Identify specific improvements based on test findings |
| **Do** | Implement changes to scripts, runbooks, or infrastructure |
| **Check** | Run the next DR test and measure whether improvements helped |
| **Act** | Standardize successful changes; iterate on remaining gaps |

### 8.4 Update Runbooks

After every test, update the runbooks in the `runbooks/` directory:

- Fix any steps that were inaccurate or unclear.
- Add new steps for issues that required manual intervention.
- Update time estimates based on actual measurements.

---

## 9. Verification

Before considering the DR/BC simulation project complete, confirm all of the following:

### Backup Validation All Passing

```bash
sudo bash scripts/backup-validate.sh
```

- All checks return PASS.
- NAS backups are current (pg_dump within 24 hours, WAL within 10 minutes).
- B2 offsite sync is current.
- Restore test completes without errors.

### Failover Script Runs Without Errors

```bash
sudo bash scripts/failover-test.sh --scenario database-failover
```

- Script completes all steps without errors.
- Database is successfully restored on db-server-b.
- Web application on web-server-b connects to restored database.
- Data integrity checks pass.

### RTO/RPO Targets Met

| Metric | Target | Actual | Status |
|---|---|---|---|
| RTO (Recovery Time Objective) | < 30 minutes | _fill in_ | PASS/FAIL |
| RPO (Recovery Point Objective) | < 10 minutes of data loss | _fill in_ | PASS/FAIL |

Adjust targets based on your environment and business requirements. The values above are starting points for a homelab.

---

## 10. Troubleshooting

### NAS Mount Fails

**Symptom:** `mount -a` fails or `/mnt/nas/backups` is not accessible.

**Fixes:**
- Verify the NAS IP is reachable: `ping 192.168.1.50`
- Check NFS exports on the NAS: ensure the share is exported to the correct subnet.
- Verify `nfs-common` is installed: `dpkg -l | grep nfs-common`
- Check firewall rules: NFS uses ports 111 and 2049.

### pg_dump Backup Not Found

**Symptom:** Backup validation fails with "no recent backup found."

**Fixes:**
- Check the cron job is scheduled: `sudo crontab -l`
- Run the backup manually: `sudo bash /opt/backups/scripts/pg-backup.sh`
- Check the log file: `cat /var/log/pg-backup.log`
- Verify the NAS mount is writable: `touch /mnt/nas/backups/postgres/test && rm /mnt/nas/backups/postgres/test`

### WAL Archiving Not Working

**Symptom:** No recent WAL files in `/mnt/nas/backups/postgres/wal/`.

**Fixes:**
- Check `archive_mode` is on: `sudo -u postgres psql -c "SHOW archive_mode;"`
- Check `archive_command`: `sudo -u postgres psql -c "SHOW archive_command;"`
- Look for archive errors: `sudo -u postgres psql -c "SELECT * FROM pg_stat_archiver;"`
- Verify directory permissions: `ls -la /mnt/nas/backups/postgres/wal/`
- Force a WAL switch to test: `sudo -u postgres psql -c "SELECT pg_switch_wal();"`

### B2 Sync Fails

**Symptom:** Backblaze B2 sync errors or stale offsite backups.

**Fixes:**
- Test rclone config: `rclone ls b2-offsite:your-bucket-name`
- Check B2 application key has write permissions.
- Review sync log: `cat /var/log/b2-sync.log`
- Run sync manually: `sudo bash /opt/backups/scripts/b2-sync.sh`

### Failover Test Fails During Restore

**Symptom:** `failover-test.sh` errors during database restore on db-server-b.

**Fixes:**
- Verify PostgreSQL is installed and running on db-server-b.
- Check that the PostgreSQL version on db-server-b matches db-server-a.
- Ensure db-server-b can access the NAS mount.
- Try a manual restore: `pg_restore -U postgres -d appdb /mnt/nas/backups/postgres/latest.dump`
- Check disk space on db-server-b: `df -h`

### RTO Target Not Met

**Symptom:** Recovery takes longer than the target.

**Fixes:**
- Identify the slowest step in the failover timeline.
- For slow restores: consider using `pg_basebackup` instead of `pg_dump` for large databases.
- For slow WAL replay: ensure archive files are on fast storage.
- For slow network transfers: check NAS link speed and consider compression.
- Automate any manual steps that added delay.
- Update runbooks with optimized procedures and re-test.

### DR Site VMs Won't Start

**Symptom:** VMs on Node 2 fail to start during failover.

**Fixes:**
- Check available resources on Node 2: RAM, CPU, disk.
- Verify VM configuration is valid in Proxmox.
- Check Proxmox logs: `journalctl -u pve-cluster`
- Ensure storage backing the VMs is accessible.

---

## Next Steps

After completing your first successful DR test:

1. Schedule regular DR tests (monthly recommended).
2. Increase scenario complexity over time.
3. Add automated alerting for backup failures.
4. Document lessons learned and feed them back into Projects 1-4.
5. Build a test results dashboard using your Project 4 monitoring stack.
