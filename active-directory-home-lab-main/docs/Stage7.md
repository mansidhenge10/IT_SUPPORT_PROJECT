# Stage 7 — Organizational Units

**Goal:** Replace reliance on Active Directory's default containers with a real, purpose-built OU structure that Group Policy can target, then relocate the domain-joined workstation into it.

**Environment:** DC01 (Windows Server 2025, 10.10.10.10) · Domain `corp.lab` · Managed via Active Directory Users and Computers (ADUC)

---

## Why this stage matters

Active Directory ships with default containers — `Users`, `Computers`, `Builtin` — that look like folders but are **containers, not Organizational Units**. The distinction is operationally critical:

| | Container (e.g., default `Computers`) | Organizational Unit |
|---|---|---|
| Can link Group Policy | ❌ No | ✅ Yes |
| Can delegate administration | Limited | ✅ Yes, granularly |
| Created by | AD automatically | The administrator, by design |

Every object sitting in a default container is effectively **unreachable by OU-linked Group Policy**. Building a real OU tree — and moving objects into it — is the prerequisite for everything Stage 9 (Group Policy) does. It is also one of the clearer signals in a portfolio that the builder understands AD's structure rather than just its install wizard.

The Type column in ADUC makes the distinction visible: default `Users` and `Computers` report `Container`, while `Domain Controllers` (the only default OU) reports `Organizational Unit`.

📸 `07-01-aduc-default-containers.png` — the default tree with Advanced Features enabled, before any changes. Note the Type column distinguishing containers from the one default OU.

---

## Target OU design

```
corp.lab
  └─ OU=CORP
        ├─ OU=Users
        │     ├─ OU=IT
        │     ├─ OU=HR
        │     └─ OU=Sales
        ├─ OU=Groups
        ├─ OU=Workstations
        ├─ OU=Servers
        └─ OU=Admins
```

Design rationale:

- **A single top-level `OU=CORP`** wraps everything the organization owns. Policies meant for "the whole company" link once, here — while AD's built-in containers and the `Domain Controllers` OU stay outside its scope.
- **Users split by department** (IT / HR / Sales) enables per-department policy and delegation later — drive maps, restrictions, and "the HR lead can reset HR passwords" style delegation all target these.
- **Separate `Workstations` and `Servers`** because client machines and servers need different policy (a lockdown appropriate for a workstation would break a server).
- **A dedicated `Admins` OU** supports the tiered-admin model from the hardening plan — privileged accounts live apart from daily-driver accounts and can carry stricter policy.

---

## Build steps

### 1. Open ADUC with Advanced Features

Server Manager → Tools → **Active Directory Users and Computers**, then **View → Advanced Features**. This exposes the system containers and the per-object Security/Object tabs — the standard working view for real administration.

### 2. Create the top-level OU

Right-click the domain root (`corp.lab`) → **New → Organizational Unit** → name: `CORP`.

**“Protect container from accidental deletion” left checked** (the default). This sets a deny-delete ACE on the object — a guardrail that has saved many an environment from a mis-click deleting an entire department of objects.

📸 `07-02-new-ou-corp-dialog.png` — the New Object dialog with deletion protection visible
📸 `07-03-corp-ou-created.png` — `CORP` present in the tree as a true OU

### 3. Build out the child OUs

Right-clicking **inside** the new `CORP` OU (placement is determined entirely by where you right-click), created five children: `Users`, `Groups`, `Workstations`, `Servers`, `Admins` — then three department OUs (`IT`, `HR`, `Sales`) nested under `CORP\Users`.

> **Note:** an OU named `Users` coexists fine with the default `Users` container. They are different object classes at different paths — `OU=Users,OU=CORP,DC=corp,DC=lab` vs `CN=Users,DC=corp,DC=lab`. AD addresses objects by distinguished name, not display name.

📸 `07-04-ou-structure-complete.png` — full tree expanded; every object under CORP reports Type = Organizational Unit

### 4. Move CLIENT01 into OU=Workstations

CLIENT01 had landed in the default `Computers` container at domain join (Stage 6) — meaning no OU-linked GPO could reach it.

Right-click `CLIENT01` → **Move…** → `CORP\Workstations`. (Move was chosen over drag-and-drop to eliminate mis-drop risk.)

The move is non-destructive: the computer object's **distinguished name changes, but its identity (SID) and domain membership do not**. The client requires no action and notices nothing.

📸 `07-05-client01-moved-to-workstations.png` — CLIENT01 resident in the Workstations OU
📸 `07-06-computers-container-empty.png` — the default Computers container now empty, confirming the move

---

## Verification

- All created objects report **Type = Organizational Unit** in ADUC (not Container)
- `IT` / `HR` / `Sales` correctly nested under `CORP\Users`, not at the CORP level
- CLIENT01 present in `CORP\Workstations`; default `Computers` container empty
- Post-Windows-Update re-verification: full OU tree and CLIENT01 placement intact after patching and reboot (expected — updates do not touch directory objects — but verified rather than assumed)

---

## Snapshot

Interim snapshot **`04b-ou-structure`** taken with DC01 powered off, before applying Windows updates. Rationale: Stage 8 introduces bulk user provisioning via PowerShell/CSV — the most likely point so far to need a rollback — so the clean OU structure was banked as a known-good restore point first. Patching was performed *after* the snapshot so any update failure could be reverted to the pre-patch state.

---

## Key takeaways

1. **Default containers cannot hold Group Policy links.** Objects must live in real OUs to be targetable — this is the root cause behind a class of "why isn't my GPO applying" tickets.
2. **OU design is policy design.** The tree wasn't organized for tidiness; each OU exists because something will be linked to or delegated at that boundary.
3. **Deletion protection is free insurance.** Left enabled on every OU created.
4. **Snapshot before risk, patch after snapshot.** Ordering maintenance operations around known-good restore points is the same discipline as production change management.

**Next stage:** Stage 8 — Users & Groups (GUI user creation, the AGDLP group model, and bulk provisioning from CSV with PowerShell).
