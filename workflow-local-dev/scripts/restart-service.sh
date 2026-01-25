#!/bin/bash
# Restart a workflow service using Tilt

set -e

SERVICE_NAME="${1:-}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name>"
    echo ""
    echo "Available services:"
    echo "  catalog          - workflow-catalog"
    echo "  executions-api   - workflow-executions-api"
    echo "  engine-worker    - workflow-engine-worker"
    echo "  consumer         - workflow-consumer"
    echo "  validator        - workflow-validator"
    echo "  workflows-worker - workflows-worker"
    echo "  tasks-worker     - workflow-standalone-tasks-worker"
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

echo "Triggering rebuild for: $FULL_NAME"
tilt trigger "$FULL_NAME"
echo "Done! Service will rebuild and restart."
