#!/bin/bash
# Tail logs for a workflow service

set -e

SERVICE_NAME="${1:-}"
LINES="${2:-100}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> [lines]"
    echo ""
    echo "Available services:"
    echo "  catalog          - workflow-catalog"
    echo "  executions-api   - workflow-executions-api"
    echo "  engine-worker    - workflow-engine-worker"
    echo "  consumer         - workflow-consumer"
    echo "  validator        - workflow-validator"
    echo "  workflows-worker - workflows-worker"
    echo "  tasks-worker     - workflow-standalone-tasks-worker"
    echo ""
    echo "Examples:"
    echo "  $0 catalog           # Tail last 100 lines"
    echo "  $0 catalog 50        # Tail last 50 lines"
    exit 1
fi

# Map short names to full service names
case "$SERVICE_NAME" in
    catalog)
        FULL_NAME="workflow-catalog"
        ;;
    executions-api)
        FULL_NAME="workflow-executions-api"
        ;;
    engine-worker)
        FULL_NAME="workflow-engine-worker"
        ;;
    consumer)
        FULL_NAME="workflow-consumer"
        ;;
    validator)
        FULL_NAME="workflow-validator"
        ;;
    workflows-worker)
        FULL_NAME="workflows-worker"
        ;;
    tasks-worker)
        FULL_NAME="workflow-standalone-tasks-worker"
        ;;
    *)
        # Assume it's already a full name
        FULL_NAME="$SERVICE_NAME"
        ;;
esac

echo "Tailing logs for: $FULL_NAME (last $LINES lines)"
echo "Press Ctrl+C to stop"
echo "---"

# Try tilt logs first, fallback to kubectl
if command -v tilt &> /dev/null; then
    tilt logs -f "$FULL_NAME" 2>/dev/null || \
    kubectl logs -f -l app="$FULL_NAME" --context kind-kind --tail="$LINES"
else
    kubectl logs -f -l app="$FULL_NAME" --context kind-kind --tail="$LINES"
fi
