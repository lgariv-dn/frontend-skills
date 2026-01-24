---
name: workflow-local-dev
description: Assist with local deployment of workflow features in the DAP workspace. Provides access to Kubernetes (Kind), Tilt service management, database queries, and troubleshooting. Use when developing workflow services, debugging pods, checking logs, running tests, or troubleshooting the local workflow environment.
---

# Workflow Local Development

## Quick Reference

### Key Commands

| Task | Command |
|------|---------|
| Check pods | `kubectl get pods --context kind-kind` |
| Restart service | `tilt trigger workflow-<service>` |
| View logs | `tilt logs workflow-<service>` |
| Run tests | `nx test <project>` (in dap-workspace) |
| Run E2E | `pytest dap-workspace/tests/workflow/<test> -v` |

### Services

`workflow-catalog`, `workflow-executions-api`, `workflow-engine-worker`, `workflow-consumer`, `workflow-validator`, `workflows-worker`, `standalone-tasks-worker`

---

## Utility Scripts

Execute these scripts for common operations:

### Check Pod Status
```bash
bash .cursor/skills/workflow-local-dev/scripts/check-pods.sh
```

### Restart a Service
```bash
bash .cursor/skills/workflow-local-dev/scripts/restart-service.sh <service-name>
# Example: bash .cursor/skills/workflow-local-dev/scripts/restart-service.sh catalog
```

### Tail Service Logs
```bash
bash .cursor/skills/workflow-local-dev/scripts/tail-logs.sh <service-name>
# Example: bash .cursor/skills/workflow-local-dev/scripts/tail-logs.sh executions-api
```

### Query Database
```bash
bash .cursor/skills/workflow-local-dev/scripts/db-query.sh "<SQL query>"
# Example: bash .cursor/skills/workflow-local-dev/scripts/db-query.sh "SELECT * FROM workflow_engine.workflow_instance ORDER BY created_at DESC LIMIT 5"
```

---

## Development Workflow

1. **Make code changes**
2. **Rebuild service**: `tilt trigger workflow-<service>`
3. **Watch logs**: `kubectl logs -f <pod> --context kind-kind`
4. **Run unit tests**: `nx test <project>` (from dap-workspace)
5. **Run linter**: `nx lint <project>`
6. **Run E2E tests** (if needed): `pytest dap-workspace/tests/workflow/<test> -v`

---

## Testing Protocol

### Unit Tests (per modified NX project)
```bash
cd dap-workspace
nx test <project-name>   # e.g., nx test workflow-catalog
nx lint <project-name>   # e.g., nx lint workflow-catalog
```

### E2E Tests
```bash
source dap-workspace/tests/.venv/bin/activate
pytest dap-workspace/tests/workflow/<path-to-specific-test> -v
```

---

## Troubleshooting

### Pod Issues
```bash
kubectl get pods --context kind-kind
kubectl describe pod <pod-name> --context kind-kind
kubectl logs -f <pod-name> --context kind-kind
```

### Temporal Workflows
Open http://localhost:8081 (Temporal UI) and search by workflow ID.

### Database State
```bash
psql -h localhost -U postgres -d temporal -c "SELECT * FROM workflow_engine.workflow_instance ORDER BY created_at DESC LIMIT 5;"
```

### Pulsar Messages
```bash
pulsar-admin topics stats persistent://public/dap/<topic>
pulsar-client consume persistent://public/dap/<topic> -s test-sub -n 10
```

---

## Additional Resources

- For complete service URLs and infrastructure details, see [reference.md](reference.md)
