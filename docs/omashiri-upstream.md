# Omashiri and its upstreams

Omashiri is an independent Arch-based server distribution. Arch provides the base package ecosystem; Omarchy supplies selected implementation work. Omashiri owns its installed package selection, defaults, custom packages, releases, update sources, and support decisions.

The GitHub fork relationship is retained for comparing and exchanging code. It does not make an Omarchy branch or package channel an Omashiri release channel.

The [first-release tracker](https://github.com/omashiri/omashiri/issues/4) and [work spec](../plans/omashiri.md) define the transition. This policy starts [upstream tracking work](https://github.com/omashiri/omashiri/issues/9); it does not claim that runtime source separation is already implemented.

## Branch boundary

`sysrex/server-edition-plan-fixes` is reserved for [upstream PR #17279](https://github.com/omacom/omarchy/pull/17279). Do not delete, rebase, merge distro changes into, or push changes to that branch. Its observed remote head at the start of this work was `413241f5e35c866a7b65aa6cff0f462e3b79f4ef`.

Create Omashiri implementation and import branches from `quattro`. Review and test changes there before integrating them into the Omashiri development line. Do not use the upstream contribution branch as a staging branch for distro work.

## Components to track

These are candidate reuse boundaries, not a promise to keep every implementation currently in those paths. Review their dependencies across the full change before importing anything.

| Component | Upstream source | Local integration points |
| --- | --- | --- |
| Kernel, firmware, boot and UKI integration | Omarchy installer, ISO, and relevant package recipes | Platform package lists, `bin/omarchy-lifecycle-dispatch`, `bin/omarchy-update-boot`, and boot hooks |
| btrfs, snapshots and recovery | Omarchy installer and runtime | `install/config/snapper.sh`, `bin/omarchy-snapshot`, and snapshot/boot integration |
| Package transactions and update safety | Omarchy runtime and package recipes | `bin/omarchy-update*`, package helpers, locking, privilege boundaries, and ALPM hooks |
| Hardware/platform setup | Omarchy installer and platform packages | `bin/omarchy-hw-*`, `install/hardware/`, and platform lifecycle implementations |
| Installation and first-boot access | Omarchy installer and ISO | `bin/omarchy-apply-*`, `install/provisioning/`, network and SSH setup |

Desktop sessions, applications, theming, and their migrations are outside the default import scope. A shared helper can still contain desktop behavior, so a path match alone is insufficient evidence that a change belongs in Omashiri.

Preserve upstream licenses and attribution. Keep local deviations small enough to explain in their implementation issue or commit.

## Initial baseline and provenance

The local starting commit is `8ea1200ef371e2075c4efe14603a5b94b3e04574`, a merge with parents `fb6a35bb4773b51f65697223553930b397b0c4ae` and `d5b32d24d37af8f0376a67d98531bb2da629824b`. Its merge subject identifies the second parent as `omacom:quattro`. This records inherited history, not a completed review of every inherited component.

No independent reviewed-upstream watermark has been established yet. The first audit must establish it and record the installer, ISO, and package-recipe revisions separately. Do not treat the date of a fetch or the latest upstream commit as a completed review.

For each review, record the source repository, previous and new reviewed revisions, imported commit SHAs, local integration commits, skipped changes with reasons, validation results, and unresolved follow-up issues. Keep this record in the upstream review issue and link it from the release notes. A reviewed revision may contain changes intentionally not imported.

## Manual import procedure

Review upstream before each Omashiri release and weekly while actively maintaining the distribution. Triage security, boot, and data-loss fixes promptly rather than waiting for the next routine review. This is an initial maintenance procedure, not a promised response-time SLA.

1. Start from a clean dedicated worktree or checkout. Verify the current branch and preserve any unrelated local work. Create a topic branch from the Omashiri development line.
2. Fetch upstream into a distinct remote. Fetching retrieves objects and refs; do not pull or merge the entire upstream development branch into the release line.
3. Compare the recorded reviewed revision to the fetched revision. Inspect relevant paths first, then the full selected commits and their dependencies, including package recipes and companion ISO changes.
4. Select fixes that apply to retained components. Use `git cherry-pick -x` where suitable to preserve source provenance. If a commit mixes desktop and server work, port only the required change and record the source SHA in the commit and review issue.
5. Review imported migrations individually for dependencies, ordering, already-applied markers, privilege requirements, and headless behavior. Do not replay the upstream desktop migration stream or reset existing completion markers.
6. Run focused checks for the changed logic. Boot, filesystem, package, and provisioning changes also require the relevant disposable-VM checks before release. Record baseline failures separately.
7. Record the reviewed revision and the disposition of relevant changes. Integrate tested imports through normal review, then publish Omashiri packages and images from explicit revisions.

For example, in a clean checkout on an Omashiri topic branch, add the source remote once and fetch its development line:

```bash
git remote add omarchy-upstream https://github.com/omacom/omarchy.git
git fetch omarchy-upstream quattro
```

If that remote already exists, verify its URL and reuse it. Compare against the recorded reviewed SHA rather than relying on a moving branch name as the historical boundary. Apply the same procedure separately to the ISO and selected package sources.

## Runtime updates and release gates

Upstream review happens in development. Installed hosts consume tested Omashiri releases and explicitly selected package sources. A normal host update must not fetch and integrate upstream Omarchy Git changes or switch back to desktop runtime/settings packages.

The inherited implementation still needs work before meeting that contract:

- `bin/omarchy-channel-set` clones `omacom/omarchy` for development channels and selects the Omarchy runtime/settings package pairs.
- `bin/omarchy-update-dev` fast-forwards the active checkout from its configured tracking remote.
- `default/pacman/`, `bin/omarchy-refresh-pacman`, and `bin/omarchy-update-keyring` retain Omarchy package-source and trust assumptions.
- Desktop shell calls in `bin/omarchy-update` are now edition-gated. Its retained tool-update dependencies and the full server update path still require validation against the resolved package closure.
- `.github/workflows/test.yml` uses an upstream desktop VM and upstream package recipes. Passing it does not prove a minimal server transaction or a fresh Omashiri install.

The static audit of committed baseline `8ea1200ef371e2075c4efe14603a5b94b3e04574` also found that package selection alone does not bound the installed system: platform additions and hardware setup can install graphics, recording, and camera components. The package audit must include those paths and the external runtime/settings package dependencies.

Remote access needs explicit integration. At this baseline, target-side service setup does not enable sshd, the firewall opens LocalSend ports rather than establishing SSH access, and owner provisioning copies authorized keys without invoking the existing SSH setup helper. Companion ISO behavior remains unverified. Resolve this through [first-boot work #11](https://github.com/omashiri/omashiri/issues/11), with authenticated access tested through the installed target.

Server updates now require the snapshot command to succeed before changing the checkout or installed packages; absent Snapper also stops the update. Desktop updates retain their optional snapshot behavior. The x86 boot dispatch still does not itself verify boot artifacts, and a successful snapshot command does not prove that recovery boots. Validate both snapshot recovery and the updated boot chain in a disposable VM before release.

Track runtime package ownership in [#12](https://github.com/omashiri/omashiri/issues/12), publishing and trust in [#18](https://github.com/omashiri/omashiri/issues/18), and update/reinstall behavior in [#6](https://github.com/omashiri/omashiri/issues/6). Selected upstream package sources can remain dependencies where intentional and documented; independence does not require rebuilding every Arch package.

## Runtime package boundary

The recipe audit examined upstream `omacom/omarchy-pkgs` at `ceeeebabf593c07f27495b1d1cf775c059f60ab7` and the existing Omashiri package repository through `a62197d4ce14d331168f8529dee07129017ec640`. The latter already contains server/settings, SSH/firewall, boot/kernel, and publication work. Reuse it; the initial empty-repository description is historical.

The next package change is an independent `omashiri-runtime`, matching source pins for the retained defaults in `omashiri-settings`, and a dependency from `omashiri-server`. Upstream runtime packages directly require the desktop stack, and their broad payload must not be copied wholesale with only the dependencies removed.

Retain legacy command paths initially, including `/usr/share/omarchy`, because the security helpers validate that layout. Select the actual command and source-file closure: environment/Bash bootstrap, command libraries and i18n, reviewed setup/migrations, terminal theme inputs, platform boot dispatch, encryption/UKI templates, and snapshot recovery. Retarget the update ALPM guard's package dependency to the new runtime and omit graphical reload hooks. Optional passwordless-sudo grants require their revocation hooks, cleanup, and lifecycle handling together; omit the feature as a whole if it is not retained.

Declare conflicts for overlapping upstream runtime/settings packages without advertising desktop compatibility through `provides=omarchy`. Preserve migration completion state and give every installed file one intentional owner. Version, channel, refresh, reinstall, and keyring commands must recognize the same runtime/settings owners and intended repositories.

Two initialization boundaries require changes before a package build proves a usable image:

- The inherited initramfs baseline includes Plymouth. Adapt the hooks before excluding that package, preserving keyboard, console, encryption, filesystem, and recovery support; verify the provider for `btrfs-overlayfs` as well.
- Existing `omashiri-settings` owns `/etc/snapper/configs/root`, while retained setup creates the root Snapper configuration only when it is absent. Reconcile file ownership with filesystem/subvolume initialization so a preinstalled config cannot accidentally skip required setup.

The audited publisher signs artifacts, but source PGP verification is skipped and recipes without build dependencies can skip dependency checks. A successful publication therefore does not prove source verification or runtime closure. Establish authenticated Omashiri key bootstrap, inspect built `.PKGINFO` and payloads, resolve the full installed transaction, check file ownership without an overwrite bypass, and test signed upgrades before claiming the package boundary is complete. Live repository contents, deployed signing identities, and complete architecture availability were not verified by the recipe audit.

The first release must demonstrate install → authenticated console/SSH → update → reboot → SSH, plus snapper recovery and any retained encrypted-boot flow. Record package closure, source revisions, signatures, artifact checksums, installed size, idle memory, and validated platforms. Until these pass, describe the image as development work rather than a supported server release.
