#!/usr/bin/env bash
# Copyright 2025 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# scale-during-upgrade-capd.sh — Scale a MachineDeployment while a ClusterClass
# cluster (CAPD) is upgrading. Tilt-only; run each step in order after creating
# the workload cluster from the Tilt UI.
# See: docs/book/src/topics/scale-during-upgrade.md

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Versions (override with env)
KUBERNETES_VERSION_FROM="${KUBERNETES_VERSION_FROM:-v1.34.0}"
KUBERNETES_VERSION_TO="${KUBERNETES_VERSION_TO:-v1.35.0}"

# Workload cluster namespace (override if not default)
NAMESPACE="${NAMESPACE:-default}"
# Cluster name: leave unset to use the only cluster in NAMESPACE (e.g. from Tilt UI with UUID)
CLUSTER_NAME="${CLUSTER_NAME:-}"

# Kind management cluster
KIND_CLUSTER_NAME="${CAPI_KIND_CLUSTER_NAME:-capi-test}"

# Hook-responses ConfigMap name (set after resolving CLUSTER_NAME)
CONFIGMAP_NAME=""

# Polling
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
WAIT_INTERVAL="${WAIT_INTERVAL:-5}"

usage() {
  echo "Usage: $0 <step>" >&2
  echo "" >&2
  echo "Steps (run in order after creating the workload cluster from Tilt UI):" >&2
  echo "  tilt-up              Start kind + Tilt (run once first)" >&2
  echo "  patch-extension      Set ExtensionConfig defaultAllHandlersToBlocking=true" >&2
  echo "  start-upgrade        Patch cluster topology version to ${KUBERNETES_VERSION_TO}" >&2
  echo "  unblock-before-cluster-upgrade    Unblock BeforeClusterUpgrade hook" >&2
  echo "  unblock-before-control-plane-upgrade  Unblock BeforeControlPlaneUpgrade hook" >&2
  echo "  wait-control-plane   Wait until control plane is at ${KUBERNETES_VERSION_TO}" >&2
  echo "  scale-up             Scale MachineDeployment and Cluster topology to 2 replicas" >&2
  echo "  unblock-after-control-plane-upgrade    Unblock AfterControlPlaneUpgrade hook" >&2
  echo "  validate             Check all nodes at ${KUBERNETES_VERSION_TO}" >&2
  echo "  cleanup               Delete workload cluster and namespace" >&2
  echo "" >&2
  echo "Env: NAMESPACE=${NAMESPACE} (CLUSTER_NAME=auto from only cluster in namespace if unset), KUBERNETES_VERSION_FROM, KUBERNETES_VERSION_TO" >&2
  echo "See: docs/book/src/topics/scale-during-upgrade.md" >&2
  exit 1
}

ensure_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo "kubectl is required" >&2
    exit 1
  fi
}

ensure_kubeconfig() {
  if ! kind get kubeconfig --name "${KIND_CLUSTER_NAME}" &>/dev/null; then
    echo "Kind cluster ${KIND_CLUSTER_NAME} not found. Run: KIND_REGISTRY_PORT=5001 make kind-cluster" >&2
    exit 1
  fi
  local kubeconfig_file
  kubeconfig_file="$(mktemp -t kubeconfig-capd-scale.XXXXXX)"
  kind get kubeconfig --name "${KIND_CLUSTER_NAME}" > "${kubeconfig_file}"
  export KUBECONFIG="${kubeconfig_file}"
}

# Resolve CLUSTER_NAME from the only cluster in NAMESPACE if not set.
ensure_cluster_name() {
  ensure_kubeconfig
  if [[ -n "${CLUSTER_NAME}" ]]; then
    CONFIGMAP_NAME="${CLUSTER_NAME}-test-extension-test-extension-hookresponses"
    return 0
  fi
  local count
  count="$(kubectl get clusters -n "${NAMESPACE}" -o name 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${count}" -eq 0 ]]; then
    echo "No cluster found in namespace ${NAMESPACE}. Create a workload cluster from the Tilt UI first." >&2
    exit 1
  fi
  if [[ "${count}" -ne 1 ]]; then
    echo "Expected exactly one cluster in namespace ${NAMESPACE}, found ${count}. Set CLUSTER_NAME to the cluster to use." >&2
    exit 1
  fi
  CLUSTER_NAME="$(kubectl get clusters -n "${NAMESPACE}" -o jsonpath='{.items[0].metadata.name}')"
  CONFIGMAP_NAME="${CLUSTER_NAME}-test-extension-test-extension-hookresponses"
  echo "Using cluster: ${CLUSTER_NAME}"
}

# Patch a hook's preloadedResponse to Success so the topology controller proceeds.
patch_hook() {
  local key="$1"
  # ConfigMap data value must be the JSON string {"Status": "Success"}; escape for kubectl patch.
  local value='{\"Status\": \"Success\"}'
  kubectl -n "${NAMESPACE}" patch configmap "${CONFIGMAP_NAME}" --type merge -p "{\"data\":{\"${key}\":\"${value}\"}}"
}

# Wait until the ConfigMap exists (created when the extension is first called).
wait_for_configmap() {
  local elapsed=0
  while [[ $elapsed -lt $WAIT_TIMEOUT ]]; do
    if kubectl -n "${NAMESPACE}" get configmap "${CONFIGMAP_NAME}" &>/dev/null; then
      return 0
    fi
    sleep "$WAIT_INTERVAL"
    elapsed=$((elapsed + WAIT_INTERVAL))
  done
  echo "Timeout waiting for ConfigMap ${CONFIGMAP_NAME} in namespace ${NAMESPACE}" >&2
  return 1
}

cmd_tilt_up() {
  echo "Creating kind cluster (registry port 5001) and starting Tilt..."
  (cd "${REPO_ROOT}" && KIND_REGISTRY_PORT=5001 make kind-cluster)
  (cd "${REPO_ROOT}" && make tilt-up)
  echo ""
  echo "Tilt is running. Create your workload cluster from the Tilt UI (ClusterClass with Runtime SDK + EXTENSION_CONFIG_NAME=test-extension)."
  echo "Then run: $0 patch-extension"
}

cmd_patch_extension() {
  ensure_kubectl
  ensure_kubeconfig
  echo "Patching ExtensionConfig test-extension to set defaultAllHandlersToBlocking=true..."
  if kubectl get extensionconfig test-extension &>/dev/null; then
    kubectl patch extensionconfig test-extension --type merge -p '{"spec":{"settings":{"defaultAllHandlersToBlocking":"true"}}}'
    echo "Patched existing ExtensionConfig."
  else
    echo "ExtensionConfig test-extension not found. Creating it..."
    kubectl apply -f - <<EOF
apiVersion: runtime.cluster.x-k8s.io/v1beta2
kind: ExtensionConfig
metadata:
  name: test-extension
  annotations:
    runtime.cluster.x-k8s.io/inject-ca-from-secret: test-extension-system/test-extension-webhook-service-cert
spec:
  settings:
    extensionConfigName: test-extension
    defaultAllHandlersToBlocking: "true"
  clientConfig:
    service:
      name: test-extension-webhook-service
      namespace: test-extension-system
      port: 443
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          - ${NAMESPACE}
EOF
  fi
  echo "Next: $0 start-upgrade"
}

cmd_start_upgrade() {
  ensure_kubectl
  ensure_cluster_name
  echo "Patching cluster ${CLUSTER_NAME} topology version to ${KUBERNETES_VERSION_TO}..."
  kubectl -n "${NAMESPACE}" patch cluster "${CLUSTER_NAME}" --type merge -p "{\"spec\":{\"topology\":{\"version\":\"${KUBERNETES_VERSION_TO}\"}}}"
  echo "Upgrade started. Next: $0 unblock-before-cluster-upgrade"
}

cmd_unblock_before_cluster_upgrade() {
  ensure_kubectl
  ensure_cluster_name
  wait_for_configmap
  local key="BeforeClusterUpgrade-${KUBERNETES_VERSION_FROM}-${KUBERNETES_VERSION_TO}-preloadedResponse"
  echo "Unblocking BeforeClusterUpgrade (patching ${key})..."
  patch_hook "${key}"
  echo "Next: $0 unblock-before-control-plane-upgrade"
}

cmd_unblock_before_control_plane_upgrade() {
  ensure_kubectl
  ensure_cluster_name
  local key="BeforeControlPlaneUpgrade-${KUBERNETES_VERSION_FROM}-${KUBERNETES_VERSION_TO}-preloadedResponse"
  echo "Unblocking BeforeControlPlaneUpgrade (patching ${key})..."
  patch_hook "${key}"
  echo "Next: $0 wait-control-plane"
}

cmd_wait_control_plane() {
  ensure_kubectl
  ensure_cluster_name
  echo "Waiting for control plane to be at ${KUBERNETES_VERSION_TO}..."
  local kcp
  kcp="$(kubectl -n "${NAMESPACE}" get cluster "${CLUSTER_NAME}" -o jsonpath='{.spec.controlPlaneRef.name}')"
  local elapsed=0
  while [[ $elapsed -lt $WAIT_TIMEOUT ]]; do
    local version
    version="$(kubectl -n "${NAMESPACE}" get kubeadmcontrolplane "${kcp}" -o jsonpath='{.spec.version}' 2>/dev/null || true)"
    if [[ "${version}" == "${KUBERNETES_VERSION_TO}" ]]; then
      echo "Control plane spec.version is ${KUBERNETES_VERSION_TO}."
      break
    fi
    sleep "$WAIT_INTERVAL"
    elapsed=$((elapsed + WAIT_INTERVAL))
  done
  if [[ $elapsed -ge $WAIT_TIMEOUT ]]; then
    echo "Timeout waiting for control plane version. Check: kubectl -n ${NAMESPACE} get kubeadmcontrolplane" >&2
    exit 1
  fi
  echo "Next: $0 scale-up"
}

cmd_scale_up() {
  ensure_kubectl
  ensure_cluster_name
  local md_name
  md_name="$(kubectl -n "${NAMESPACE}" get machinedeployment -l cluster.x-k8s.io/cluster-name="${CLUSTER_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${md_name}" ]]; then
    echo "No MachineDeployment found for cluster ${CLUSTER_NAME} in ${NAMESPACE}" >&2
    exit 1
  fi
  echo "Patching Cluster topology (replicas=2) and MachineDeployment ${md_name} (replicas=2)..."
  kubectl -n "${NAMESPACE}" patch cluster "${CLUSTER_NAME}" --type='json' -p='[{"op": "replace", "path": "/spec/topology/workers/machineDeployments/0/replicas", "value": 2}]'
  kubectl -n "${NAMESPACE}" patch machinedeployment "${md_name}" --type merge -p '{"spec":{"replicas":2}}'
  echo "Scale-up applied. Next: $0 unblock-after-control-plane-upgrade"
}

cmd_unblock_after_control_plane_upgrade() {
  ensure_kubectl
  ensure_cluster_name
  local key="AfterControlPlaneUpgrade-${KUBERNETES_VERSION_TO}-preloadedResponse"
  echo "Unblocking AfterControlPlaneUpgrade (patching ${key})..."
  patch_hook "${key}"
  echo "Upgrade will proceed. Next: $0 validate"
}

cmd_validate() {
  ensure_kubectl
  ensure_cluster_name
  if ! command -v clusterctl &>/dev/null; then
    echo "clusterctl not in PATH; skipping kubeconfig fetch. Run: kubectl -n ${NAMESPACE} get machines, and check node versions in workload cluster." >&2
    return 0
  fi
  local kubeconfig_file="/tmp/wk-${CLUSTER_NAME}.yaml"
  clusterctl get kubeconfig "${CLUSTER_NAME}" -n "${NAMESPACE}" > "${kubeconfig_file}" 2>/dev/null || true
  if [[ -s "${kubeconfig_file}" ]]; then
    echo "Nodes in workload cluster:"
    kubectl --kubeconfig "${kubeconfig_file}" get nodes -o wide 2>/dev/null || true
    echo ""
    echo "Ensure all nodes show VERSION ${KUBERNETES_VERSION_TO}."
  else
    echo "Could not get kubeconfig. Check cluster and machines: kubectl -n ${NAMESPACE} get cluster,machines"
  fi
}

cmd_cleanup() {
  ensure_kubectl
  ensure_kubeconfig
  echo "Deleting workload cluster and namespace..."
  kubectl delete cluster -n "${NAMESPACE}" --all --ignore-not-found --timeout=120s || true
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found --timeout=60s || true
  echo "Done. To remove kind: kind delete cluster --name ${KIND_CLUSTER_NAME}"
}

case "${1:-}" in
  tilt-up)                              cmd_tilt_up ;;
  patch-extension)                      cmd_patch_extension ;;
  start-upgrade)                        cmd_start_upgrade ;;
  unblock-before-cluster-upgrade)       cmd_unblock_before_cluster_upgrade ;;
  unblock-before-control-plane-upgrade) cmd_unblock_before_control_plane_upgrade ;;
  wait-control-plane)                   cmd_wait_control_plane ;;
  scale-up)                             cmd_scale_up ;;
  unblock-after-control-plane-upgrade) cmd_unblock_after_control_plane_upgrade ;;
  validate)                             cmd_validate ;;
  cleanup)                              cmd_cleanup ;;
  *)                                    usage ;;
esac
