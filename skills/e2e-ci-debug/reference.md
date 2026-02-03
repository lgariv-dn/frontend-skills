# E2E CI Debug - Reference Documentation

This document provides detailed technical information about E2E test infrastructure, CI workflows, artifact locations, and Playwright configurations.

## Table of Contents

- [Playwright Configurations](#playwright-configurations)
- [CI Workflows](#ci-workflows)
- [Artifact Locations](#artifact-locations)
- [Test Report Structure](#test-report-structure)
- [Common Failure Patterns](#common-failure-patterns)
- [GitHub Actions Integration](#github-actions-integration)

## Playwright Configurations

### Workflow Tests Configuration

**Location:** `dap-workspace/tests/workflow/typescript/playwright.config.ts`

```typescript
{
  testDir: './',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  testIgnore: ['**/._*', '**/.DS_Store'],
  reporter: [
    ['html', { outputFolder: '../../../reports/typescript-playwright/workflow/playwright-report' }],
    ['list'],
    ['junit', { outputFile: '../../../reports/typescript-playwright/workflow/junit.xml' }]
  ],
  use: {
    baseURL: process.env.WORKFLOW_BASE_URL || 'http://localhost:4200',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    {
      name: 'sanity',
      testMatch: /.*\.sanity\.spec\.ts$/,
      retries: 0,
      timeout: 30000
    },
    {
      name: 'setup',
      testDir: './seed',
      testMatch: /\.setup\.ts$/,
      timeout: 120000,
      dependencies: ['sanity']
    },
    {
      name: 'e2e',
      testMatch: /.*\.e2e\.spec\.ts$/,
      dependencies: ['setup']
    }
  ]
}
```

**Key Features:**
- **Project Dependencies:** Tests run in order: `sanity` → `setup` → `e2e`
- **Retries:** 2 retries in CI, 0 locally
- **Workers:** Single worker in CI for stability
- **Artifacts:** Trace, screenshot, and video on failure only
- **Base URL:** Configurable via `WORKFLOW_BASE_URL` environment variable

### Component E2E Tests Configuration

**Location:** `dap-workspace/libs/workflow/workflow-fe/workflow-fe-e2e/playwright.config.ts`

**Key Features:**
- **Web Server:** Auto-starts `workflow-root-fe` on port 4200
- **Test Directory:** `./src` (relative to config file)
- Used for component-level E2E tests within workflow libraries

## CI Workflows

### PR Workflow Chain

**Entry Point:** `.github/workflows/dispatcher.yml`
- Triggers on: `pull_request` events (opened, synchronize, reopened)
- Validates branch patterns and protection rules
- Calls: `pr-core.yaml`

**Core Logic:** `.github/workflows/pr-core.yaml`
- Runs: `test`, `lint`, `validate-package-dependencies`, `docker`, `deploy`
- E2E tests triggered via: `pr-processor.yml` (external workflow)
- Uses `nx affected -t e2e --base=origin/<target-branch>` for E2E

**Jobs:**
1. `skip_duplicate_actions` - Prevents duplicate runs
2. `check-labels` - Validates PR labels
3. `check-title` - Validates PR title format
4. `test` - Runs unit tests (`nx affected -t test`)
5. `lint` - Runs linters (`nx affected -t lint`)
6. `validate-package-dependencies` - Checks dependency consistency
7. `check-mermaid-export` - Validates Mermaid diagram exports
8. `check-ci-deployment` - Determines if deployment should occur
9. `set-environment` - Sets up environment variables
10. `docker` - Builds affected Docker images
11. `deploy` - Deploys to dev environment (calls `pr-processor.yml`)
12. `analyze-workflow-failure` - AI-powered failure analysis

## Artifact Locations

### PR E2E Artifacts

**GitHub Actions Artifacts:**
- Artifact naming varies by implementation in `pr-processor.yml`
- Typically includes E2E or test-related keywords in name
- Contains: Playwright reports from `nx affected -t e2e`

**Local Paths (after download):**
```
playwright-results/
└── workflow/
    ├── playwright-report/  # HTML report
    ├── junit.xml           # JUnit XML
    └── test-results/       # Screenshots, traces, videos
```

## Test Report Structure

### JUnit XML Format

**Location:** `reports/typescript-playwright/{suite}/junit.xml`

**Structure:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="workflow" tests="10" failures="2" errors="0" time="45.123">
    <testcase name="should load workflow builder" classname="workflow-builder.e2e.spec.ts" time="2.456">
      <!-- Success - no child elements -->
    </testcase>
    <testcase name="should save workflow" classname="workflow-builder.e2e.spec.ts" time="3.789">
      <failure message="Timeout 30000ms exceeded" type="TimeoutError">
        Error: Timeout 30000ms exceeded.
        Call log:
          - waiting for locator('[data-testid="save-button"]')
        
        at tests/e2e/builder/workflow-builder.e2e.spec.ts:42:15
      </failure>
    </testcase>
  </testsuite>
</testsuites>
```

**Key Elements:**
- `<testsuite>`: Groups tests by file or suite
- `<testcase>`: Individual test with name, classname, time
- `<failure>`: Contains error message, type, and stack trace
- `<error>`: System errors (rare in Playwright)

### HTML Report Structure

**Location:** `reports/typescript-playwright/{suite}/playwright-report/`

**Contents:**
```
playwright-report/
├── index.html           # Main report page
├── data/                # Test data in JSON format
├── assets/              # CSS, JS, images
└── trace-*/             # Trace files (if enabled)
```

**Features:**
- Interactive filtering by status, project, file
- Detailed test execution timeline
- Screenshots and videos embedded
- Trace viewer integration

### Trace Files

**Location:** `test-results/{test-name}/trace.zip`

**Usage:**
```bash
npx playwright show-trace test-results/workflow-builder-should-save/trace.zip
```

**Contains:**
- Full DOM snapshots at each step
- Network requests and responses
- Console logs
- Action timeline

## Common Failure Patterns

### 1. Selector Not Found

**Error:**
```
Error: Locator.click: Error: element not found: [data-testid="save-button"]
```

**Causes:**
- Element doesn't exist in DOM
- Element rendered after timeout
- Incorrect selector
- Element in shadow DOM

**Solutions:**
- Verify selector with browser DevTools
- Add explicit wait: `await page.waitForSelector('[data-testid="save-button"]')`
- Check for dynamic content loading
- Use Playwright's auto-waiting: `page.locator(...).click()` instead of manual waits

### 2. Timeout Errors

**Error:**
```
Error: Timeout 30000ms exceeded.
Call log:
  - waiting for locator('[data-testid="workflow-list"]')
```

**Causes:**
- Network delays
- API response slow
- Element never appears
- Wrong selector

**Solutions:**
- Increase timeout: `{ timeout: 60000 }` in test or config
- Check network tab for slow API calls
- Verify API endpoints are accessible
- Use `page.waitForResponse()` for API-dependent elements

### 3. Setup/Seed Failures

**Error:**
```
Error in setup project: Failed to seed database
```

**Causes:**
- Database connection issues
- API authentication failures
- Missing environment variables
- Seed data conflicts

**Solutions:**
- Check `WORKFLOW_BASE_URL` or other env vars
- Verify database is accessible
- Review `seed/*.setup.ts` files
- Clear test database before seeding

### 4. Flaky Tests

**Symptoms:**
- Test passes locally, fails in CI
- Intermittent failures
- Different results on retries

**Causes:**
- Race conditions
- Timing dependencies
- Shared state between tests
- Hard-coded waits

**Solutions:**
- Use `test.describe.serial()` for dependent tests
- Reset state in `beforeEach`/`afterEach`
- Replace `page.waitForTimeout(1000)` with proper assertions
- Use `expect(locator).toBeVisible()` with auto-retry

### 5. Screenshot/Video Failures

**Error:**
```
Error: Failed to capture screenshot
```

**Causes:**
- Insufficient disk space
- Permission issues
- Headless browser limitations

**Solutions:**
- Check available disk space on runner
- Verify output directory permissions
- Use `--headed` mode for local debugging

## GitHub Actions Integration

### Useful Commands

**List PR checks:**
```bash
gh pr checks
```

**View workflow run:**
```bash
gh run view <run_id>
gh run view <run_id> --log
gh run view <run_id> --log --job <job_id>
```

**Download artifacts:**
```bash
# List artifacts for a run
gh run view <run_id> --json artifacts

# Download specific artifact
gh run download <run_id> -n <artifact-name>

# Download all artifacts
gh run download <run_id>
```

**Find recent workflow runs:**
```bash
# List runs for current branch
gh run list --branch <branch-name>

# List runs for specific workflow
gh run list --workflow "Nightly Tests"

# Filter by status
gh run list --status failure
```

### Environment Variables in CI

**Playwright Base URLs:**
- `WORKFLOW_BASE_URL` - Workflow application URL (defaults to `http://localhost:4200`)

**GitHub Context:**
- `CI=true` - Enables CI mode (affects retries, workers)
- `GITHUB_ACTIONS=true` - Indicates GitHub Actions environment

**Custom Variables:**
- `ENFORCE_E2E_RESULT` - Whether to fail job on E2E failure

### Runner Types

**PR Workflow Runners:**
- `light-runners` - For lightweight tasks (label checks)
- `arc-runner-set` - For deployment and CI tasks
- `medium-dev-runners` - For longer-running tasks

**ATT Runners:**
- `att-nprd-runners` - Non-production environment
- `att-pst-runners` - PST environment
- `att-sit-runners` - SIT environment
- `att-e2e-runners` - E2E environment

## Nx E2E Target Configuration

**Executor:** `@nx/playwright:playwright`

**Workflow E2E Project Configuration:**
```json
{
  "targets": {
    "e2e": {
      "executor": "@nx/playwright:playwright",
      "options": {
        "config": "tests/workflow/typescript/playwright.config.ts"
      },
      "outputs": [
        "{workspaceRoot}/reports/typescript-playwright/workflow"
      ]
    }
  }
}
```

**Common Commands:**
```bash
# Run workflow E2E tests
nx e2e tests-workflow-typescript

# Run affected E2E tests
nx affected -t e2e --base=origin/main

# Run with specific project
nx e2e tests-workflow-typescript --project=e2e
```

## Troubleshooting Tips

### Debugging Locally

1. **Enable trace on all actions:**
   ```typescript
   use: {
     trace: 'on'  // Instead of 'retain-on-failure'
   }
   ```

2. **Run with UI mode:**
   ```bash
   npx playwright test --ui
   ```

3. **Run headed for visual debugging:**
   ```bash
   npx playwright test --headed --project=e2e
   ```

4. **Debug specific test:**
   ```bash
   npx playwright test --debug tests/e2e/builder/workflow-builder.e2e.spec.ts
   ```

### Debugging in CI

1. **Enable verbose logging in workflow:**
   - Add `ACTIONS_STEP_DEBUG: true` secret to repo
   - Re-run workflow to see detailed logs

2. **Check test artifacts:**
   - Download HTML report for interactive inspection
   - Review screenshots and videos
   - Open trace files in Playwright Trace Viewer

3. **Compare with local:**
   - Run same test locally with same base URL
   - Check for environment-specific issues
   - Verify environment variables match CI

4. **Review job logs:**
   - Look for setup errors before test execution
   - Check for network connectivity issues
   - Verify database seeding completed

## Related Files

- `.github/workflows/dispatcher.yml` - PR workflow entry point
- `.github/workflows/pr-core.yaml` - PR core logic
- `dap-workspace/tests/workflow/typescript/playwright.config.ts` - Main Playwright config
- `dap-workspace/tests/workflow/typescript/seed/*.setup.ts` - Database seeding
