# Workflow Local Development Reference

## Service URLs

### Workflow Engine APIs

| Service | URL | Docs |
|---------|-----|------|
| Catalog API | http://localhost:8000 | http://localhost:8000/docs |
| Executions API | http://localhost:8001 | http://localhost:8001/docs |
| Validator API | http://localhost:8003 | http://localhost:8003/docs |
| Consumer (HTTP) | http://localhost:8004 | - |
| Consumer (gRPC) | localhost:9004 | - |
| GitHub App | http://localhost:8005 | http://localhost:8005/docs |
| Executions gRPC | localhost:9001 | - |

### Unified Ingress (Gateway)

All services via **http://localhost:8090**:
- `/execution/` → workflow-executions-api
- `/catalog/` → workflow-catalog
- `/validator/` → workflow-validator
- `/consumer/` → workflow-consumer
- `/github-app/` → workflow-github-app

---

## Infrastructure

| Service | URL/Port |
|---------|----------|
| PostgreSQL | localhost:5432 |
| Temporal gRPC | localhost:7233 |
| Temporal UI | http://localhost:8081 |
| Pulsar (binary) | pulsar://localhost:6650 |
| Pulsar Admin | http://localhost:9090 |
| Azurite | localhost:10000-10002 |
| Vault | http://localhost:8200 |
| OpenFGA | localhost:8091, 8092, 3010 |
| GitBucket | http://localhost:8888 |

---

## Monitoring & Tools

| Service | URL |
|---------|-----|
| Tilt UI | http://localhost:10350 |
| PostgREST | http://localhost:3000 |
| Swagger UI | http://localhost:8080 |
| Grafana | http://localhost:3001 (if enabled) |
| VictoriaLogs | http://localhost:9428 |
| Tempo | localhost:3200, 4317, 4318 |

---

## Other Services

| Service | URL/Port |
|---------|----------|
| Template Manager | http://localhost:3001 |
| Config Manager | localhost:3100 (gRPC), localhost:8080 (HTTP) |
| Resource Manager | localhost:9091 (gRPC), localhost:8080 (HTTP) |
| DAP GitHub App | http://localhost:8050/docs |
| MCP Server | http://localhost:3009 |

---

## Database Access

### PostgreSQL (Workflow Engine)

```
Host: localhost
Port: 5432
Database: temporal
User: postgres
Password: postgres
Schema: workflow_engine
```

### Connect via psql
```bash
psql -h localhost -U postgres -d temporal
```

### Useful Queries
```sql
-- Recent workflow instances
SELECT * FROM workflow_engine.workflow_instance ORDER BY created_at DESC LIMIT 10;

-- Task catalog
SELECT * FROM workflow_engine.task_catalog;

-- Workflow versions
SELECT * FROM workflow_engine.workflow_version WHERE workflow_id = '<uuid>';
```

---

## Pulsar (Message Broker)

### Consume Messages
```bash
pulsar-client consume persistent://public/dap/<topic> -s test-sub -n 10
```

### Common Topics
- `persistent://public/dap/workflow.*`
- `persistent://public/dap/e2e-test.workflow_invocation_response`
- `persistent://public/dap/notifications`

---

## Key Directories

```
dap-workspace/
├── apps/workflow/                    # Workflow microservices
│   ├── workflow-catalog/             # Catalog API service
│   ├── workflow-executions-api/      # Executions API service
│   ├── workflow-engine-worker/       # Activities worker
│   ├── workflow-consumer/            # Event consumer
│   ├── workflow-validator/           # YAML validator
│   ├── workflows-worker/             # Workflows worker
├── libs/workflow/                    # Shared workflow libraries
│   └── workflow-engine-core/         # Core models and utilities
├── libs/sdk/testing_sdk/             # Testing SDK
├── tests/workflow/                   # E2E tests
└── tools/local-deployments/          # K8s manifests and Tiltfiles
    └── workflow-engine/              # Workflow engine deployment
```
