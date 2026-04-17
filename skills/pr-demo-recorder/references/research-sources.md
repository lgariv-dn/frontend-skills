# Research sources for PR demos

Where to pull context from before talking to the user. Gather in parallel; nothing here waits on the user.

## Current branch and PR

```bash
git branch --show-current            # → extract Jira key, e.g. lgariv/ar-58199/... → AR-58199
gh pr view --json number,title,body,headRefName,baseRefName
gh pr diff --name-only               # → filter for E2E/seed files
```

Parse the PR body for:
- Repro instance IDs (`instanceId=<uuid>`)
- Manual verification steps
- Screenshots (PR desc images → infer the intended visual story)
- Linked tickets (`AR-XXXXX` references)

## Jira ticket (MCP)

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: <from getAccessibleAtlassianResources if unknown>
  issueIdOrKey: AR-XXXXX
```

Read:
- `description` — the user-visible bug/feature
- `customfield_10001` (Epic Link) or equivalent — for epic detection
- comments — repro steps from QA, screenshots, UAT notes
- status + linked issues (is this part of a larger effort?)

For epic-level demos, fetch children:

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  jql: 'parent = "EPIC-KEY" AND status != Closed ORDER BY rank'
```

## New E2E tests (PR diff)

```bash
gh pr diff --name-only | grep -E '\.e2e\.spec\.ts$|\.seed\.ts$|/fixtures/|\.ya?ml$'
```

For each spec file:
1. Read the whole file — the test titles describe user-visible flows.
2. Note fixture imports (`instanceViewerPage`, `catalogPage`, `setupParallelInstances`) — these name the POMs to read next.
3. Extract the navigation URL and the interaction sequence.

For each referenced POM (`tests/workflow/typescript/pages/*.ts`):
1. Find `readonly` locator declarations — stable selectors.
2. Find the action methods the spec calls — flow semantics.

## Playwright fixtures

Many tests use fixtures like `setupParallelInstances` that pre-seed data. Find them in `tests/workflow/typescript/fixtures/` and read:
- What they seed (workflow names, instance shapes)
- What they return (instance IDs, URLs — these become webreel `url` fields)

## Reproduction artifacts on disk

```bash
ls /tmp/ar${TICKET_NUMBER}_*.yaml 2>/dev/null
ls /tmp/ar${TICKET_NUMBER}_*.json 2>/dev/null
```

These are often the exact minimal repro definitions from a prior debugging session. They're the best input if you need to seed a fresh instance.

## Seeding a fresh workflow instance via DAP catalog API

```bash
# 1. Upload YAML
curl -X POST http://localhost:4200/api/workflows/upload \
  -F "file=@/tmp/ar58199_parent.yaml"
# Response: { "workflow_id": "...", "version_id": "..." }

# 2. Poll until version status === PENDING (typically <5s)
for i in {1..20}; do
  status=$(curl -s "http://localhost:4200/api/workflows/versions/$VERSION_ID" | jq -r .status)
  [[ "$status" == "PENDING" ]] && break
  sleep 0.5
done

# 3. Approve
curl -X PUT "http://localhost:4200/api/workflows/versions/$VERSION_ID/approve"

# 4. Execute
curl -X POST http://localhost:4200/api/workflow/execute \
  -H "Content-Type: application/json" \
  -d '{"workflow_id":"'"$WORKFLOW_ID"'","inputs":{}}'
# Response: { "instance_id": "..." }

# 5. Poll for terminal state (if demo needs completed state)
for i in {1..60}; do
  state=$(curl -s "http://localhost:4200/api/instances/$INSTANCE_ID" | jq -r .status)
  [[ "$state" == "Completed" || "$state" == "Failed" ]] && break
  sleep 1
done
```

Replace port `4200` with the actual dev server port if different. For workflows with embedded sub-workflows, upload and approve the child first, then the parent.

## Verifying the running dev server

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4200/    # 200 = up
```

To verify the running code has the expected fix, open the target URL via `mcp__chrome-devtools__navigate_page` and inspect the DOM for fix-specific elements. Don't trust git state alone — HMR can lag, and side-branches may not have the fix even if they recently rebased.
