#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home" "$test_tmp/home/.hermes/profiles/james"

export OMARCHY_EDITION_FILE="$test_tmp/edition"
printf 'desktop\n' >"$OMARCHY_EDITION_FILE"

for command in xdg-user-dirs-update xdg-settings xdg-mime update-desktop-database; do
  printf '#!/bin/bash\nprintf "%%s %%s\\n" "${0##*/}" "$*" >>"$TEST_COMMAND_LOG"\n' >"$mock_bin/$command"
done
export TEST_COMMAND_LOG=$test_tmp/commands.log
chmod +x "$mock_bin"/*

# Provisioning prepends $OMARCHY_PATH/bin, which shadows a mock for anything
# Omarchy ships, so the install suite is stubbed out at its path instead. The
# real one rethemes the session it runs in: hyprctl reload against the live
# compositor, gsettings against the live desktop, and app retints.
mkdir -p "$test_tmp/install/user"
: >"$test_tmp/install/user/all.sh"

HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$test_tmp/install" bash "$ROOT/bin/omarchy-provision-user" >/dev/null ||
  fail "omarchy-provision-user finishes"

for skill in omarchy diagnose-crash; do
  link="$test_tmp/home/.gemini/config/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "omarchy-provision-user provisions the $skill skill for Antigravity"

  link="$test_tmp/home/.hermes/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "omarchy-provision-user provisions the $skill skill for Hermes"

  link="$test_tmp/home/.hermes/profiles/james/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "omarchy-provision-user provisions the $skill skill for a Hermes profile"
done

pass "omarchy-provision-user provisions Antigravity and Hermes skills"

for dir in DOWNLOAD:Downloads PICTURES:Pictures VIDEOS:Videos DOCUMENTS:Documents MUSIC:Music; do
  grep -qxF "xdg-user-dirs-update --set ${dir%%:*} $test_tmp/home/${dir#*:}" "$TEST_COMMAND_LOG" ||
    fail "provisioning names the ${dir%%:*} folder in English" "$(cat "$TEST_COMMAND_LOG")"
done
for dir in Downloads Pictures Videos Documents Music; do
  [[ -d $test_tmp/home/$dir ]] || fail "provisioning creates the $dir folder it names"
done
pass "provisioning names the user folders in English before a first login in another language"

: >"$TEST_COMMAND_LOG"
mkdir -p "$test_tmp/home/.config"
printf 'XDG_DOWNLOAD_DIR="$HOME/下载"\n' >"$test_tmp/home/.config/user-dirs.dirs"
HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$test_tmp/install" bash "$ROOT/bin/omarchy-provision-user" --force >/dev/null ||
  fail "omarchy-provision-user finishes again"
! grep -q -- '--set DOWNLOAD ' "$TEST_COMMAND_LOG" || fail "provisioning keeps a folder the user already named"
grep -q -- '--set PICTURES ' "$TEST_COMMAND_LOG" || fail "provisioning still names the folders the user has not"
pass "provisioning keeps a folder the user already named, in any language"

# Run the real setup leaves, replacing commands that touch hardware or a session.
runtime="$test_tmp/runtime"
mkdir -p "$runtime/bin"
ln -s "$ROOT/bin/"* "$runtime/bin/"
for asset in default themes migrations; do
  ln -s "$ROOT/$asset" "$runtime/$asset"
done
export OMARCHY_ISSUE_FILE="$test_tmp/issue"
export OMARCHY_USER_NAME="Test User" OMARCHY_USER_EMAIL="test@example.com"
for command in mise omarchy-install-chromium-copy-url omarchy-install-chromium-ytdlp \
  omarchy-input-method omarchy-install-camera omarchy-install-video-decode \
  omarchy-display-text-size omarchy-refresh-applications omarchy-shell pactl amixer alsactl sudo busctl \
  omarchy-restart-terminal omarchy-theme-set-foot omarchy-theme-set-tmux omarchy-restart-btop \
  omarchy-restart-opencode omarchy-restart-helix omarchy-theme-set-hunk omarchy-restart-hyprctl \
  omarchy-theme-set-gnome omarchy-theme-set-claude omarchy-theme-set-hermes omarchy-theme-set-t3code \
  omarchy-theme-set-herdr-app omarchy-theme-set-slack omarchy-theme-set-browser omarchy-theme-set-vscode \
  omarchy-theme-set-obsidian omarchy-theme-set-keyboard omarchy-theme-bg-cache omarchy-theme-set-herdr-machines; do
  rm -f "$runtime/bin/$command"
  cat >"$runtime/bin/$command" <<'STUB'
#!/bin/bash
[[ ${0##*/} != "mise" || $MISE_OFFLINE == "true" ]] || exit 1
printf '%s %s\n' "${0##*/}" "$*" >>"$TEST_COMMAND_LOG"
STUB
  chmod +x "$runtime/bin/$command"
done
for command in omarchy-hw-asus-rog omarchy-hw-match omarchy-hw-vm; do
  rm "$runtime/bin/$command"
  printf '#!/bin/bash\nexit 0\n' >"$runtime/bin/$command"
  chmod +x "$runtime/bin/$command"
done
# Keep desktop retints out of the session; server theme staging stays real.
rm "$runtime/bin/omarchy-theme-set"
cat >"$runtime/bin/omarchy-theme-set" <<'STUB'
#!/bin/bash
if omarchy-edition-server; then
  exec "$ROOT/bin/omarchy-theme-set" "$@"
else
  printf 'desktop-theme %s %s\n' "${OMARCHY_THEME_HEADLESS:-0}" "$*" >>"$TEST_COMMAND_LOG"
fi
STUB
chmod +x "$runtime/bin/omarchy-theme-set"

fake_platform "$test_tmp/platform" aarch64-apple
ln -s "$test_tmp/platform/bin/uname" "$mock_bin/uname"
export OMARCHY_PROC_ROOT="$test_tmp/platform/proc"
export OMARCHY_SYS_ROOT="$test_tmp/platform/sys"
export OMARCHY_LIFECYCLE_ROOT="$test_tmp/lifecycle"
mkdir -p "$OMARCHY_SYS_ROOT" "$OMARCHY_LIFECYCLE_ROOT/usr/lib/omarchy/mac"
printf '#!/bin/bash\necho platform-user >>"%s"\n' "$TEST_COMMAND_LOG" >"$OMARCHY_LIFECYCLE_ROOT/usr/lib/omarchy/mac/setup-user"
chmod +x "$OMARCHY_LIFECYCLE_ROOT/usr/lib/omarchy/mac/setup-user"

for edition in server desktop; do
  printf '%s\n' "$edition" >"$OMARCHY_EDITION_FILE"
  home="$test_tmp/$edition-home"
  mkdir -p "$home"
  : >"$TEST_COMMAND_LOG"
  # Desktop uses a preseeded theme so its activation helpers read real configs.
  if [[ $edition == "desktop" ]]; then
    mkdir -p "$home/.local/state/omarchy/current/theme"
    printf '{}\n' >"$home/.local/state/omarchy/current/theme/pi.json"
  fi
  args=()
  [[ $edition != "desktop" ]] || args=(--first-install)
  HOME="$home" PATH="$mock_bin:$runtime/bin:$PATH" OMARCHY_PATH="$runtime" \
    OMARCHY_INSTALL="$ROOT/install" OMARCHY_THEME_WAIT=1 bash "$ROOT/bin/omarchy-provision-user" "${args[@]}" ||
    fail "$edition provisioning runs the real setup leaves"
  [[ -d $home/Work/tries && -f $home/.local/state/omarchy/done/finalize-user ]] ||
    fail "$edition provisioning keeps work directories and completion tracking"
  grep -qxF 'mise reshim --system' "$TEST_COMMAND_LOG" && grep -qxF 'mise reshim' "$TEST_COMMAND_LOG" ||
    fail "$edition provisioning builds system and user mise shims"
  grep -qxF platform-user "$TEST_COMMAND_LOG" || fail "$edition provisioning runs the registered platform user hook"
  [[ -L $home/.agents/skills/omarchy ]] || fail "$edition provisioning keeps agent skills"
  if [[ $edition == "server" ]]; then
    [[ $(cat "$home/.local/state/omarchy/current/theme.name") == "tokyo-night" && -s $OMARCHY_ISSUE_FILE ]] ||
      fail "server provisioning seeds the terminal palette and console banner"
    [[ -s $home/.pi/agent/themes/omarchy-system.json && -f $home/.pi/agent/settings.json && -f $home/.config/btop/themes/current.theme ]] ||
      fail "server provisioning activates Pi and btop themes"
    for path in .XCompose .config/fcitx5 .local/share/fcitx5 .local/share/keyrings .config/gtk-3.0 Downloads .local/state/omarchy/toggles/hypr; do
      [[ ! -e $home/$path ]] || fail "server provisioning creates no desktop state: $path"
    done
    ! grep -Eq '^(xdg-|update-desktop-database|omarchy-(install-|input-method|display-text-size|refresh-applications|shell |restart-|theme-set-)|pactl |amixer |alsactl |sudo |busctl )' "$TEST_COMMAND_LOG" ||
      fail "server provisioning invokes no desktop commands" "$(cat "$TEST_COMMAND_LOG")"
    printf 'chosen-theme\n' >"$home/.local/state/omarchy/current/theme.name"
    HOME="$home" PATH="$mock_bin:$runtime/bin:$PATH" OMARCHY_PATH="$runtime" \
      OMARCHY_INSTALL="$ROOT/install" OMARCHY_THEME_WAIT=1 bash "$ROOT/bin/omarchy-provision-user" --force --first-install ||
      fail "server provisioning can repeat during owner setup"
    [[ $(cat "$home/.local/state/omarchy/current/theme.name") == "chosen-theme" ]] ||
      fail "repeated provisioning keeps the user's theme"
    for migration in "$ROOT"/migrations/*.sh; do
      [[ -f $home/.local/state/omarchy/migrations/${migration##*/} ]] || fail "server first-install marks shipped migrations complete"
    done
  else
    [[ -s $home/.XCompose && -s $home/.local/share/keyrings/Default_keyring.keyring && -f $home/.local/state/omarchy/toggles/hypr/no-animations.lua ]] ||
      fail "desktop provisioning keeps compose, keyring and VM setup"
    [[ -f $home/.config/fcitx5/conf/classicui.conf && -d $home/Downloads ]] ||
      fail "desktop provisioning keeps input themes and user folders"
    for call in 'desktop-theme 1 Tokyo Night' 'omarchy-install-camera ' 'omarchy-install-video-decode ' 'omarchy-display-text-size 11' 'omarchy-input-method configure --seed'; do
      grep -qxF "$call" "$TEST_COMMAND_LOG" || fail "desktop provisioning keeps $call"
    done
  fi
  pass "$edition provisioning retains its setup without leaking desktop work into servers"
done
