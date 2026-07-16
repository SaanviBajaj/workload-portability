#!/usr/bin/env bash
#
# prep-mtv-2tier.sh — pre-seed OpenShift before MTV migrates todo-db / todo-web.
# Creates project, Services (todo-db-svc / todo-web-svc), and a Route.
# Run while logged into the *target* cluster, BEFORE starting the MTV Plan.
#
# Usage:
#   export PROJECT=portable-workload   # optional
#   ./scripts/prep-mtv-2tier.sh
#
set -euo pipefail

if ! oc whoami >/dev/null 2>&1; then
  echo "ERROR: not logged in. Run oc login first." >&2
  exit 1
fi

PROJECT="${PROJECT:-portable-workload}"
CLUSTER_API="$(oc whoami --show-server)"
CLUSTER_USER="$(oc whoami)"

printf '\nTarget cluster: %s\nUser: %s\nProject: %s\n\n' "${CLUSTER_API}" "${CLUSTER_USER}" "${PROJECT}"
read -r -p "Proceed? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo ">> Project ${PROJECT}"
oc new-project "${PROJECT}" 2>/dev/null || oc project "${PROJECT}"

echo ">> Services + Route"
oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: todo-db-svc
  namespace: ${PROJECT}
  labels:
    app: todo-db
spec:
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
      protocol: TCP
  selector:
    # After MTV, KubeVirt sets vm.kubevirt.io/name from the VM name
    vm.kubevirt.io/name: todo-db
---
apiVersion: v1
kind: Service
metadata:
  name: todo-web-svc
  namespace: ${PROJECT}
  labels:
    app: todo-web
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    vm.kubevirt.io/name: todo-web
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: todo-web
  namespace: ${PROJECT}
spec:
  to:
    kind: Service
    name: todo-web-svc
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

echo
echo "Services applied. Next:"
echo "  1. In MTV UI, create/start a Plan for VMs todo-db + todo-web → namespace ${PROJECT}"
echo "  2. Use cold migration + skipGuestConversion (raw copy)"
echo "  3. Prefer a StorageClass that binds for CDI imports (Immediate or known-good CDI path)."
echo "     Avoid WFFC-only RWX classes that leave PVCs Pending with no populator."
echo "  4. After VMs Running: oc get endpoints todo-db-svc -n ${PROJECT}"
echo "  5. Open the Route: oc get route todo-web -n ${PROJECT}"
echo
echo "On boot, todo-env-detect removes /etc/hosts on kvm so CoreDNS resolves todo-db-svc."
