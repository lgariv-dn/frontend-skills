# E2E CI Debug Scripts

Utility scripts for debugging Playwright E2E test failures from CI.

## Scripts Overview

### 1. download-artifacts.sh

Downloads Playwright test artifacts from GitHub Actions.

**Usage:**
```bash
# Auto-detect from current PR
./download-artifacts.sh

# Specify run ID
./download-artifacts.sh <run_id>

# Specify run ID and artifact name
./download-artifacts.sh <run_id> <artifact_name>

# Show help
./download-artifacts.sh --help
```

**Prerequisites:**
- GitHub CLI (`gh`) must be installed and authenticated
- Must be run from within the git repository

**Output:**
- Downloads artifacts to `playwright-results/` directory
- Automatically extracts ZIP archives

### 2. parse-junit.py

Parses JUnit XML files from Playwright results and extracts structured failure information, including paths to failure screenshots that AI models can analyze.

**Usage:**
```bash
# Auto-detect junit.xml files
./parse-junit.py

# Parse specific file
./parse-junit.py path/to/junit.xml

# Output as JSON (includes screenshot/trace/video paths)
./parse-junit.py --json

# Show screenshot paths for AI model analysis
./parse-junit.py --screenshots

# Open HTML report in browser after parsing
./parse-junit.py --open-report

# Show help
./parse-junit.py --help
```

**Prerequisites:**
- Python 3.6 or higher
- No additional dependencies required (uses stdlib only)

**Output Formats:**
- **Text (default):** Human-readable summary with colors and emojis
- **JSON (`--json`):** Structured output with artifact paths for programmatic consumption

**Output includes:**
- Test summary (passed/failed/error/skipped counts)
- Detailed failure information (error message, file location, stack trace)
- **Screenshot paths** (absolute paths to failure screenshots)
- **Trace paths** (Playwright trace files for debugging)
- **Video paths** (if video recording was enabled)
- Local reproduction commands

**AI Model Integration:**
Screenshot paths are absolute, allowing AI models to directly read the images using the Read tool:
```bash
# Get JSON with screenshot paths
./parse-junit.py --json | jq '.failures[].screenshots[]'

# Then use the Read tool on each path to analyze the screenshots
```

### 3. find-failing-job.sh

Finds failing E2E jobs from PR workflow runs.

**Usage:**
```bash
# Search for PR workflow failures
./find-failing-job.sh

# Search specific workflow
./find-failing-job.sh "Workflow Name"

# Show help
./find-failing-job.sh --help
```

**Prerequisites:**
- GitHub CLI (`gh`) must be installed and authenticated
- Works on both macOS and Linux (cross-platform date formatting)

**Features:**
- Lists recent PR workflow runs with status
- Identifies failed E2E jobs
- Provides download and log viewing commands
- Interactive mode for analyzing specific runs

### 4. cleanup-artifacts.sh

Removes all downloaded Playwright artifacts after debugging is complete.

**Usage:**
```bash
# Clean all artifacts
./cleanup-artifacts.sh

# Preview what would be cleaned
./cleanup-artifacts.sh --dry-run

# Show help
./cleanup-artifacts.sh --help
```

**Safety:**
- Only removes E2E-related files
- Idempotent (safe to run multiple times)
- Provides feedback on freed disk space

**What it removes:**
- `playwright-results/` directory
- E2E-related ZIP files
- Temporary test directories

## Complete Debugging Workflow

1. **Download artifacts from failed CI run:**
   ```bash
   ./download-artifacts.sh
   ```

2. **Parse failures to identify issues:**
   ```bash
   ./parse-junit.py
   ```

3. **Reproduce locally:**
   ```bash
   cd dap-workspace
   nx affected -t e2e --base=origin/main
   # Or run specific test shown by parse-junit.py
   ```

4. **Clean up after debugging:**
   ```bash
   ./cleanup-artifacts.sh
   ```

## Troubleshooting

### "gh: command not found"

Install GitHub CLI:
- macOS: `brew install gh`
- Linux: See https://cli.github.com/
- Windows: See https://cli.github.com/

Then authenticate:
```bash
gh auth login
```

### "No artifacts found"

Possible causes:
- Artifacts have expired (GitHub Actions artifacts expire after 90 days by default)
- Wrong run ID specified
- E2E tests didn't run in that workflow

Use `gh run view <run_id>` to check if artifacts are available.

### "junit.xml not found"

Possible causes:
- Artifacts not downloaded yet (run `download-artifacts.sh` first)
- Wrong directory (script searches common locations)
- Tests didn't generate JUnit output

Specify the path explicitly:
```bash
./parse-junit.py path/to/junit.xml
```

## Script Permissions

All scripts should be executable. If you get "Permission denied", run:

```bash
chmod +x *.sh *.py
```

## Related Documentation

- [SKILL.md](../SKILL.md) - Main skill documentation
- [reference.md](../reference.md) - Detailed technical reference
