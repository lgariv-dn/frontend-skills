#!/bin/bash
# Check pod status in the local Kind cluster

set -e

echo "=== Pod Status (kind-kind) ==="
kubectl get pods --context kind-kind -o wide

echo ""
echo "=== Pods Not Running ==="
kubectl get pods --context kind-kind --field-selector=status.phase!=Running 2>/dev/null || echo "All pods are running!"
