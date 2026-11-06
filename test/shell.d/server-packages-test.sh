#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

server_packages="$ROOT/install/omarchy-server.packages"

[[ -f $server_packages ]] || fail "the server package list is shipped"

# The ISO builder only skips whole-line comments and blank lines.
inline=$(grep -E '^[^#].*#' "$server_packages" || true)
[[ -z $inline ]] || fail "the server list has no inline comments" "$inline"
pass "the server list has no inline comments"

mapfile -t packages < <(grep -v '^#\|^$' "$server_packages")
[[ ${#packages[@]} -gt 0 ]] || fail "the server package list is not empty"

duplicates=$(printf '%s\n' "${packages[@]}" | sort | uniq -d)
[[ -z $duplicates ]] || fail "the server list has no duplicates" "$duplicates"
pass "the server list has no duplicates"

# A headless image that pulls in a compositor, a login manager, or a browser has
# failed at the one thing it exists to do.
for package in hyprland quickshell sddm uwsm chromium nautilus plymouth \
  wireplumber bluez cups xdg-desktop-portal-hyprland; do
  ! printf '%s\n' "${packages[@]}" | grep -Fxq "$package" ||
    fail "the server list ships no desktop stack" "$package is present"
done
pass "the server list ships no compositor, shell, login manager, or GUI stack"

# Remote LUKS unlock is opt-in: omarchy-server-remote-unlock installs its own packages.
for package in mkinitcpio-dropbear mkinitcpio-netconf mkinitcpio-utils; do
  ! printf '%s\n' "${packages[@]}" | grep -Fxq "$package" ||
    fail "remote LUKS unlock packages are not in the default list" "$package is present"
done
pass "remote LUKS unlock packages are not in the default list"

# What the image needs to install, be reached, update, and recover.
for package in networkmanager ufw rsync docker lazydocker lazyjournal tmux git gum \
  nvim yay mise-bin pacman-contrib; do
  printf '%s\n' "${packages[@]}" | grep -Fxq "$package" ||
    fail "the server list keeps the access, update, and menu essentials" "$package is missing"
done
pass "the server list keeps the access, update, and menu essentials"
