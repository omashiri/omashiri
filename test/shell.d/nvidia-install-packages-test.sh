#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Stop at the driver transaction, before the setup script writes to /etc.
assert_packages() {
  local description="$1" architecture="$2" driver="$3" expected="$4"
  local actual
  local edition=${5:-desktop}
  actual=$(TEST_ARCH="$architecture" TEST_DRIVER="$driver" \
    TEST_EDITION="$edition" bash -euo pipefail -c '
      omarchy-edition-desktop() { [[ $TEST_EDITION == "desktop" ]]; }
      lspci() { printf "%s\n" "3D controller: NVIDIA Corporation"; }
      omarchy-hw-aarch64-n1x() { return 1; }
      omarchy-hw-x86() { [[ $TEST_ARCH == "x86_64" ]]; }
      omarchy-hw-nvidia-gsp() { [[ $TEST_DRIVER == "gsp" ]]; }
      omarchy-hw-nvidia-without-gsp() { [[ $TEST_DRIVER == "legacy" ]]; }
      omarchy-pkg-add() {
        printf "%s\n" "$*"
        exit 0
      }
      source "$ROOT/install/hardware/nvidia.sh"
    ')
  [[ $actual == "$expected" ]] || fail "$description" "expected: $expected; actual: $actual"
  pass "$description"
}

assert_packages "ARM GSP selection uses native packages" aarch64 gsp \
  'linux-omarchy-nvidia-open nvidia-utils libva-nvidia-driver'
assert_packages "ARM legacy selection omits x86 multilib" aarch64 legacy \
  'nvidia-580xx-dkms nvidia-580xx-utils'
assert_packages "x86 GSP package selection adds multilib" x86_64 gsp \
  'linux-omarchy-nvidia-open nvidia-utils lib32-nvidia-utils libva-nvidia-driver'
assert_packages "x86 legacy package selection stays unchanged" x86_64 legacy \
  'nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils'

assert_packages "server GSP keeps native compute drivers without desktop video or multilib" x86_64 gsp \
  'linux-omarchy-nvidia-open nvidia-utils' server
assert_packages "server legacy keeps native compute drivers without multilib" x86_64 legacy \
  'nvidia-580xx-dkms nvidia-580xx-utils' server
assert_packages "GB10 server keeps native GSP compute drivers" aarch64 gsp \
  'linux-omarchy-nvidia-open nvidia-utils' server
