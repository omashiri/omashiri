#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"
sed 's|/etc/ssh/|${TEST_ROOT:?}/etc/ssh/|g' "${SSHD_SETUP_UNDER_TEST:-$ROOT/bin/omarchy-setup-security-sshd}" >"$test_dir/setup"
cat >"$stub_bin/systemd-detect-virt" <<'STUB'
#!/bin/bash
[[ ${TEST_CHROOT:-0} == 1 ]]
STUB

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg %s\n' "$*" >>"${CALL_LOG:?}"
STUB
cat >"$stub_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB
cat >"$stub_bin/ufw" <<'STUB'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"${CALL_LOG:?}"
[[ -e ${TEST_ROOT:?}/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] || echo "exposed before hardening" >>"$CALL_LOG"
[[ ${FAIL_UFW:-0} != 1 && ${FAIL_AT:-} != "ufw $*" ]]
STUB
cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"${CALL_LOG:?}"
[[ -e ${TEST_ROOT:?}/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] || echo "exposed before hardening" >>"$CALL_LOG"
[[ ${FAIL_AT:-} != "systemctl $*" ]]
STUB
cat >"$stub_bin/curl" <<'STUB'
#!/bin/bash
printf 'unexpected download %s\n' "$*" >>"${CALL_LOG:?}"
exit 98
STUB
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
printf 'gum %s\n' "$1" >>"${CALL_LOG:?}"
# Esc at the first prompt.
exit 130
STUB
cat >"$stub_bin/sshd" <<'STUB'
#!/bin/bash
# A fresh install has no host keys until ssh-keygen -A runs, and sshd -t and
# sshd -T refuse to run without them.
[[ -e ${TEST_ROOT:?}/host-keys ]] || exit 1
case $1 in
-t)
  [[ ${SSHD_SYNTAX_VALID:-1} == 1 ]]
  ;;
-T)
  echo 'pubkeyacceptedalgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256'
  printf 'pubkeyauthentication %s\nauthenticationmethods any\nauthorizedkeysfile .ssh/authorized_keys\nport 22\n' "${SSHD_PUBKEY_AUTH:-yes}"
  if [[ ${2:-} == -C && ${MATCH_PASSWORD:-no} == yes ]]; then
    echo 'passwordauthentication yes'
    exit 0
  fi
  # OpenSSH 10.x dumps keywords in CamelCase; 9.x dumped them lowercase.
  if [[ ${SSHD_DUMP_LOWERCASE:-0} == 1 ]]; then
    printf 'passwordauthentication %s\n' "${SSHD_PASSWORD_AUTH:-no}"
    printf 'kbdinteractiveauthentication %s\n' "${SSHD_KBD_AUTH:-no}"
  else
    printf 'PasswordAuthentication %s\n' "${SSHD_PASSWORD_AUTH:-no}"
    printf 'KbdInteractiveAuthentication %s\n' "${SSHD_KBD_AUTH:-no}"
  fi
  ;;
*)
  exit 2
  ;;
esac
STUB
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
case $1 in
sshd)
  if [[ -n ${REAL_SSHD_CONFIG:-} ]]; then
    shift
    exec /usr/sbin/sshd -f "$REAL_SSHD_CONFIG" "$@"
  fi
  exec "$@"
  ;;
install)
  destination="${4:?}"
  /usr/bin/mkdir -p "${destination%/*}"
  /usr/bin/install -Dm644 /dev/stdin "$destination"
  ;;
rm)
  /usr/bin/rm -f "${3:?}"
  ;;
ssh-keygen)
  : >"${TEST_ROOT:?}/host-keys"
  ;;
*)
  exec "$@"
  ;;
esac
STUB
chmod +x "$stub_bin"/*

ssh-keygen -q -t ed25519 -N "" -f "$test_dir/key"
public_key=$(<"$test_dir/key.pub")

run_setup() {
  local scenario="$1" key="${2:-$public_key}"
  local home="$test_dir/$scenario/home"
  local root="$test_dir/$scenario/root"

  mkdir -p "$home" "$root"
  : >"$test_dir/$scenario.calls"

  HOME="$home" TEST_ROOT="$root" CALL_LOG="$test_dir/$scenario.calls" \
    SSHD_SYNTAX_VALID="${SSHD_SYNTAX_VALID:-1}" \
    SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-no}" \
    SSHD_KBD_AUTH="${SSHD_KBD_AUTH:-no}" \
    PATH="$stub_bin:$PATH" \
    bash "$test_dir/setup" --key="$key"
}

# Nothing may listen or be opened while passwords could still be accepted.
assert_nothing_exposed() {
  local scenario="$1"

  ! grep -qE "^systemctl (enable|start|restart|reload)" "$test_dir/$scenario.calls" ||
    fail "SSH setup must not start sshd when $scenario"
  ! grep -q "^ufw " "$test_dir/$scenario.calls" ||
    fail "SSH setup must not open the firewall when $scenario"
}

output=$(run_setup success)
config="$test_dir/success/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
grep -qxF "PasswordAuthentication no" "$config" || fail "SSH setup disables password authentication"
grep -qxF "KbdInteractiveAuthentication no" "$config" || fail "SSH setup disables keyboard-interactive authentication"
grep -qxF "systemctl reload-or-restart sshd.service" "$test_dir/success.calls" || fail "SSH setup starts sshd with the validated config"
grep -qxF "ufw insert 1 limit 22/tcp comment omarchy-sshd" "$test_dir/success.calls" || fail "SSH setup opens the SSH port"
! grep -qxF "exposed before hardening" "$test_dir/success.calls" || fail "SSH setup starts sshd and opens the port only after passwords are off"
grep -qxF "$public_key" "$test_dir/success/home/.ssh/authorized_keys" || fail "SSH setup writes the authorized key"
grep -q "Password logins are off" <<<"$output" || fail "SSH setup reports hardening after it succeeds"
! grep -qE '^(pkg|unexpected download) ' "$test_dir/success.calls" || fail "installed system enrollment never downloads packages or keys"
pass "SSH setup authorizes a key and disables password logins"

output=$(SSHD_DUMP_LOWERCASE=1 run_setup success-legacy)
config="$test_dir/success-legacy/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
[[ -e $config ]] || fail "SSH setup accepts the lowercase sshd -T dump of OpenSSH 9.x"
grep -q "Password logins are off" <<<"$output" || fail "SSH setup reports hardening on OpenSSH 9.x"
pass "SSH setup verifies settings across sshd -T keyword casings"

if SSHD_PASSWORD_AUTH=yes run_setup ineffective >"$test_dir/ineffective.output" 2>&1; then
  fail "SSH setup must fail when password authentication remains effective"
fi
[[ ! -e $test_dir/ineffective/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH setup removes an ineffective hardening config"
assert_nothing_exposed ineffective
! grep -q "Password logins are off" "$test_dir/ineffective.output" ||
  fail "SSH setup must not claim ineffective hardening succeeded"
pass "SSH setup verifies the effective daemon settings"

if SSHD_SYNTAX_VALID=0 run_setup invalid >"$test_dir/invalid.output" 2>&1; then
  fail "SSH setup must fail when sshd rejects its config"
fi
[[ ! -e $test_dir/invalid/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH setup removes a rejected hardening config"
assert_nothing_exposed invalid
! grep -q "Password logins are off" "$test_dir/invalid.output" ||
  fail "SSH setup must not claim rejected hardening succeeded"
pass "SSH setup fails safely when sshd rejects the config"

if run_setup rejected-key "not-a-key" >"$test_dir/rejected-key.output" 2>&1; then
  fail "SSH setup must fail when the key is rejected"
fi
assert_nothing_exposed rejected-key
[[ ! -e $test_dir/rejected-key/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH setup writes no hardening config without a key"
pass "SSH setup starts nothing and opens nothing when no key is authorized"

mkdir -p "$test_dir/cancelled/home" "$test_dir/cancelled/root"
: >"$test_dir/cancelled.calls"
if HOME="$test_dir/cancelled/home" TEST_ROOT="$test_dir/cancelled/root" CALL_LOG="$test_dir/cancelled.calls" \
  PATH="$stub_bin:$ROOT/bin:$PATH" bash "$test_dir/setup" >/dev/null 2>&1; then
  fail "SSH setup must fail when the key prompt is cancelled"
fi
grep -q "^gum choose" "$test_dir/cancelled.calls" || fail "SSH setup reaches the key prompt"
assert_nothing_exposed cancelled
pass "SSH setup starts nothing and opens nothing when the key prompt is cancelled"

for scenario in invalid-batch comments-only; do
  keys="$public_key"$'\nnot-a-key'
  [[ $scenario == comments-only ]] && keys='# no enrolled keys'
  if run_setup "$scenario" "$keys" >"$test_dir/$scenario.output" 2>&1; then
    fail "$scenario must reject enrollment"
  fi
  assert_nothing_exposed "$scenario"
  [[ ! -s $test_dir/$scenario/home/.ssh/authorized_keys ]] || fail "invalid batch adds no keys"
done
pass "a bad batch is rejected in full before authorization"

if TEST_CHROOT=1 run_setup chroot >"$test_dir/chroot.output" 2>&1; then
  fail "chroot enrollment must fail"
fi
assert_nothing_exposed chroot
pass "chroot enrollment never starts services or touches the live firewall"

for scenario in firewall-failure pubkey-disabled owner-match; do
  if FAIL_UFW=$([[ $scenario == firewall-failure ]] && echo 1 || echo 0) \
    SSHD_PUBKEY_AUTH=$([[ $scenario == pubkey-disabled ]] && echo no || echo yes) \
    MATCH_PASSWORD=$([[ $scenario == owner-match ]] && echo yes || echo no) \
    run_setup "$scenario" >"$test_dir/$scenario.output" 2>&1; then
    fail "$scenario must fail enrollment"
  fi
  ! grep -q '^systemctl .*sshd.service' "$test_dir/$scenario.calls" || fail "$scenario must not start SSH"
done
pass "firewall failure and unusable owner authentication prevent SSH activation"

mkdir -p "$test_dir/admin/root/etc/ssh/sshd_config.d"
printf '# administrator policy\nPasswordAuthentication yes\n' >"$test_dir/admin/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
cp "$test_dir/admin/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf" "$test_dir/admin.original"
if SSHD_PASSWORD_AUTH=yes run_setup admin >"$test_dir/admin.output" 2>&1; then
  fail "insecure administrator policy must fail enrollment"
fi
cmp -s "$test_dir/admin.original" "$test_dir/admin/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf" || fail "administrator config is preserved on failure"
assert_nothing_exposed admin
pass "failed hardening preserves existing administrator configuration"

# Run the real provisioning worker in a separate errexit process, replacing all
# account/boot effects and mapping cleanup paths into the fixture root.
sed -n '/^install_authorized_keys() {/,/^}/p; /^run_provisioning() {/,/^}/p; /^cleanup_oem_state() {/,/^}/p' \
  "${PROVISION_OWNER_UNDER_TEST:-$ROOT/bin/omarchy-provision-owner}" | \
  sed 's|/etc/|${TEST_ROOT:?}/etc/|g; s|/home/|${TEST_ROOT:?}/home/|g' >"$test_dir/owner-functions"
cat >"$test_dir/owner-worker" <<'SH'
#!/bin/bash
set -euo pipefail
source "$OWNER_FUNCTIONS"
username=localowner
hostname=server
timezone=UTC
STATE_FILE=$PROVISIONING_DIR/state
REKEY_STATE=$PROVISIONING_DIR/rekey
FINALIZE_WARNING_FLAG=$PROVISIONING_DIR/warning
log_step() { echo "$*"; }
create_user() { :; }
configure_hostname() { :; }
configure_timezone() { :; }
finalize_user() { :; }
configure_login() { :; }
luks_rekey_pending() { return 1; }
limine_entries_stale() { return 1; }
luks_staged_unlock_remains() { return 1; }
omarchy-edition-server() { return 0; }
chown() { echo "unexpected chown" >&2; exit 98; }
omarchy-setup-security-sshd() {
  [[ $1 == --user=localowner ]] || exit 97
  shift
  bash "$SETUP" "$@"
}
run_provisioning
SH
for scenario in no-key invalid-key valid-key firewall-error firewall-enable-error service-enable-error service-start-error; do
  case_dir="$test_dir/owner-$scenario"
  mkdir -p "$case_dir/home" "$case_dir/root" "$case_dir/provisioning"
  touch "$case_dir/provisioning/pending"
  : >"$case_dir/calls"
  case $scenario in
    invalid-key) echo invalid >"$case_dir/provisioning/authorized_keys" ;;
    valid-key|*-error) printf '%s\n' "$public_key" >"$case_dir/provisioning/authorized_keys" ;;
  esac
  failure=""
  case $scenario in
    firewall-enable-error) failure='ufw --force enable' ;;
    service-enable-error) failure='systemctl enable sshd.service' ;;
    service-start-error) failure='systemctl reload-or-restart sshd.service' ;;
  esac
  status=0
  HOME="$case_dir/home" TEST_ROOT="$case_dir/root" CALL_LOG="$case_dir/calls" FAIL_AT="$failure" \
    PROVISIONING_DIR="$case_dir/provisioning" OWNER_FUNCTIONS="$test_dir/owner-functions" SETUP="$test_dir/setup" \
    FAIL_UFW=$([[ $scenario == firewall-error ]] && echo 1 || echo 0) PATH="$stub_bin:$PATH" \
    bash "$test_dir/owner-worker" >"$case_dir/output" 2>&1 || status=$?
  if [[ $scenario == valid-key ]]; then
    (( status == 0 )) && [[ ! -e $case_dir/provisioning/pending ]] || fail "valid owner enrollment completes" "$(cat "$case_dir/output")"
    grep -qxF 'systemctl reload-or-restart sshd.service' "$case_dir/calls" || fail "server provisioning activates hardened SSH"
    grep -qxF "$public_key" "$case_dir/home/.ssh/authorized_keys" || fail "owner key is authorized"
  else
    (( status != 0 )) && [[ -e $case_dir/provisioning/pending ]] || fail "$scenario must keep provisioning pending" "$(cat "$case_dir/output")"
    if [[ -n $failure ]]; then
      grep -qxF "$failure" "$case_dir/calls" || fail "$scenario reaches the failing operation" "$(cat "$case_dir/output")"
    fi
    if [[ $scenario != service-* ]]; then
      ! grep -q '^systemctl .*sshd.service' "$case_dir/calls" || fail "$scenario must not start SSH"
    fi
  fi
done
pass "server provisioning completes only after valid key, hardening and firewall enrollment"

# Only the daemon's parser runs here; it never binds a socket or authenticates.
for scenario in real-default real-match real-disabled-key real-admin real-rejected-algorithm; do
  case_dir="$test_dir/$scenario"
  mkdir -p "$case_dir/home" "$case_dir/root/etc/ssh/sshd_config.d"
  : >"$case_dir/calls"
  cat >"$case_dir/sshd_config" <<CONF
Include $case_dir/root/etc/ssh/sshd_config.d/*.conf
HostKey $test_dir/key
Port 2222
AuthorizedKeysFile .ssh/authorized_keys
CONF
  case $scenario in
    real-match) printf 'Match User %s\n  PasswordAuthentication yes\n' "$(id -un)" >>"$case_dir/sshd_config" ;;
    real-disabled-key) echo 'PubkeyAuthentication no' >>"$case_dir/sshd_config" ;;
    real-rejected-algorithm) echo 'PubkeyAcceptedAlgorithms rsa-sha2-512' >>"$case_dir/sshd_config" ;;
    real-admin) echo 'PasswordAuthentication yes' >"$case_dir/root/etc/ssh/sshd_config.d/00-admin.conf" ;;
  esac
  status=0
  HOME="$case_dir/home" USER="$(id -un)" TEST_ROOT="$case_dir/root" CALL_LOG="$case_dir/calls" \
    REAL_SSHD_CONFIG="$case_dir/sshd_config" PATH="$stub_bin:$PATH" \
    bash "$test_dir/setup" --key="$public_key" >"$case_dir/output" 2>&1 || status=$?
  if [[ $scenario == real-default ]]; then
    (( status == 0 )) || fail "real sshd accepts hardened enrollment" "$(cat "$case_dir/output")"
    grep -qxF 'ufw insert 1 limit 2222/tcp comment omarchy-sshd' "$case_dir/calls" || fail "firewall uses the effective SSH port"
  else
    (( status != 0 )) || fail "$scenario must reject ineffective hardening"
    ! grep -qE '^(ufw|systemctl) ' "$case_dir/calls" || fail "$scenario must not activate SSH or firewall"
  fi
done
pass "real sshd validates defaults, custom ports, owner Match and administrator precedence"

mkdir -p "$test_dir/append/home/.ssh"
printf '%s' "$public_key" >"$test_dir/append/home/.ssh/authorized_keys"
ssh-keygen -q -t ed25519 -N "" -f "$test_dir/second"
run_setup append "$(cat "$test_dir/second.pub")" >"$test_dir/append.output" 2>&1
[[ $(ssh-keygen -lf "$test_dir/append/home/.ssh/authorized_keys" | wc -l) == 2 ]] || fail "appended key remains usable beside an existing key without a final newline"
pass "enrollment preserves existing keys and appends a separate usable key"
