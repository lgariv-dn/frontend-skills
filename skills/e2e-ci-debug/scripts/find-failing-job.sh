#!/bin/bash
# AI Generated file
# Find failing E2E jobs from PR workflow runs
# Usage: ./find-failing-job.sh [workflow_name]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default workflow name
DEFAULT_WORKFLOW="PR Deploy Core"

# Function to print colored output
print_info() {
    echo -e "${GREEN}ℹ${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Function to check if gh CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub CLI"
        echo "Run: gh auth login"
        exit 1
    fi
}

# Function to list recent workflow runs
list_recent_runs() {
    local workflow_name=$1
    local limit=${2:-10}
    
    print_header "\n📋 Recent Workflow Runs: ${workflow_name}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get recent runs with status
    local runs
    runs=$(gh run list --workflow "$workflow_name" --limit "$limit" --json databaseId,status,conclusion,displayTitle,createdAt,headBranch)
    
    if [ -z "$runs" ] || [ "$runs" = "[]" ]; then
        print_warning "No workflow runs found for '${workflow_name}'"
        echo ""
        print_info "Available workflows:"
        gh workflow list
        return 1
    fi
    
    # Parse and display runs
    echo "$runs" | jq -r '.[] | 
        "\(.databaseId)\t\(.status)\t\(.conclusion // "N/A")\t\(.headBranch)\t\(.displayTitle)\t\(.createdAt)"' | \
    while IFS=$'\t' read -r run_id status conclusion branch title created_at; do
        # Format status with color
        local status_icon=""
        local status_color=""
        
        case "$conclusion" in
            "success")
                status_icon="✓"
                status_color="${GREEN}"
                ;;
            "failure")
                status_icon="✗"
                status_color="${RED}"
                ;;
            "cancelled")
                status_icon="⊝"
                status_color="${YELLOW}"
                ;;
            *)
                if [ "$status" = "in_progress" ]; then
                    status_icon="⟳"
                    status_color="${BLUE}"
                else
                    status_icon="?"
                    status_color="${NC}"
                fi
                ;;
        esac
        
        # Format date (cross-platform: try GNU date first, fall back to macOS, then raw)
        local date_formatted
        if date --version >/dev/null 2>&1; then
            # GNU date (Linux)
            date_formatted=$(date -d "$created_at" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created_at")
        else
            # BSD/macOS date
            date_formatted=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created_at")
        fi
        
        # Print run info
        printf "${status_color}${status_icon}${NC} Run %-8s  Status: %-12s  Branch: %-20s  %s\n" \
            "$run_id" \
            "$status/$conclusion" \
            "$branch" \
            "$date_formatted"
    done
    
    echo ""
}

# Function to find E2E job in a workflow run
find_e2e_job() {
    local run_id=$1
    
    print_info "Searching for E2E jobs in run ${run_id}..."
    
    # Get jobs for this run
    local jobs
    jobs=$(gh run view "$run_id" --json jobs -q '.jobs[] | {id: .databaseId, name: .name, status: .status, conclusion: .conclusion}')
    
    if [ -z "$jobs" ]; then
        print_error "No jobs found for run ${run_id}"
        return 1
    fi
    
    # Look for E2E-related jobs
    local e2e_jobs
    e2e_jobs=$(echo "$jobs" | jq -s '[.[] | select(.name | test("e2e|E2E|test|Test"; "i"))]')
    
    if [ "$e2e_jobs" = "[]" ]; then
        print_warning "No E2E jobs found in run ${run_id}"
        echo ""
        print_info "Available jobs:"
        echo "$jobs" | jq -r '.name'
        return 1
    fi
    
    # Display E2E jobs
    print_success "Found E2E jobs:"
    echo ""
    
    echo "$e2e_jobs" | jq -r '.[] | 
        "  Job ID: \(.id)\n  Name: \(.name)\n  Status: \(.status)\n  Conclusion: \(.conclusion // "N/A")\n"'
    
    # Find failed E2E jobs
    local failed_jobs
    failed_jobs=$(echo "$e2e_jobs" | jq -r '.[] | select(.conclusion == "failure") | .id')
    
    if [ -n "$failed_jobs" ]; then
        print_header "\n❌ Failed E2E Jobs:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        while IFS= read -r job_id; do
            local job_info
            job_info=$(echo "$e2e_jobs" | jq -r ".[] | select(.id == $job_id)")
            local job_name
            job_name=$(echo "$job_info" | jq -r '.name')
            
            echo ""
            print_error "Job: ${job_name} (ID: ${job_id})"
            echo ""
            print_info "Download artifacts:"
            echo "  .cursor/skills/e2e-ci-debug/scripts/download-artifacts.sh ${run_id}"
            echo ""
            print_info "View logs:"
            echo "  gh run view ${run_id} --log --job ${job_id}"
        done <<< "$failed_jobs"
        
        return 0
    else
        print_info "No failed E2E jobs found"
        return 1
    fi
}

# Function to analyze specific run
analyze_run() {
    local run_id=$1
    
    print_header "\n🔍 Analyzing Run ${run_id}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get run details
    local run_info
    run_info=$(gh run view "$run_id" --json status,conclusion,displayTitle,createdAt,headBranch,event)
    
    if [ -z "$run_info" ]; then
        print_error "Run ${run_id} not found"
        return 1
    fi
    
    # Display run info
    echo "$run_info" | jq -r '
        "Status: \(.status)",
        "Conclusion: \(.conclusion // "N/A")",
        "Title: \(.displayTitle)",
        "Branch: \(.headBranch)",
        "Event: \(.event)",
        "Created: \(.createdAt)"
    '
    
    echo ""
    
    # Find E2E jobs
    find_e2e_job "$run_id"
}

# Main script
main() {
    check_gh_cli
    
    local workflow_name="${1:-$DEFAULT_WORKFLOW}"
    
    # List recent runs
    if ! list_recent_runs "$workflow_name" 10; then
        exit 1
    fi
    
    # Prompt for run ID or analyze failed runs
    print_info "Find failures in recent runs? (Enter run ID or 'all' to check all, or press Enter to exit)"
    read -r response
    
    if [ -z "$response" ]; then
        exit 0
    fi
    
    if [ "$response" = "all" ]; then
        # Analyze all failed runs
        print_header "\n🔍 Analyzing All Failed Runs"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local failed_runs
        failed_runs=$(gh run list --workflow "$workflow_name" --limit 10 --json databaseId,conclusion | \
            jq -r '.[] | select(.conclusion == "failure") | .databaseId')
        
        if [ -z "$failed_runs" ]; then
            print_info "No failed runs found"
            exit 0
        fi
        
        while IFS= read -r run_id; do
            analyze_run "$run_id"
            echo ""
        done <<< "$failed_runs"
    else
        # Analyze specific run
        analyze_run "$response"
    fi
}

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Find Failing E2E Jobs Script"
    echo ""
    echo "Usage:"
    echo "  ./find-failing-job.sh                    # Search default workflow"
    echo "  ./find-failing-job.sh \"Workflow Name\"    # Search specific workflow"
    echo "  ./find-failing-job.sh --help             # Show this help"
    echo ""
    echo "What it does:"
    echo "  - Lists recent PR workflow runs with status"
    echo "  - Identifies failed E2E jobs"
    echo "  - Provides download and log viewing commands"
    echo "  - Interactive mode for analyzing specific runs"
    echo ""
    echo "Prerequisites:"
    echo "  - GitHub CLI (gh) must be installed and authenticated"
    exit 0
fi

main "$@"
