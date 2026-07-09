#!/usr/bin/env bash
# Update xrpld from the Ripple RPM repo and restart the service if a new
# version was installed. Deployed by Ansible (roles/rippled); replaces the
# update script that the xrpld package no longer ships.
# Run manually, one box at a time: nodes first, validator last.
set -uo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This update script must be run as root or sudo" >&2
  exit 1
fi

LOCKDIR=/tmp/xrpld-update.lock
LOG=/var/log/rippled/update.log

log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

# mkdir is atomic - poor man's lock
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  log "lockdir $LOCKDIR exists - another update in progress, aborting"
  exit 1
fi
trap 'rmdir "$LOCKDIR"' EXIT

dnf -q clean expire-cache --disablerepo='*' --enablerepo=ripple-stable || true

dnf -q check-update --enablerepo=ripple-stable xrpld
rc=$?
if [[ $rc -eq 0 ]]; then
  log "xrpld is up to date ($(rpm -q xrpld))"
  exit 0
elif [[ $rc -ne 100 ]]; then
  log "dnf check-update failed with rc=$rc"
  exit 1
fi

old=$(rpm -q xrpld)
log "update available (current: $old) - updating"
dnf -y update --enablerepo=ripple-stable xrpld >>"$LOG" 2>&1
systemctl daemon-reload
systemctl restart xrpld

for _ in $(seq 1 30); do
  if systemctl is-active --quiet xrpld; then
    log "updated: $old -> $(rpm -q xrpld), xrpld active"
    exit 0
  fi
  sleep 1
done

log "WARNING: xrpld not active 30s after restart - check 'journalctl -u xrpld'"
exit 1
