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

<<<<<<< HEAD
=======
## The front door

The server edition greets a login the way a bulletin board did. Three surfaces, one palette:

| Command | Draws |
| --- | --- |
| `omarchy-server-palette` | Translates the active theme into shell-sourceable ANSI escapes. `eval "$(omarchy-server-palette)"` puts `$OMARCHY_BBS_ACCENT` and friends in scope. |
| `omarchy-server-issue` | Renders `/etc/issue`, the pre-login banner agetty draws on the console. |

The palette names roles, not colors, so a theme can move a hue without every renderer following it: `ACCENT FG DIM RULE BRIGHT TITLE KEY OK WARN INFO ALERT ACCENT_BG SELECTION_BG ON_ACCENT`, plus `RESET` and `BOLD`.

Two axes degrade independently, because they fail differently. **Color depth** falls from truecolor to 16 SGR codes, and an SGR parameter a terminal cannot render is ignored or approximated rather than printed. **Glyphs** fall from box drawing to ASCII, signalled by `$OMARCHY_BBS_UNICODE`, because a console font missing box characters substitutes them and wrecks the alignment. `TERM=linux` gets both floors.

`omarchy-server-issue` is called by `omarchy-theme-set`, so switching themes restyles the banner. On the desktop edition it does nothing, which is why that call needs no guard around it - except that a machine which was a server long enough to get a banner has its stock `/etc/issue` restored from the copy kept beside it. The marker is writable, and a desktop should not keep greeting people as a server. It leaves agetty's own escapes in the file (`\n` nodename, `\4` IPv4, `\l` tty) so the hostname and address stay correct without anything regenerating them.

>>>>>>> 7fb169de0 (Restore the stock banner when a machine stops being a server)
## Gating rules

**New migrations that touch a compositor, the shell, or GUI config must gate on the edition.** A migration that restarts Hyprland or rewrites a Quickshell config has nothing to do on a server, and running it there is at best noise.

```bash
omarchy-edition-desktop || exit 0
```

Existing migrations need no retrofit. The `omarchy` package seeds `/etc/skel/.local/state/omarchy/migrations` with a marker for every migration in the build, so a user created during a fresh install starts with all of them already marked. Historical migrations never run on a machine installed after they shipped, server or desktop.

**Refresh commands** that copy a GUI config into `~/.config` should gate the same way.

**Do not gate** anything the two editions share: pacman, snapper, the update pipeline, the CLI, or the terminal side of a theme. One update pipeline, two editions.
