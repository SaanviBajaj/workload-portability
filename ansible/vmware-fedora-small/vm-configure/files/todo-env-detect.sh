#!/bin/bash
# Manages /etc/hosts entries for todo-db-svc resolution.
# VMware: write service name → static DB IP.
# OpenShift Virt (kvm): remove entries so CoreDNS resolves the K8s Service.
set -euo pipefail

MARKER_START="# BEGIN TODO-WORKLOAD SERVICE EMULATION"
MARKER_END="# END TODO-WORKLOAD SERVICE EMULATION"
SVC_NAME="${TODO_DB_SVC_NAME:-todo-db-svc}"
DB_IP="${TODO_DB_IP:-}"

VIRT="$(systemd-detect-virt 2>/dev/null || echo unknown)"

sed -i "/${MARKER_START}/,/${MARKER_END}/d" /etc/hosts

if [ "${VIRT}" = "vmware" ]; then
  if [ -z "${DB_IP}" ]; then
    echo "todo-env-detect: TODO_DB_IP unset; skipping /etc/hosts write" >&2
    exit 0
  fi
  cat >> /etc/hosts <<EOF
${MARKER_START}
${DB_IP} ${SVC_NAME}
${MARKER_END}
EOF
  echo "todo-env-detect: VMware — mapped ${SVC_NAME} → ${DB_IP}"
else
  echo "todo-env-detect: virt=${VIRT} — left CoreDNS/Service resolution in place"
fi
