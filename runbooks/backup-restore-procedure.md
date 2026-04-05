# Backup and Restore Procedure

This covers both the daily backup schedule and how to actually do a restore. These are two separate things — a lot of environments have backups configured but have never actually tested restoring from them. This procedure is designed to be run monthly as a validation exercise, not just kept in a drawer.

## backup schedule and retention

| what | method | frequency | destination | retention |
|---|---|---|---|---|
| PostgreSQL full | pg_dump | nightly 02:00 | NAS + B2 | 30 days |
| PostgreSQL WAL | archive_command | every 10 min | NAS + B2 | 7 days |
| web server files | rsync | nightly 03:00 | NAS | 14 days |
| VM snapshots | Proxmox vzdump | weekly Sunday | NAS | 4 weeks |
| pfSense config | auto-backup | on change | NAS + email | last 10 |

B2 (Backblaze) is the offsite copy. The NAS is the primary restore target because it's faster. B2 is only used if the NAS is also unavailable.

## database backup configuration

The backup job runs as the `postgres` system user. The cron entry lives in `/etc/cron.d/postgresql-backup`:

```
0 2 * * * postgres /usr/local/bin/db-backup.sh >> /var/log/db-backup.log 2>&1
```

The script does a `pg_dump` in custom format and copies the output to the NAS mount. WAL archiving is configured in `postgresql.conf`:

```
archive_mode = on
archive_command = 'rsync -a %p /mnt/nas-backup/postgresql/wal/%f'
wal_level = replica
```

Make sure `/mnt/nas-backup/` is actually mounted before assuming backups are working. The second DR test caught this — the NAS mount had dropped after a reboot and no one noticed because the cron job was silently writing to local disk instead. Added a mount check to the backup script after that.

## monthly backup validation procedure

Run `scripts/backup-validate.sh` or follow these manual steps on the first Monday of each month.

### step 1 — verify backup files exist and are recent

```bash
# check NAS backups
ssh backup-user@192.168.10.50
ls -lth /mnt/nas-backup/postgresql/full/ | head -3
# confirm timestamp is from last night

ls -lth /mnt/nas-backup/postgresql/wal/ | head -5
# confirm WAL archives are arriving every 10 minutes
```

If the newest full backup is older than 25 hours, something is wrong — check the cron log at `/var/log/db-backup.log`.

### step 2 — verify file integrity

```bash
# check checksums
sha256sum /mnt/nas-backup/postgresql/full/db_full_$(date +%Y-%m-%d).pgdump
# compare with the .sha256 file that should exist alongside it

# verify the pg_dump file is valid
pg_restore --list /mnt/nas-backup/postgresql/full/db_full_latest.pgdump | wc -l
# if this returns 0 or errors, the backup is corrupt
```

### step 3 — restore to isolated test VM

Spin up a throwaway VM (Proxmox template `ubuntu-22-base`) for the restore test. This VM gets destroyed after validation.

```bash
# on proxmox node 1
qm clone 100 999 --name restore-test --full true
qm start 999

# ssh in and install postgres
ssh 192.168.10.99
sudo apt install postgresql -y
sudo systemctl stop postgresql

# restore backup
sudo -u postgres pg_restore -d postgres -v \
  /mnt/nas-backup/postgresql/full/db_full_latest.pgdump

# verify row counts match production (get prod counts first)
sudo -u postgres psql -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC;"
```

Compare row counts against production. They won't match exactly (because production keeps getting writes) but they should be close to the expected RPO window.

### step 4 — application startup test

Install the application on the restore test VM and point it at the restored database. If the app starts without errors and basic queries work, the backup is valid.

### step 5 — log results and clean up

Fill in the results in `test-results/` using the naming convention `dr-test-YYYY-MM-DD.md`. Then destroy the test VM:

```bash
qm stop 999
qm destroy 999
```

## restore from B2 (offsite)

Only needed if the NAS is also unavailable. Install the B2 CLI and authenticate:

```bash
b2 authorize-account <accountId> <applicationKey>
b2 download-file-by-name backups postgresql/full/db_full_latest.pgdump ./db_full_latest.pgdump
```

B2 downloads are slower than NAS — factor in an extra 30-60 minutes for a 20GB database file on a typical broadband connection. This affects the database RTO estimate in a full-site-loss scenario.
