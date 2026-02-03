#!/bin/bash
# AI Generated file
# Remove all downloaded Playwright E2E test artifacts after debugging
# Usage: ./cleanup-artifacts.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories and files to clean up
ARTIFACTS_DIR="playwright-results"
ZIP_PATTERN="*-playwright-results.zip"
TEMP_PATTERN="*-test-results.zip"

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

# Function to get human-readable size
get_size() {
    local path=$1
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | awk '{print $1}'
    elif [ -f "$path" ]; then
        du -h "$path" 2>/dev/null | awk '{print $1}'
    else
        echo "0B"
    fi
}

# Function to count files recursively
count_files() {
    local path=$1
    if [ -d "$path" ]; then
        find "$path" -type f 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Function to clean artifacts directory
clean_artifacts_dir() {
    if [ -d "$ARTIFACTS_DIR" ]; then
        local size
        size=$(get_size "$ARTIFACTS_DIR")
        local file_count
        file_count=$(count_files "$ARTIFACTS_DIR")
        
        print_info "Found artifacts directory: ${ARTIFACTS_DIR}/"
        echo "  Size: ${size}"
        echo "  Files: ${file_count}"
        
        rm -rf "$ARTIFACTS_DIR"
        print_success "Removed ${ARTIFACTS_DIR}/ (freed ${size})"
        return 0
    else
        print_info "No artifacts directory found"
        return 1
    fi
}

# Function to clean ZIP files
clean_zip_files() {
    local found=0
    local total_size=0
    
    # Find all matching ZIP files
    shopt -s nullglob
    local zip_files=($ZIP_PATTERN $TEMP_PATTERN *.zip)
    shopt -u nullglob
    
    # Filter to only E2E-related zips
    local e2e_zips=()
    for zip_file in "${zip_files[@]}"; do
        if [[ "$zip_file" =~ (playwright|e2e|test|nightly|pytest) ]]; then
            e2e_zips+=("$zip_file")
        fi
    done
    
    if [ ${#e2e_zips[@]} -gt 0 ]; then
        print_info "Found ${#e2e_zips[@]} E2E-related ZIP file(s):"
        
        for zip_file in "${e2e_zips[@]}"; do
            if [ -f "$zip_file" ]; then
                local size
                size=$(get_size "$zip_file")
                echo "  - ${zip_file} (${size})"
                
                rm -f "$zip_file"
                found=$((found + 1))
            fi
        done
        
        print_success "Removed ${found} ZIP file(s)"
        return 0
    else
        print_info "No E2E-related ZIP files found"
        return 1
    fi
}

# Function to clean other temporary files
clean_temp_files() {
    local found=0
    
    # Look for other common test artifact patterns
    local patterns=(
        "test-results"
        "playwright-report"
        ".playwright"
    )
    
    for pattern in "${patterns[@]}"; do
        if [ -d "$pattern" ] || [ -f "$pattern" ]; then
            local size
            size=$(get_size "$pattern")
            
            print_info "Found temporary: ${pattern}"
            echo "  Size: ${size}"
            
            rm -rf "$pattern"
            found=$((found + 1))
        fi
    done
    
    if [ $found -gt 0 ]; then
        print_success "Removed ${found} temporary item(s)"
        return 0
    else
        return 1
    fi
}

# Function to show what would be cleaned (dry run)
dry_run() {
    print_header "\n🔍 Dry Run - Items that would be cleaned:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_size=0
    local total_items=0
    
    # Check artifacts directory
    if [ -d "$ARTIFACTS_DIR" ]; then
        local size
        size=$(get_size "$ARTIFACTS_DIR")
        local file_count
        file_count=$(count_files "$ARTIFACTS_DIR")
        
        echo "📁 ${ARTIFACTS_DIR}/"
        echo "   Size: ${size}"
        echo "   Files: ${file_count}"
        echo ""
        total_items=$((total_items + 1))
    fi
    
    # Check ZIP files
    shopt -s nullglob
    local zip_files=($ZIP_PATTERN $TEMP_PATTERN *.zip)
    shopt -u nullglob
    
    local e2e_zips=()
    for zip_file in "${zip_files[@]}"; do
        if [[ "$zip_file" =~ (playwright|e2e|test|nightly|pytest) ]]; then
            e2e_zips+=("$zip_file")
        fi
    done
    
    if [ ${#e2e_zips[@]} -gt 0 ]; then
        echo "📦 ZIP Files:"
        for zip_file in "${e2e_zips[@]}"; do
            if [ -f "$zip_file" ]; then
                local size
                size=$(get_size "$zip_file")
                echo "   - ${zip_file} (${size})"
                total_items=$((total_items + 1))
            fi
        done
        echo ""
    fi
    
    # Check temp files
    local patterns=("test-results" "playwright-report" ".playwright")
    local found_temp=0
    
    for pattern in "${patterns[@]}"; do
        if [ -d "$pattern" ] || [ -f "$pattern" ]; then
            if [ $found_temp -eq 0 ]; then
                echo "🗑️  Temporary Files:"
                found_temp=1
            fi
            local size
            size=$(get_size "$pattern")
            echo "   - ${pattern} (${size})"
            total_items=$((total_items + 1))
        fi
    done
    
    if [ $total_items -eq 0 ]; then
        print_info "No items to clean"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_warning "Total items: ${total_items}"
    fi
}

# Main script
main() {
    local dry_run_mode=false
    
    # Check for dry-run flag
    if [ "$1" = "--dry-run" ] || [ "$1" = "-n" ]; then
        dry_run_mode=true
    fi
    
    print_header "\n🧹 E2E Artifacts Cleanup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$dry_run_mode" = true ]; then
        dry_run
        echo ""
        print_info "Run without --dry-run to actually remove files"
        exit 0
    fi
    
    # Track what was cleaned
    local cleaned_something=false
    
    # Clean artifacts directory
    if clean_artifacts_dir; then
        cleaned_something=true
    fi
    echo ""
    
    # Clean ZIP files
    if clean_zip_files; then
        cleaned_something=true
    fi
    echo ""
    
    # Clean temporary files
    if clean_temp_files; then
        cleaned_something=true
    fi
    echo ""
    
    # Final message
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$cleaned_something" = true ]; then
        print_success "Cleanup complete!"
        echo ""
        print_info "Your workspace is clean and ready for the next debug session"
    else
        print_info "Nothing to clean - workspace is already clean"
    fi
    
    echo ""
}

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "E2E Artifacts Cleanup Script"
    echo ""
    echo "Usage:"
    echo "  ./cleanup-artifacts.sh           # Clean all E2E artifacts"
    echo "  ./cleanup-artifacts.sh --dry-run # Preview what would be cleaned"
    echo "  ./cleanup-artifacts.sh --help    # Show this help"
    echo ""
    echo "What gets cleaned:"
    echo "  - playwright-results/ directory"
    echo "  - E2E-related ZIP files (*-playwright-results.zip, etc.)"
    echo "  - Temporary test directories (test-results, playwright-report)"
    echo ""
    echo "Safety:"
    echo "  - Only removes E2E-related files (not your source code!)"
    echo "  - Idempotent (safe to run multiple times)"
    echo "  - Use --dry-run to preview before cleaning"
    exit 0
fi

main "$@"
