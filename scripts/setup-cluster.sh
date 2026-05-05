#!/bin/bash
set -euo pipefail

CLUSTER_NAME="tracing-mcp-eval"

echo "==> Creating Kind cluster: ${CLUSTER_NAME}"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "    Cluster '${CLUSTER_NAME}' already exists, skipping creation"
else
    kind create cluster --name "${CLUSTER_NAME}" --wait 5m
fi

echo "==> Installing Cert Manager..."
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.19.4/cert-manager.yaml
kubectl -n cert-manager rollout status deployment/cert-manager --timeout=5m
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=5m
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=5m

echo "==> Installing OpenTelemetry operator..."
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/download/v0.146.0/opentelemetry-operator.yaml
kubectl -n opentelemetry-operator-system rollout status deployment/opentelemetry-operator-controller-manager --timeout=5m

echo "==> Installing Tempo operator..."
kubectl apply -f https://github.com/grafana/tempo-operator/releases/download/v0.20.0/tempo-operator.yaml
kubectl -n tempo-operator-system rollout status deployment/tempo-operator-controller --timeout=5m
