#!/bin/bash
# AI Generated file
# Download Playwright E2E test artifacts from GitHub Actions
# Usage: ./download-artifacts.sh [run_id] [artifact_name]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Output directory
OUTPUT_DIR="playwright-results"

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

# Function to get current PR number
get_current_pr() {
    local pr_number
    pr_number=$(gh pr view --json number -q .number 2>/dev/null || echo "")
    echo "$pr_number"
}

# Function to get latest run ID for current PR
get_latest_pr_run() {
    local pr_number=$1
    local run_id
    
    print_info "Finding latest workflow run for PR #${pr_number}..."
    
    # Get the branch name for this PR
    local branch
    branch=$(gh pr view "$pr_number" --json headRefName -q .headRefName)
    
    # Get latest run for this branch
    run_id=$(gh run list --branch "$branch" --limit 1 --json databaseId -q '.[0].databaseId')
    
    if [ -z "$run_id" ]; then
        print_error "No workflow runs found for PR #${pr_number}"
        exit 1
    fi
    
    echo "$run_id"
}

# Function to list artifacts for a run
list_artifacts() {
    local run_id=$1
    
    print_info "Artifacts available for run ${run_id}:"
    gh run view "$run_id" --json artifacts -q '.artifacts[] | "  - \(.name) (expired: \(.expired))"'
}

# Function to download artifact
download_artifact() {
    local run_id=$1
    local artifact_name=$2
    
    print_info "Downloading artifact: ${artifact_name} from run ${run_id}..."
    
    # Create temp directory for download
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Download artifact
    if gh run download "$run_id" -n "$artifact_name" -D "$temp_dir" 2>/dev/null; then
        print_success "Downloaded artifact to ${temp_dir}"
        
        # Check if it's a zip file
        if find "$temp_dir" -name "*.zip" -type f | grep -q .; then
            print_info "Extracting ZIP files..."
            
            # Extract all zip files
            for zipfile in "$temp_dir"/*.zip; do
                if [ -f "$zipfile" ]; then
                    local zip_name
                    zip_name=$(basename "$zipfile")
                    print_info "Extracting ${zip_name}..."
                    
                    unzip -q "$zipfile" -d "$OUTPUT_DIR" 2>/dev/null || {
                        print_warning "Failed to extract ${zip_name}, copying as-is"
                        cp "$zipfile" .
                    }
                    
                    print_success "Extracted to ${OUTPUT_DIR}/"
                fi
            done
        else
            # Not a zip, just copy the contents
            print_info "Copying artifact contents..."
            mkdir -p "$OUTPUT_DIR"
            cp -r "$temp_dir"/* "$OUTPUT_DIR/"
            print_success "Copied to ${OUTPUT_DIR}/"
        fi
        
        # Clean up temp directory
        rm -rf "$temp_dir"
        
        return 0
    else
        print_error "Failed to download artifact: ${artifact_name}"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to find and download E2E artifacts
download_e2e_artifacts() {
    local run_id=$1
    
    print_info "Searching for E2E test artifacts in run ${run_id}..."
    
    # Get list of artifacts
    local artifacts
    artifacts=$(gh run view "$run_id" --json artifacts -q '.artifacts[] | select(.expired == false) | .name')
    
    if [ -z "$artifacts" ]; then
        print_error "No artifacts found for run ${run_id}"
        return 1
    fi
    
    # Look for E2E-related artifacts
    local found=0
    while IFS= read -r artifact_name; do
        # Match common E2E artifact patterns
        if [[ "$artifact_name" =~ (e2e|playwright|nightly-pytest|test-results) ]]; then
            print_info "Found E2E artifact: ${artifact_name}"
            
            if download_artifact "$run_id" "$artifact_name"; then
                found=$((found + 1))
            fi
        fi
    done <<< "$artifacts"
    
    if [ $found -eq 0 ]; then
        print_warning "No E2E artifacts matched common patterns"
        echo ""
        echo "Available artifacts:"
        list_artifacts "$run_id"
        echo ""
        print_info "Specify artifact name manually: $0 $run_id <artifact_name>"
        return 1
    fi
    
    print_success "Downloaded ${found} E2E artifact(s)"
    return 0
}

# Main script
main() {
    check_gh_cli
    
    local run_id=$1
    local artifact_name=$2
    
    # If no run_id provided, try to get from current PR
    if [ -z "$run_id" ]; then
        local pr_number
        pr_number=$(get_current_pr)
        
        if [ -z "$pr_number" ]; then
            print_error "Not in a PR context and no run_id provided"
            echo ""
            echo "Usage:"
            echo "  $0                    # Auto-detect from current PR"
            echo "  $0 <run_id>          # Download E2E artifacts from specific run"
            echo "  $0 <run_id> <name>   # Download specific artifact by name"
            exit 1
        fi
        
        print_info "Detected PR #${pr_number}"
        run_id=$(get_latest_pr_run "$pr_number")
        print_info "Using latest run: ${run_id}"
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # If artifact name provided, download it directly
    if [ -n "$artifact_name" ]; then
        if download_artifact "$run_id" "$artifact_name"; then
            print_success "Artifact downloaded successfully!"
            echo ""
            print_info "Next steps:"
            echo "  1. Parse failures: .cursor/skills/e2e-ci-debug/scripts/parse-junit.py"
            echo "  2. Clean up: .cursor/skills/e2e-ci-debug/scripts/cleanup-artifacts.sh"
        else
            exit 1
        fi
    else
        # Try to find and download E2E artifacts automatically
        if download_e2e_artifacts "$run_id"; then
            print_success "E2E artifacts downloaded successfully!"
            echo ""
            print_info "Artifacts saved to: ${OUTPUT_DIR}/"
            echo ""
            print_info "Next steps:"
            echo "  1. Parse failures: .cursor/skills/e2e-ci-debug/scripts/parse-junit.py"
            echo "  2. Clean up: .cursor/skills/e2e-ci-debug/scripts/cleanup-artifacts.sh"
        else
            exit 1
        fi
    fi
}

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Download E2E Artifacts Script"
    echo ""
    echo "Usage:"
    echo "  ./download-artifacts.sh              # Auto-detect from current PR"
    echo "  ./download-artifacts.sh <run_id>     # Download E2E artifacts from specific run"
    echo "  ./download-artifacts.sh <run_id> <name>  # Download specific artifact by name"
    echo "  ./download-artifacts.sh --help       # Show this help"
    echo ""
    echo "What it does:"
    echo "  - Fetches Playwright report archives from GitHub Actions"
    echo "  - Extracts to playwright-results/ directory"
    echo "  - Cleans up ZIP files after extraction"
    echo ""
    echo "Prerequisites:"
    echo "  - GitHub CLI (gh) must be installed and authenticated"
    echo "  - Must be run from within the git repository"
    exit 0
fi

main "$@"
