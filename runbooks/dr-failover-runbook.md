# DR Failover Runbook

Version: 2.1
Last tested: 2024-11-15
Owner: network/systems team

This runbook covers full site failover from primary (site-a) to secondary (site-b). It's written to be executed by anyone on the team — not just the person who built the environment. Steps include timing checkpoints so we can measure RTO against targets.

Primary site: 10.10.20.0/24 — VLAN 20 (Proxmox node 1)
Secondary site: 10.10.20.0/24 — VLAN 20 (Proxmox node 2)

---

## pre-conditions — confirm before starting failover

Before declaring a disaster and initiating failover, confirm that the primary site outage is real and not a transient issue:

1. Verify multiple services are unreachable (not just one VM)
2. 2. Check if the monitoring server can reach site-a devices on the management VLAN
   3. 3. Confirm with at least one other team member
      4. 4. Check pfSense logs if accessible — if the firewall is still up, the issue may be isolated
        
         5. If the outage has been ongoing for more than 15 minutes with no recovery path, proceed with failover.
        
         6. **Start RTO timer now. Log start time: ________**
        
         7. ---
        
         8. ## phase 1 — network cutover (target: 30 min)
        
         9. ### 1.1 access secondary site firewall
        
         10. SSH to site-b pfSense at 10.0.0.3 from the management jump host or out-of-band console.
        
         11. ```
             ssh admin@10.0.0.3
             ```

             ### 1.2 verify secondary WAN link is active

             ```
             pfctl -si | grep state
             ping -c 4 8.8.8.8
             ```

             If WAN is down on site-b, contact ISP before continuing. The secondary WAN uses a different ISP for circuit diversity.

             ### 1.3 update BGP/static routes if using dynamic routing

             In this lab environment, static routes are used. Update the default route to point through site-b:

             ```
             route del default
             route add default gw 10.0.0.3
             ```

             On production, this would be a BGP prefix announcement — site-b would start advertising the same IP space.

             ### 1.4 DNS failover

             Update internal DNS to point service records to site-b IPs. Zone file changes are in `/etc/bind/zones/` on the DNS server.

             Key records to update:
             - web.internal → 10.10.20.110 (was 10.10.20.10)
             - - db.internal → 10.10.20.120 (was 10.10.20.20)
               - - monitor.internal → 10.10.20.130 (was 10.10.20.30)
                
                 - ```
                   vim /etc/bind/zones/db.internal
                   # update A records to site-b IPs
                   systemctl reload bind9
                   ```

                   Flush DNS cache on a test client: `sudo systemd-resolve --flush-caches`

                   **Phase 1 complete time: ________ (target: T+30min)**

                   ---

                   ## phase 2 — database restore (target: T+4 hours)

                   This is the longest phase and the one most likely to miss target. The PostgreSQL restore takes 30-90 minutes depending on database size and WAL replay volume.

                   ### 2.1 identify most recent backup

                   Backups land on the NAS at `//nas-01/backups/postgresql/`. Check for the most recent full backup and any WAL archives newer than it.

                   ```
                   ssh backup-user@10.10.20.50
                   ls -lth /mnt/backups/postgresql/full/ | head -5
                   ls -lth /mnt/backups/postgresql/wal/ | head -20
                   ```

                   The most recent full backup should be no older than 24 hours. WAL archives run every 10 minutes, so RPO should be under 15 minutes from the last WAL file timestamp.

                   **Log most recent full backup timestamp: ________**
                   **Log most recent WAL archive timestamp: ________**
                   **Calculated RPO: ________ minutes**

                   ### 2.2 restore full backup to site-b database VM

                   ```
                   ssh db-server-b@10.10.20.120
                   sudo systemctl stop postgresql
                   sudo rm -rf /var/lib/postgresql/14/main/
                   sudo -u postgres pg_restore -d postgres -v /mnt/backups/postgresql/full/db_full_latest.pgdump
                   ```

                   This step takes 20-60 minutes depending on database size. Do not interrupt.

                   ### 2.3 apply WAL archives for point-in-time recovery

                   Edit `/etc/postgresql/14/main/recovery.conf`:

                   ```
                   restore_command = 'cp /mnt/backups/postgresql/wal/%f %p'
                   recovery_target_time = '2024-11-15 14:30:00'  # set to time just before failure
                   ```

                   Start postgres and let it replay WAL:

                   ```
                   sudo systemctl start postgresql
                   # watch logs for replay progress
                   sudo tail -f /var/log/postgresql/postgresql-14-main.log | grep -E 'redo|recovery|LOG'
                   ```

                   ### 2.4 verify database integrity

                   ```
                   sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_user_tables;"
                   sudo -u postgres psql -c "\l"
                   # run application-specific validation query here
                   ```

                   **Phase 2 complete time: ________ (target: T+4 hours)**

                   ---

                   ## phase 3 — web tier and application services (target: T+2 hours)

                   ### 3.1 start web server VM on site-b

                   The web server VM snapshot is kept current via a nightly Proxmox backup. Start from the most recent snapshot.

                   On Proxmox node 2:
                   ```
                   qm start 201  # web-server-b VM ID
                   ```

                   Wait for VM to boot (~2 min), then SSH in and verify services:

                   ```
                   ssh 10.10.20.110
                   systemctl status nginx
                   systemctl status app-service
                   ```

                   ### 3.2 update application database connection string

                   The app config at `/etc/app/config.yml` has a `db_host` value pointing to site-a. Update it to site-b:

                   ```
                   sed -i 's/db_host: 10.10.20.20/db_host: 10.10.20.120/' /etc/app/config.yml
                   systemctl restart app-service
                   ```

                   ### 3.3 smoke test

                   Hit the web service from an external client:

                   ```
                   curl -I http://web.internal/health
                   # expect: HTTP/1.1 200 OK
                   ```

                   Check application logs for database connectivity errors:
                   ```
                   tail -50 /var/log/app/app.log | grep -i error
                   ```

                   **Phase 3 complete time: ________ (target: T+2 hours)**

                   ---

                   ## phase 4 — declaration and notification

                   Once all services are validated:

                   1. Log final RTO: `________` (time from phase start to phase 3 sign-off)
                   2. 2. Notify stakeholders per `bc-communication-plan.md`
                      3. 3. Open incident ticket for post-incident review
                         4. 4. Do not start failback until root cause of primary site failure is confirmed and resolved
                           
                            5. **Total RTO achieved: ________**
                            6. **Total RPO (data loss): ________ minutes**
                           
                            7. ---
                           
                            8. ## known issues and gotchas
                           
                            9. The PostgreSQL restore step has caused the most problems. Make sure the backup destination in `/etc/cron.d/db-backup` is pointing to the NAS mount (`/mnt/nas-backup/`) and not the local disk. This was the root cause of the test 1 failure — the backup file existed but was on the failed primary server, not the NAS.
                           
                            10. After WAL replay, PostgreSQL sometimes stays in standby mode waiting for a `pg_ctl promote` command. If the database starts but the app can't write, check `pg_is_in_recovery()`:
                           
                            11. ```
                                sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
                                # if returns 't', run:
                                sudo -u postgres pg_ctl promote -D /var/lib/postgresql/14/main/
                                ```
