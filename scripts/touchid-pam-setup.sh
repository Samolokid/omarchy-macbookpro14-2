#!/bin/bash
# Touch ID (t1bridge) PAM wiring for Omarchy: sudo, polkit, lock screen.
# Follows t1-revive's docs/omarchy.md. Do NOT use
# omarchy-setup-security-fingerprint instead: it replaces t1bridge's fprintd.
#
# Run:  sudo bash touchid-pam-setup.sh
# Undo: sudo bash touchid-pam-setup.sh --undo
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run this with sudo."; exit 1; }

# Skip the fingerprint reader while the lid is closed (external display use)
GATE='auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed'
FPRINT='auth      sufficient pam_fprintd.so'

if [[ ${1:-} == --undo ]]; then
  [[ -f /etc/pam.d/sudo.bak-touchid ]] && cp /etc/pam.d/sudo.bak-touchid /etc/pam.d/sudo
  rm -f /etc/pam.d/polkit-1 /etc/pam.d/omarchy-lock-fingerprint
  echo "Undone."
  exit 0
fi

# sudo: two lines directly under the header, existing lines untouched
if grep -q pam_fprintd.so /etc/pam.d/sudo; then
  echo "sudo: already set up, skipped"
else
  cp /etc/pam.d/sudo /etc/pam.d/sudo.bak-touchid
  sed -i "1a $GATE\n$FPRINT" /etc/pam.d/sudo
  echo "sudo: set up (backup: /etc/pam.d/sudo.bak-touchid)"
fi

# polkit: Arch's vendor file (/usr/lib/pam.d/polkit-1) uses system-auth
# includes, so mirror that with the two lines on top
if [[ -e /etc/pam.d/polkit-1 ]]; then
  echo "polkit-1: already exists, skipped"
else
  printf '%s\n' '#%PAM-1.0' "$GATE" "$FPRINT" \
    'auth      include      system-auth' \
    'account   include      system-auth' \
    'password  include      system-auth' \
    'session   include      system-auth' > /etc/pam.d/polkit-1
  echo "polkit-1: created"
fi

# lock screen: fingerprint-only path offered next to the password path
if [[ -e /etc/pam.d/omarchy-lock-fingerprint ]]; then
  echo "omarchy-lock-fingerprint: already exists, skipped"
else
  printf '%s\n' '#%PAM-1.0' \
    'auth       required                    pam_fprintd.so' \
    'account    include                     system-local-login' > /etc/pam.d/omarchy-lock-fingerprint
  echo "omarchy-lock-fingerprint: created"
fi

echo
echo "== /etc/pam.d/sudo"
cat /etc/pam.d/sudo
