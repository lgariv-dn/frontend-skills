#!/bin/bash
# Execute a query against the workflow engine database

set -e

QUERY="${1:-}"

if [ -z "$QUERY" ]; then
    echo "Usage: $0 \"<SQL query>\""
    echo ""
    echo "Connection details:"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  Database: temporal"
    echo "  Schema: workflow_engine"
    echo ""
    echo "Examples:"
    echo "  $0 \"SELECT * FROM workflow_engine.workflows ORDER BY created_at DESC LIMIT 5\""
    echo "  $0 \"SELECT * FROM workflow_engine.tasks\""
    echo "  $0 \"SELECT * FROM workflow_engine.workflow_versions WHERE workflow_id = 'uuid'\""
    exit 1
fi

echo "Executing query..."
echo "---"

# Find the postgres pod and run psql inside it
POSTGRES_POD=$(kubectl get pods --context kind-kind -o name | grep -E '^pod/postgres-' | head -1 | sed 's|pod/||')

if [ -z "$POSTGRES_POD" ]; then
    echo "Error: Could not find postgres pod in the cluster"
    exit 1
fi

kubectl exec "$POSTGRES_POD" --context kind-kind -- psql -U postgres -d temporal -c "$QUERY"
