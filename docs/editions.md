# Editions

Omarchy ships two editions from one repo. The desktop edition is the historical one: Hyprland, the Quickshell shell, GUI applications. The server edition is headless: a getty on the console, SSH as the primary access, and no compositor.

The edition is chosen at install time and never toggled afterwards. Uninstalling a GUI stack in place is a migration minefield in both directions, so changing your mind is a reinstall.

## The marker

`/etc/omarchy-edition` holds one word, `desktop` or `server`. The installer writes it. Nothing else should.

A missing marker reads as `desktop`. Every install that predates editions is a desktop, so defaulting keeps the predicates answerable on machines the installer never stamped.

## Reading it

```bash
omarchy edition                 # prints desktop or server
```

For scripts, use the predicates. They print nothing and answer with an exit code, in the `hw-` tradition:

```bash
if omarchy-edition-server; then
  ...
fi

omarchy-edition-desktop || exit 0
```

An unrecognized marker fails loudly: `omarchy-edition` exits non-zero and both predicates stay false, rather than guessing an edition for a half-configured machine.

`omarchy-edition-set <desktop|server>` writes the marker. It escalates with `sudo` only when the target needs it, so the installer can call it as root from the ISO chroot where there is no terminal to answer a password prompt in.

## Package lists

| File | Edition |
| --- | --- |
| `install/omarchy-base.packages` | desktop |
| `install/omarchy-server.packages` | server |

The server list is derived from the base list by subtraction, plus two additions that the base list cannot supply (`openssh`, `rsync`). `test/shell.d/server-packages-test.sh` enforces that shape: anything in the server list that is neither in the base list nor a declared addition fails the suite.

Commands that install the default package set pick their list from the edition. `omarchy-reinstall-pkgs` is the example to copy.

## Gating rules

**New migrations that touch a compositor, the shell, or GUI config must gate on the edition.** A migration that restarts Hyprland or rewrites a Quickshell config has nothing to do on a server, and running it there is at best noise.

```bash
omarchy-edition-desktop || exit 0
```

Existing migrations need no retrofit. The `omarchy` package seeds `/etc/skel/.local/state/omarchy/migrations` with a marker for every migration in the build, so a user created during a fresh install starts with all of them already marked. Historical migrations never run on a machine installed after they shipped, server or desktop.

**Refresh commands** that copy a GUI config into `~/.config` should gate the same way.

**Do not gate** anything the two editions share: pacman, snapper, the update pipeline, the CLI, or the terminal side of a theme. One update pipeline, two editions.
