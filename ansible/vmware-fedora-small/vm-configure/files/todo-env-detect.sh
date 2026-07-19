#!/bin/bash
# Resolves todo-db-svc on VMware vs OpenShift Virtualization.
#
# VMware: /etc/hosts → TODO_DB_IP (guest has no cluster DNS).
# OpenShift Virt (kvm/qemu): clear VMware hosts block and point the guest at
# cluster CoreDNS so short name todo-db-svc resolves via the Service.
# Optional fallback: TODO_DB_SERVICE_IP writes ClusterIP into /etc/hosts.
set -euo pipefail

MARKER_START="# BEGIN TODO-WORKLOAD SERVICE EMULATION"
MARKER_END="# END TODO-WORKLOAD SERVICE EMULATION"
SVC_NAME="${TODO_DB_SVC_NAME:-todo-db-svc}"
DB_IP="${TODO_DB_IP:-}"
SERVICE_IP="${TODO_DB_SERVICE_IP:-}"
# OpenShift in-cluster DNS (dns-default in openshift-dns); override if needed.
CLUSTER_DNS_IP="${CLUSTER_DNS_IP:-172.30.0.10}"
CLUSTER_DNS_SEARCH="${CLUSTER_DNS_SEARCH:-portable-workload.svc.cluster.local svc.cluster.local cluster.local}"

VIRT="$(systemd-detect-virt 2>/dev/null || echo unknown)"

sed -i "/${MARKER_START}/,/${MARKER_END}/d" /etc/hosts

configure_cluster_dns() {
  if [[ -d /etc/systemd/resolved.conf.d ]] || systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat >/etc/systemd/resolved.conf.d/99-todo-openshift.conf <<EOF
[Resolve]
DNS=${CLUSTER_DNS_IP}
Domains=~svc.cluster.local ~cluster.local ${CLUSTER_DNS_SEARCH}
DNSSEC=no
EOF
    # Prefer stub resolv.conf when resolved is in use
    if [[ -f /run/systemd/resolve/stub-resolv.conf ]]; then
      ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    fi
    systemctl try-restart systemd-resolved.service 2>/dev/null \
      || systemctl restart systemd-resolved.service 2>/dev/null \
      || true
    echo "todo-env-detect: configured systemd-resolved → ${CLUSTER_DNS_IP} (${CLUSTER_DNS_SEARCH})"
  else
    cat >/etc/resolv.conf <<EOF
nameserver ${CLUSTER_DNS_IP}
search ${CLUSTER_DNS_SEARCH}
EOF
    echo "todo-env-detect: wrote /etc/resolv.conf → ${CLUSTER_DNS_IP}"
  fi
}

if [ "${VIRT}" = "vmware" ]; then
  # Drop any OpenShift-only resolved drop-in so VMware DHCP/DNS stays authoritative.
  rm -f /etc/systemd/resolved.conf.d/99-todo-openshift.conf
  systemctl try-restart systemd-resolved.service 2>/dev/null || true

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
  exit 0
fi

# Non-VMware (OpenShift Virt / kvm / qemu): use cluster DNS, optional hosts fallback.
configure_cluster_dns

if [ -n "${SERVICE_IP}" ]; then
  cat >> /etc/hosts <<EOF
${MARKER_START}
${SERVICE_IP} ${SVC_NAME}
${MARKER_END}
EOF
  echo "todo-env-detect: virt=${VIRT} — mapped ${SVC_NAME} → ${SERVICE_IP} (TODO_DB_SERVICE_IP)"
else
  echo "todo-env-detect: virt=${VIRT} — relying on CoreDNS for ${SVC_NAME}"
fi
