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
    echo "  $0 \"SELECT * FROM workflow_engine.workflow_instance ORDER BY created_at DESC LIMIT 5\""
    echo "  $0 \"SELECT * FROM workflow_engine.task_catalog\""
    echo "  $0 \"SELECT * FROM workflow_engine.workflow_version WHERE workflow_id = 'uuid'\""
    exit 1
fi

echo "Executing query..."
echo "---"

PGPASSWORD=postgres psql -h localhost -U postgres -d temporal -c "$QUERY"
