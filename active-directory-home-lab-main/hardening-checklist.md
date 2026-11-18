# Hardening Checklist

A baseline of security controls for the `corp.lab` domain, each mapped to the concept it represents (CompTIA Security+ SY0-701 framing). Status is honest about what was implemented in the lab versus what would be applied in a production environment — a documented, reasoned checklist demonstrates security maturity better than a list of clicks.

**Status key:** ✅ Implemented in lab · 🟡 Partially implemented / demonstrated · 📋 Would implement in production

---

## Identity & Access

| Control | Status | How | Concept |
|---|---|---|---|
| Strong password policy | ✅ | Default Domain Policy: 14-char minimum, complexity enabled, 90-day max age (Stage 9) | Authentication hardening |
| Account lockout policy | ✅ | 5 invalid attempts → 15-minute lockout (Stage 9) | Brute-force resistance |
| Least-privilege group model | ✅ | AGDLP: accounts → global groups → domain local groups → permissions (Stage 8) | Least privilege |
| Identity lifecycle management | ✅ | Scripted provisioning, password reset, and offboarding (disable-don't-delete) (Stage 8 & 10) | Account lifecycle / accountability |
| Logon warning banner | ✅ | GPO-set interactive logon message ("Authorized users only") (Stage 9) | Deterrent control |
| Tiered admin accounts | 🟡 | Model documented (`jane.doe` vs `a-jane.doe`); separate daily and admin accounts, never browse/email as a domain admin | Privileged access management |
| Limit Domain Admins membership | 📋 | Keep to the absolute minimum and audit regularly | Least privilege |
| Rename / secure built-in Administrator | 📋 | Rename the built-in account; use named admin accounts so actions are attributable | Accountability |
| Windows LAPS | 📋 | Randomize and rotate local administrator passwords, stored and access-controlled in AD | Credential protection |

---

## System & Network

| Control | Status | How | Concept |
|---|---|---|---|
| Host firewall enabled | ✅ | Windows Defender Firewall on across all profiles (default, left on) | Preventive control |
| Isolated lab network | ✅ | Dedicated NAT Network; VirtualBox DHCP disabled so DC01 is the single DHCP authority | Network segmentation |
| `.lab` domain suffix | ✅ | Non-routable suffix avoids any clash with public DNS | Reduces external exposure |
| Patch management | 📋 | Windows Update on DC and client with a documented cadence | Vulnerability management |
| Reduce attack surface | 📋 | Remove unused roles/features; disable SMBv1 and other legacy protocols | Attack surface reduction |
| Secure RDP | 📋 | Require Network Level Authentication; restrict who can connect; never expose externally | Secure remote access |
| Authoritative time (NTP) | 📋 | Configure the DC as the authoritative time source | Kerberos depends on accurate time (clock skew breaks logons) |

---

## Monitoring & Recovery

| Control | Status | How | Concept |
|---|---|---|---|
| Audit logon & account events | 🟡 | Auditing configurable via GPO; reviewed in Event Viewer | Detective control |
| Stale-account reporting | ✅ | PowerShell report flags accounts that have never logged on (Stage 10) | Account hygiene / detective control |
| Active Directory backup | 📋 | Schedule a System State backup of the DC | Availability / recovery |
| Snapshot-based recovery | ✅ | Every stage snapshotted at a known-good point; lab is rebuildable on demand | Recoverability |
| DSRM password recorded | ✅ | Directory Services Restore Mode password set at promotion and recorded (distinct from the domain Administrator) | Recovery readiness |

---

## Notes

- **Implemented controls** are live in the lab and verifiable in the per-stage write-ups and screenshots.
- **Planned controls** are documented here as production recommendations; several (LAPS, System State backup, NTP authority) are straightforward next steps and are noted in the guide's "Where to take it next."
- Credentials and the `LabPasswords.txt` file are deliberately excluded from this repository.

*Security is a posture, not a checkbox — this list reflects both what the lab enforces today and what a production domain should enforce.*
