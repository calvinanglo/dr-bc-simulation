# Environment Topology

Lab environment for DR testing built on Proxmox VE across two physical nodes. The network layer (VLANs, OSPF, ACLs) is documented in the companion project [enterprise-network-segmentation](https://github.com/calvinanglo/enterprise-network-segmentation).

## Site Layout

```
Site-A (Proxmox Node 1 — primary)          Site-B (Proxmox Node 2 — DR)
┌────────────────────────────┐              ┌────────────────────────────┐
│  web-server-a  10.10.20.10 │              │  web-server-b  10.10.20.110│
│  db-server-a   10.10.20.20 │              │  db-server-b   10.10.20.120│
│  pfsense-a     10.0.0.1    │              │  pfsense-b     10.0.0.3    │
└────────────┬───────────────┘              └────────────┬───────────────┘
             │                                           │
        ┌────┴────┐                                 ┌────┴────┐
        │ VLAN 20 │                                 │ VLAN 20 │
        │ Servers │                                 │ DR Site │
        └────┬────┘                                 └────┬────┘
             │                                           │
        ┌────┴──────────────────────────────────────────┴────┐
        │              NAS (10.10.20.50)                      │
        │         Backup target for both sites                │
        └─────────────────────────────────────────────────────┘
```

## Device Inventory

| Device | Role | IP | VLAN | Site | OS |
|--------|------|----|------|------|----|
| web-server-a | Primary web/app server | 10.10.20.10 | 20 (Servers) | A | Ubuntu 22.04 |
| db-server-a | Primary PostgreSQL | 10.10.20.20 | 20 (Servers) | A | Ubuntu 22.04 |
| pfsense-a | Primary perimeter firewall | 10.0.0.1 | WAN | A | pfSense CE 2.7.x |
| web-server-b | DR web/app server | 10.10.20.110 | 20 (Servers) | B | Ubuntu 22.04 |
| db-server-b | DR PostgreSQL | 10.10.20.120 | 20 (Servers) | B | Ubuntu 22.04 |
| pfsense-b | DR perimeter firewall | 10.0.0.3 | WAN | B | pfSense CE 2.7.x |
| nas-01 | Backup storage | 10.10.20.50 | 20 (Servers) | Shared | TrueNAS |

## Network Context

The DR environment sits on the same VLAN structure defined in the [network segmentation project](https://github.com/calvinanglo/enterprise-network-segmentation):

- VLAN 10 (10.10.10.0/24) — Staff workstations
- VLAN 20 (10.10.20.0/24) — Servers, monitoring, DR VMs
- VLAN 30 (10.10.30.0/24) — Guest (isolated)
- VLAN 99 (10.10.99.0/24) — Management / out-of-band access

Site-B VMs use higher addresses on VLAN 20 (.110, .120) to avoid conflicts with site-A during split-brain scenarios.

## Backup Paths

```
db-server-a (10.10.20.20)
    │
    ├─ pg_dump nightly ──→ NAS (10.10.20.50:/mnt/nas-backup/postgresql/full/)
    ├─ WAL archive q10m ─→ NAS (10.10.20.50:/mnt/nas-backup/postgresql/wal/)
    └─ B2 sync nightly ──→ Backblaze B2 (offsite)

web-server-a (10.10.20.10)
    └─ rsync nightly ────→ NAS (10.10.20.50:/mnt/nas-backup/web/)

pfsense-a (10.0.0.1)
    └─ auto-backup ──────→ NAS (10.10.20.50:/mnt/nas-backup/pfsense/)
```

## Proxmox VM IDs

| VM ID | Name | Site | Notes |
|-------|------|------|-------|
| 100 | ubuntu-22-base | — | Template for cloning test VMs |
| 101 | web-server-a | A | Primary web tier |
| 102 | db-server-a | A | Primary database |
| 103 | pfsense-a | A | Primary firewall |
| 201 | web-server-b | B | DR web tier |
| 202 | db-server-b | B | DR database |
| 203 | pfsense-b | B | DR firewall |
| 999 | restore-test | — | Throwaway VM for backup validation |
