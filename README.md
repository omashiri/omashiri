# Omashiri

Omashiri is an Arch-based Linux server distribution under development. It borrows selected kernel, boot/UKI, btrfs/snapper, and maintenance infrastructure from [Omarchy](https://github.com/omacom/omarchy), while defining its own headless package selection, defaults, and release process.

The goal is a small system that boots to a console, is administered over SSH, and supports reliable updates and recovery. The first target is a standalone server; small VMs for Recur workspace isolation are a later use.

## Development status

This repository is being reduced from an Omarchy Server Edition starting point. It still contains inherited desktop code and configuration. A positive server package manifest and initial headless provisioning/update guards are implemented, but the complete package dependency closure and installed payload have not been validated as desktop-free.

The first Omashiri ISO and the full install → SSH → update → reboot → recovery flow have not been validated. Remote LUKS unlock is experimental and opt-in; it has not been proven through an encrypted boot. There are no production installation instructions yet.

Remaining release work includes secure first-boot access, independent runtime packaging and signing, package/channel ownership, server-only ISO composition, and measured disk/memory use. Follow the [first-release tracker](https://github.com/omashiri/omashiri/issues/4) for implementation and acceptance criteria.

## Repositories

| Repository | Role |
| --- | --- |
| [omashiri](https://github.com/omashiri/omashiri) | Server package selection, target-side setup, defaults, and maintenance commands |
| [omashiri-iso](https://github.com/omashiri/omashiri-iso) | ISO composition and disk installation orchestration |
| [omashiri-pkgs](https://github.com/omashiri/omashiri-pkgs) | Build recipes and publication for required custom packages |

Arch supplies the base package ecosystem. Omashiri is responsible for its own releases and support decisions. The installer and ISO repositories retain their Omarchy fork relationships to make upstream comparison and selected imports easier. Upstream changes are reviewed and tested before inclusion; a moving Omarchy branch is not an Omashiri release channel.

Existing `omarchy-*` commands and `OMARCHY_*` identifiers remain during the transition. Broad renaming follows a working, validated server image.

## Project documentation

- [Server image specification](plans/omashiri.md): scope, work sequence, and completion criteria.
- [Upstream integration policy](docs/omashiri-upstream.md): retained components, provenance, import procedure, and release boundaries.
- [Testing reference](docs/testing.md): focused checks, companion repositories, and VM/acceptance suites.
- [Contributor instructions](AGENTS.md): repository conventions and task guides.

The existing [manual](manual/) describes upstream Omarchy, primarily its desktop experience. It is retained as upstream material and is not an Omashiri server installation guide. The earlier [Server Edition plan](plans/server.md) and [edition reference](docs/editions.md) document the inherited implementation; the Omashiri specification defines the intended product.

## Development checks

Use Linux with Bash 5 and the dependencies required by the selected tests. Run focused checks for the area being changed and retain their complete output, for example:

```bash
bash test/shell.d/platform-packages-test.sh >/tmp/platform-packages.log 2>&1
cat /tmp/platform-packages.log
```

Passing shell tests does not replace installing and booting the ISO in a disposable VM or validating updates and recovery.

## License and attribution

Released under the [MIT License](LICENSE). Omashiri derives from Omarchy by David Heinemeier Hansson and its contributors; the upstream copyright and license are preserved.
