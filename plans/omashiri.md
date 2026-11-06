# Omashiri server image — work spec

Date: 6 November 2026 (Europe/Rome)

Status: direction agreed; slimming and ISO validation remain to be done. The repository layout and PR #3 merge are reported in the project handoff below; remote repository and CI status have not been rechecked for this document.

## Goal

Build a small, opinionated Linux server image that borrows Omarchy's kernel, boot/UKI integration, btrfs and snapper, update and package machinery, and SSH setup. Define what the server installs with a short positive package list, rather than deriving it by subtracting desktop packages.

The first intended host is the server at omashiri.com. Later, Omashiri can provide small VMs for Recur workspace and agent isolation. Those VMs use a glibc userland and do not run the Recur desktop.

The first deliverable is a bootable ISO that installs a headless system, permits SSH access after first boot, and supports updates and rollback.

## Scope and upstream relationship

Omashiri is an independent Arch-based distribution. The [distro tracker](https://github.com/omashiri/omashiri/issues/4) sequences implementation, and the [upstream policy](../docs/omashiri-upstream.md) defines selective imports and release boundaries. Leave `sysrex/server-edition-plan-fixes`, the source branch for upstream PR #17279, untouched; use separate branches from `quattro` for distro work.

Omashiri has its own server product definition. The existing [Server Edition plan](server.md) and [edition implementation](../docs/editions.md) describe the starting point, including features that may be removed during slimming.

Keep `omashiri/omashiri` and `omashiri/omashiri-iso` in their upstream fork networks. Pull or cherry-pick useful kernel, boot, filesystem, and pipeline fixes from upstream. Record the upstream source revision when borrowing changes so later updates can be reviewed.

Treat the official Omarchy repositories as upstream sources. Do not inherit their whole desktop package catalog or use the upstream Server Edition roadmap as Omashiri's scope.

## Repository responsibilities

The following repository arrangement was reported in the handoff on 6 November 2026:

| Repository | Responsibility | Required relationship |
| --- | --- | --- |
| `omashiri/omashiri` | Installer, installed package selection, server defaults, and maintenance commands; default branch `quattro` | Remain a fork of `omacom/omarchy` |
| `omashiri/omashiri-iso` | ISO composition and build; default branch `quattro` | Remain a fork of `omacom/omarchy-iso` |
| `omashiri/omashiri-pkgs` | Build recipes and publishing for packages Omashiri actually needs; default branch `main` | New empty standalone repository; clean slate |
| `sysrex/omarchy-pkgs` | Personal upstream package contributions | Remain the personal fork of `omacom/omarchy-pkgs` |

Do not move the personal package fork again or copy its contribution branches into the clean package repository. The handoff reports these upstream PRs back on the personal fork:

- `omacom/omarchy-pkgs#2193`: Add recur bin.
- `omacom/omarchy-pkgs#2201`: Add OpenLogi binary package.
- `omacom/omarchy-pkgs#2202`: Update herdr to 0.9.5.
- `omacom/omarchy-pkgs#2204`: Leave Grok Bot updates to pacman by default.

The separate Server Edition plan PR, `omacom/omarchy#17279`, was reported as still coming from `omashiri:sysrex/server-edition-plan-fixes`. It is separate from the in-fork PR #3 merge.

## Starting point

The handoff reports PR #3 merged into `quattro` as `fb6a35bb` at 14:05 Europe/Rome. It adds the server edition marker and predicates, a package list formed by removing GUI packages, a BBS login/menu, and optional remote LUKS unlock.

That merge was reported with four failing test files:

- `bin-style-test.sh`
- `image-deferred-hardware-test.sh`
- `privileged-heredoc-test.sh`
- `server-packages-test.sh`

These are historical failures to investigate, not a fresh diagnosis. Reproduce relevant failures on the implementation baseline and fix their causes. Change expectations only where the new product definition changes behavior; preserve security and boot checks.

## Required runtime

- Boot to a console with no compositor, GUI session, browser, desktop portals, or desktop theming applications.
- Install and maintain the kernel, initramfs, UKI, and bootloader through the retained pipeline.
- Use btrfs and snapper for the retained update and rollback workflow.
- Configure networking and SSH so an operator can reach the machine after first boot.
- Keep a working local console and a documented recovery route.
- Run updates without reinstalling desktop packages or requiring a desktop session.
- Measure installed size and idle memory against the current Server Edition baseline. Set a footprint budget from those measurements before calling the image small; no numeric target has been agreed yet.

Retain existing platform names and hardware helpers. Document the first ISO's validated platform and leave other platforms explicitly unvalidated until they are tested.

## Work packages

### 1. Define the package list

Start with an empty selection and add only what is necessary to install, boot, access, update, and recover the first server.

| Group | Include when required |
| --- | --- |
| Base userland | Arch base dependencies, glibc, systemd, pacman, and install/runtime utilities |
| Kernel and boot | Kernel, required firmware, initramfs and UKI tooling, bootloader, and disk setup tools |
| Filesystem and recovery | btrfs tools, snapper, and dependencies of the chosen rollback integration |
| Network and access | Networking, OpenSSH, and the chosen first-boot authentication path |
| Maintenance | Dependencies actually invoked by retained update and package commands |
| Optional host software | Hypervisor, observability, and application services, added explicitly after the first image works |

Keep the authoritative installed package manifest with the installer in `omashiri/omashiri`. In `omashiri-pkgs`, document the small set of custom packages, their upstream sources, and how they are built and published. A package build repository and an installed package manifest have different jobs; keep references aligned without duplicating the full manifest.

Use Arch or an upstream Omarchy package when it is genuinely shared. Package only the custom components needed by Omashiri, and do not copy the upstream catalog wholesale. An empty custom package repository need not block a first ISO if all selected packages already have suitable sources.

Deliverables: a readable manifest, a reason and source for each directly selected package, and a build/publishing decision for any custom packages needed by that manifest.

### 2. Slim the installer and installed system

Trace the selected packages through installation, first boot, updates, migrations, and recovery before removing dependencies.

- Make server package selection independent of the desktop base list.
- Retain the kernel, boot, filesystem, SSH, and maintenance paths required by the manifest.
- Remove desktop setup from the server install path and omit unused desktop assets from the installed payload.
- Audit retained commands for implicit GUI dependencies and environment supplied by the desktop session, including `OMARCHY_PATH`. Provide the required environment for console, SSH, and maintenance services without per-command fallback paths.
- Ensure package reinstallation, updates, and migrations preserve the positive server selection.
- Decide whether to retain the BBS greeting/menu, terminal theming, and remote LUKS unlock. None is a prerequisite merely because PR #3 shipped it.
- If the BBS remains, retain the guards that keep non-interactive SSH, scp, sftp, and rsync silent and unblocked.
- If encrypted root remains, document console unlock and decide whether unattended remote reboot requires the optional initramfs SSH unlock path.

Reuse the existing maintenance machinery where it fits. Avoid a broad rewrite or identifier rename while establishing the first working image.

Deliverables: an install path and installed payload matching the manifest, with focused checks for changed behavior. Replace the desktop-subtraction assumption in `server-packages-test.sh` with checks of the real server package contract.

### 3. Wire the ISO and package sources

- Configure the ISO builder to use `omashiri/omashiri` and an explicit installer ref through `OMARCHY_INSTALLER_REPO` / `OMARCHY_INSTALLER_REF`, if those are still the builder's supported inputs.
- Make the ISO's package selection and offline payload follow the server manifest, rather than carrying a desktop mirror into a headless install.
- Configure package sources, signing and trust, and any custom repository publication needed by the selected packages. Verify that a fresh install and a later update resolve the same intended sources.
- Record the installer revision, ISO builder revision, package sources, and build command with each validation artifact.

Deliverables: a buildable ISO and concise build instructions in the ISO repository. Do not claim an ISO works until it has been booted and used to install a system.

### 4. Validate installation and maintenance

Use a disposable VM for destructive installation and rollback checks. Follow the repository's focused-test rules for code changes; investigate historical failures against the baseline instead of weakening unrelated checks.

Acceptance checks:

1. Build the ISO from the documented revisions and package sources.
2. Boot it and install onto an empty disk with the selected filesystem and boot setup.
3. Reboot into the installed system and confirm networking, console access, and SSH authentication.
4. Confirm the installed package list and enabled services contain no desktop stack.
5. Run a normal update, regenerate boot artifacts where required, and reboot successfully without introducing desktop dependencies.
6. Create and use a snapper recovery point through the retained rollback workflow; verify the recovered system boots and SSH remains usable.
7. If retained, exercise remote LUKS unlock through an actual reboot, including host key persistence and the chosen network configuration.
8. Record installed disk use and idle memory under comparable conditions against the starting Server Edition image.

Deliverables: validation results, measurements, and any remaining platform or hardware limits. Actual deployment on the first host is a separate task.

## Deferred work

After the first validated ISO:

- Decide branding for the edition marker, ISO volume label, MOTD, package names, and `OMARCHY_*` identifiers while preserving a manageable upstream update path.
- Configure DNS, a landing page, and the first machine at omashiri.com when requested.
- Design `recur-base`, `recur-node`, `recur-go`, and `recur-rust` images on top of Omashiri. The intended size is roughly 1 vCPU and 1–2 GB RAM; this is a later workload target, not a validated host footprint.
- Evaluate Incus first for VM management; consider Firecracker only if a concrete need remains.
- Decide workspace sharing through virtio-fs versus cloning inside the VM for untrusted or scheduled work.

## Decisions still open

- Exact direct package selection and the measured footprint budget.
- First validated ISO platform and hardware target.
- Whether the BBS interface, terminal theming, encrypted root, and remote unlock remain.
- First-boot network configuration and SSH key provisioning.
- Custom package build/publishing mechanism, signing, and use of shared upstream repositories.
- Which host services and hypervisor packages become explicit optional additions.

Resolve each decision when its work package needs it. Branding and future Recur images must not block the first headless install.

## Completion criteria

A reviewer can build an ISO from `omashiri/omashiri-iso`, install a system defined by the short manifest in `omashiri/omashiri`, and verify console access, SSH, updates, and snapper rollback. The installed system contains no desktop stack, and its disk and memory measurements meet the agreed budget.

Required checks for the changed paths pass, known baseline failures are documented, and any retained remote unlock flow has been exercised at boot. The two upstream fork relationships remain intact, the custom package repository contains only intentional server packages, and personal upstream package contributions remain on `sysrex/omarchy-pkgs`.
