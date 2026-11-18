# Stage 6 — Build & Join the Client (CLIENT01)

**Objective:** Create a Windows 11 Pro workstation (CLIENT01), confirm it receives a
DHCP lease and DNS from DC01, and join it to the `corp.lab` domain.

**Result:** CLIENT01 received lease `10.10.10.100` from DC01, resolved `corp.lab`,
and joined the domain successfully — confirmed from both the client and the domain
controller. A multi-layer VirtualBox/Hyper-V boot-and-display conflict was diagnosed
and resolved along the way (documented separately below).

---

## Configuration

| Setting | Value |
| --- | --- |
| VM name | CLIENT01 |
| OS | Windows 11 Pro (Pro required — Home cannot domain-join) |
| RAM | 4096 MB |
| vCPU | **4** (changed from 2 — see Troubleshooting) |
| Disk | 60 GB dynamically allocated |
| Firmware | UEFI, TPM 2.0, Secure Boot disabled (lab convenience) |
| Network | VirtualBox NAT Network `LabNet` |
| DHCP lease received | `10.10.10.100` (from scope `10.10.10.100–200`) |
| DNS | `10.10.10.10` (DC01) |
| Domain | `corp.lab` (NetBIOS `CORP`) |

---

## Build Walkthrough

### 1. Create and install CLIENT01
Created the VM attached to `LabNet`, selected **Windows 11 Pro** explicitly (the
installer defaults to Home, which cannot join a domain). Installed Windows 11 from the
mounted ISO.

![Both VMs in VirtualBox Manager](screenshots/stage6/06-01-both-vms-in-manager.png)
*DC01 and CLIENT01 both present and attached to the isolated LabNet network.*

![Network adapter on LabNet](screenshots/stage6/06-02-network-labnet-attached.png)
*CLIENT01 Adapter 1 attached to NAT Network LabNet — the single most important setting
for the client to reach DC01's DHCP and DNS.*

![Windows 11 setup](screenshots/stage6/06-03-windows-setup-language.png)
*Windows 11 Setup language screen.*

![Installing Windows](screenshots/stage6/06-04-installing-windows-progress.png)
*Windows 11 installation in progress.*

### 2. Bypass the Microsoft account requirement
Windows 11 Pro OOBE forces an online Microsoft account by default. For a domain
workstation this is the wrong identity model — domain machines authenticate against
Active Directory, not a Microsoft cloud account. Bypassed it to create a clean local
account.

At the **"Let's connect you to a network"** screen, opened a command prompt with
**Shift + F10** and ran:

```
start ms-cxh:localonly
```

This surfaces the hidden **"Create a user for this PC"** local-account form. Created a
temporary local admin (`labadmin`) used only for the setup and domain-join steps.

![OOBE network screen](screenshots/stage6/06-05-oobe-network-screen.png)
*The "Let's connect you to a network" screen — the point at which the bypass is invoked.*

![Local account creation](screenshots/stage6/06-06-oobe-local-account-creation.png)
*Local account form surfaced by the bypass — no Microsoft account required.*

![First desktop](screenshots/stage6/06-07-windows11-desktop-first-boot.png)
*Windows 11 desktop, local account, first boot complete.*

> **Concept — three authentication contexts.** The local `labadmin` account is validated
> by CLIENT01's own SAM. The domain `CORP\Administrator` account is validated by Active
> Directory on DC01. The DSRM password (set during DC promotion) is validated by the DC's
> local SAM and used only to repair AD offline. Knowing which credential lives where is a
> common source of "I can't log in" help desk tickets.

### 3. Confirm addressing (proves the Stage 5 DHCP scope works)
With DC01 running, ran `ipconfig /release` / `/renew` / `/all` on CLIENT01.

```
IPv4 Address. . . . . . . . . . . : 10.10.10.100 (Preferred)
Subnet Mask . . . . . . . . . . . : 255.255.255.0
Default Gateway . . . . . . . . . : 10.10.10.1
DHCP Server . . . . . . . . . . . : 10.10.10.10
DNS Servers . . . . . . . . . . . : 10.10.10.10
Connection-specific DNS Suffix  . : corp.lab
```

This confirms DORA completed (Discover → Offer → Request → Acknowledge) and that the
scope handed out the correct router, DNS, and domain-name options.

![DHCP lease](screenshots/stage6/06-08-ipconfig-dhcp-lease.png)
*CLIENT01 received 10.10.10.100 from DC01 with correct DNS (10.10.10.10) and corp.lab
suffix — the Stage 5 scope verified end to end.*

> **Gotcha caught during this step.** The first `ipconfig /all` returned a `169.254.x.x`
> APIPA address with no gateway — the classic "no DHCP reached" symptom. Root cause: DC01
> was not running. Started DC01 first, waited for services to initialize, then renewed.
> This is Golden Rule #5: **start the domain controller first, always.**

### 4. Verify DNS resolution
```
ping corp.lab
Pinging corp.lab [10.10.10.10] with 32 bytes of data:
Reply from 10.10.10.10: ... (0% loss)
```

The bracketed `[10.10.10.10]` confirms DNS resolved the domain name *before* the ping —
the #1 prerequisite for a successful domain join (Golden Rule #2: DNS is ~80% of AD
problems).

![Ping corp.lab](screenshots/stage6/06-09-ping-corp-lab.png)
*DNS resolves corp.lab to DC01 and the client can reach it.*

### 5. Join the domain
```powershell
Add-Computer -DomainName 'corp.lab' -NewName 'CLIENT01' `
  -Credential (Get-Credential CORP\Administrator) -Restart
```

Authenticated with the **domain** `CORP\Administrator` credential (not the local account).
The machine renamed itself to CLIENT01, joined the domain, and rebooted.

### 6. Verify the join (both sides)
**Client side:**
```
systeminfo | findstr /B /C:"Domain"
Domain:    corp.lab

hostname
CLIENT01
```

![Client-side verification](screenshots/stage6/06-12-domain-join-verification.png)
*CLIENT01 reports Domain: corp.lab and the correct hostname.*

**Domain controller side (authoritative):**
On DC01, `Active Directory Users and Computers → corp.lab → Computers` shows CLIENT01 as
a Computer object.

![CLIENT01 in ADUC](screenshots/stage6/06-13-client01-in-aduc.png)
*CLIENT01 visible as a domain member in Active Directory on DC01 — the domain is live.*

> CLIENT01 lands in the default **Computers** container at this stage. It will be moved
> into `OU=Workstations` in Stage 7, once the OU structure exists.

### 7. Snapshot
Powered off both VMs and took the `04-client-joined` snapshot on each. Both halves of the
domain trust are stateful, so both VMs are snapshotted at the same known-good moment to
keep them in sync.

![Snapshot 04-client-joined](screenshots/stage6/06-14-snapshot-04-client-joined.png)
*Snapshot tree showing the full build progression through 04-client-joined.*

---

## Troubleshooting Case Study — VirtualBox / Hyper-V Boot & Display Conflict

**Environment:** VirtualBox 7.2.x on a Windows 11 Home host with the
`VirtualMachinePlatform` feature enabled.

### Symptom
A freshly created CLIENT01 VM hung at a black screen on first boot — no UEFI prompt, no
"Press any key to boot from CD," no error. After this was worked past and Windows
installed, a *second* black screen appeared at the OOBE phase: the guest was clearly
running (VirtualBox reported mouse/keyboard integration) but the display would not paint.

![Symptom — black screen](screenshots/stage6/Troubleshooting/01-symptom-black-screen.png)

### Investigation (isolation, simplest causes first)
1. **Ruled out a corrupt ISO** — mounted the Windows 11 ISO directly in the host; it
   mounted cleanly and contained a valid installer structure (`boot`, `efi`, `sources`,
   bootloaders). File integrity confirmed.
2. **Verified the VM storage attachment** with `VBoxManage showvminfo` — the ISO was
   correctly attached. Also tested moving the optical drive from SATA to a new IDE
   controller via `VBoxManage` to rule out a controller issue. No change.
3. **Recreated the VM** with a fresh NVRAM and Secure Boot disabled to rule out corrupted
   EFI boot variables. No change.
4. **Checked the host** for a hypervisor conflict.

![ISO mount verification](screenshots/stage6/Troubleshooting/02-iso-mount-verification.png)
![VBoxManage storage config](screenshots/stage6/Troubleshooting/03-vboxmanage-storage-config.png)
![VirtualBox version](screenshots/stage6/Troubleshooting/04-virtualbox-version.png)

### Root cause
`Get-WindowsOptionalFeature` showed **VirtualMachinePlatform: Enabled** on the host. That
feature forces VirtualBox to run on top of Microsoft's Hyper-V platform (WHPX/NEM
compatibility mode) instead of taking direct control of hardware virtualization. In that
mode, VirtualBox 7.2 has known regressions affecting Windows 11 guests — including a boot
hang at the default 2 vCPU and unreliable display rendering.

![VirtualMachinePlatform enabled](screenshots/stage6/Troubleshooting/05-hyperv-platform-enabled.png)

### Security tradeoff evaluated before remediation
Confirmed that **HVCI / Memory Integrity** was actively running on the host before
disabling anything:

```
Get-CimInstance Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard
SecurityServicesRunning : {2, 7}        # 2 = HVCI, 7 = SMM firmware protection
VirtualizationBasedSecurityStatus : 2   # VBS running
```

So disabling `VirtualMachinePlatform` would turn off real, active protections — not
dormant ones. This made it a genuine **risk-acceptance** decision rather than a free
change.

![DeviceGuard status](screenshots/stage6/Troubleshooting/06-deviceguard-hvci-active.png)

### Resolution
- **Boot hang:** increased CLIENT01 vCPU from **2 → 4**, which cleared the known 2-vCPU
  boot regression. Windows installed normally.
- **OOBE display hang:** the CPU change alone did not fix display rendering in
  compatibility mode, so disabled the hypervisor at the host level:
  ```powershell
  Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
  bcdedit /set hypervisorlaunchtype off
  # reboot host
  ```
  After the host reboot, VirtualBox regained direct hardware virtualization access and
  OOBE rendered correctly.

![CPU set to 4](screenshots/stage6/Troubleshooting/07-cpu-4-setting.png)

### Risk management note
The loss of HVCI/Memory Integrity was accepted as a **time-bounded** trade for the lab
build period (~2 weeks), with compensating controls left intact (Windows Defender,
firewall, and Windows Update remained on; lab VMs are isolated on a NAT network). A
re-enable step is scheduled and documented:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
bcdedit /set hypervisorlaunchtype auto
# reboot host, then verify SecurityServicesRunning returns {2, 7}
```

The distinction matters: a control disabled for a defined window *with* compensating
controls and a documented reversal plan is **managed risk**; the same control disabled
indefinitely with no plan is negligence. Same action, very different risk posture.

---

## Skills Demonstrated
- Built and domain-joined a Windows 11 Pro workstation in an Active Directory environment.
- Verified DHCP/DNS delivery end to end and interpreted `ipconfig`, `ping`, and
  `systeminfo` output to confirm correct addressing and domain membership.
- Diagnosed an obscure hypervisor compatibility issue through systematic isolation
  (ruling out media, VM config, firmware state) before identifying the host-level cause.
- Used `VBoxManage` and PowerShell DISM tooling for configuration inspection and change.
- Evaluated and documented a security control tradeoff (HVCI/VBS) as a time-bounded,
  reversible risk-acceptance decision with compensating controls.

## Stage 6 Checklist
- [x] CLIENT01 created (Windows 11 **Pro**) and attached to LabNet
- [x] Windows 11 installed; Microsoft-account requirement bypassed to a local account
- [x] DHCP lease `10.10.10.100` received from DC01 with DNS `10.10.10.10`
- [x] `corp.lab` resolves and is reachable
- [x] CLIENT01 joined to `corp.lab`; verified on client and in ADUC
- [x] Snapshot `04-client-joined` taken on **both** VMs
- [ ] (Stage 7) Move CLIENT01 from default Computers container into `OU=Workstations`
- [ ] (Post-lab) Re-enable `VirtualMachinePlatform` to restore HVCI/Memory Integrity
