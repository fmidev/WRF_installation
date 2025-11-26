#!/bin/bash

#########################################################################
######## Deploy Test Scripts to Production #####
# Deploys changes from WRF_test scripts to production WRF
# Author: Mikael Hasu
# Date: November 2025
#########################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check if we're in a git repository
if ! git -C "${REPO_ROOT}" rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Get the base directories from environment
if [ -f "${SCRIPT_DIR}/env.sh" ]; then
    source "${SCRIPT_DIR}/env.sh"
else
    echo -e "${RED}Error: env.sh not found${NC}"
    exit 1
fi

# Define test base directory (assuming it's parallel to production)
TEST_BASE_DIR="$(dirname ${BASE_DIR})/WRF_test"
PROD_BASE_DIR="${BASE_DIR}"

# Check if test directory exists
if [ ! -d "$TEST_BASE_DIR" ]; then
    echo -e "${RED}Error: Test directory not found: $TEST_BASE_DIR${NC}"
    exit 1
fi

echo "========================================================================="
echo "Deploying Test Scripts to Production"
echo "========================================================================="
echo "Production BASE_DIR: ${PROD_BASE_DIR}"
echo "Test BASE_DIR:       ${TEST_BASE_DIR}"
echo ""

# Discover what exists under WRF_test
echo "Discovering test directories..."
TEST_DIRS=()
for dir in "${TEST_BASE_DIR}"/*; do
    if [ -d "$dir" ]; then
        dirname=$(basename "$dir")
        echo "  Found: ${dirname}/"
        TEST_DIRS+=("$dirname")
    fi
done
echo ""

# Files to exclude from deployment (test-specific files)
EXCLUDE_FILES=(
    "verification_test.sh"
    "deploy_test_to_prod.sh"
)

# Special files that need name mapping
declare -A FILE_MAPPINGS=(
    ["env_test.sh"]="env.sh"
)

# Function to check if file should be excluded
should_exclude() {
    local filename="$1"
    for exclude in "${EXCLUDE_FILES[@]}"; do
        if [[ "$filename" == "$exclude" ]]; then
            return 0  # true, should exclude
        fi
    done
    return 1  # false, should not exclude
}

# Function to replace paths in file content
replace_paths() {
    local content="$1"
    
    # Replace test paths with production paths
    # Handle various path patterns
    content=$(echo "$content" | sed "s|${TEST_BASE_DIR}|${BASE_DIR}|g")
    content=$(echo "$content" | sed "s|WRF_test|WRF_Model|g")
    content=$(echo "$content" | sed 's|TEST_BASE_DIR|BASE_DIR|g')
    content=$(echo "$content" | sed 's|env_test\.sh|env.sh|g')
    
     
    echo "$content"
}

# Function to get destination filename (handles special mappings)
get_dest_filename() {
    local src_filename="$1"
    
    # Check if there's a special mapping for this file
    if [ -n "${FILE_MAPPINGS[$src_filename]}" ]; then
        echo "${FILE_MAPPINGS[$src_filename]}"
    else
        echo "$src_filename"
    fi
}

# Function to deploy a single file
deploy_file() {
    local src_file="$1"
    local dest_dir="$2"
    local src_filename=$(basename "$src_file")
    
    # Check if file should be excluded
    if should_exclude "$src_filename"; then
        echo -e "${YELLOW}  Skipping: $src_filename (excluded)${NC}"
        return
    fi
    
    # Get destination filename (may be different for special files)
    local dest_filename=$(get_dest_filename "$src_filename")
    local dest_file="${dest_dir}/${dest_filename}"
    
    # Read source file
    if [ ! -f "$src_file" ]; then
        echo -e "${RED}  Error: Source file not found: $src_file${NC}"
        return 1
    fi
    
    local content=$(cat "$src_file")
    
    # Replace paths
    local updated_content=$(replace_paths "$content")
    
    # Check if destination file exists and compare
    if [ -f "$dest_file" ]; then
        local dest_content=$(cat "$dest_file")
        if [ "$updated_content" = "$dest_content" ]; then
            echo -e "  ${GREEN}✓${NC} No changes: $src_filename → $dest_filename"
            return
        else
            echo -e "  ${YELLOW}↻${NC} Updating: $src_filename → $dest_filename"
        fi
    else
        echo -e "  ${GREEN}+${NC} Creating: $src_filename → $dest_filename"
    fi
    
    # Write updated content to destination
    echo "$updated_content" > "$dest_file"
    
    # Preserve execute permissions
    if [ -x "$src_file" ]; then
        chmod +x "$dest_file"
    fi
}

# Function to recursively deploy scripts from a directory
deploy_directory() {
    local src_dir="$1"
    local dest_dir="$2"
    local rel_path="$3"  # Relative path for display
    
    if [ ! -d "$src_dir" ]; then
        return
    fi
    
    # Create destination directory if it doesn't exist
    mkdir -p "$dest_dir"
    
    # Deploy files in current directory
    local file_count=0
    for src_file in "$src_dir"/*.sh "$src_dir"/*.py "$src_dir"/*.R; do
        if [ -f "$src_file" ]; then
            deploy_file "$src_file" "$dest_dir"
            ((file_count++))
        fi
    done
    
    # Recursively process subdirectories
    for subdir in "$src_dir"/*; do
        if [ -d "$subdir" ]; then
            local subdir_name=$(basename "$subdir")
            local new_rel_path="${rel_path}/${subdir_name}"
            deploy_directory "$subdir" "$dest_dir/$subdir_name" "$new_rel_path"
        fi
    done
}

# Main deployment
echo ""
echo "Starting deployment..."

# Dynamically deploy all discovered directories
DEPLOYED_DIRS=()
for test_dir_name in "${TEST_DIRS[@]}"; do
    TEST_DIR="${TEST_BASE_DIR}/${test_dir_name}"
    PROD_DIR="${PROD_BASE_DIR}/${test_dir_name}"
    
    echo ""
    echo "=========================================="
    echo "Deploying: ${test_dir_name}/"
    echo "  From: ${TEST_DIR}"
    echo "  To:   ${PROD_DIR}"
    echo "=========================================="
    
    deploy_directory "$TEST_DIR" "$PROD_DIR" "$test_dir_name"
    DEPLOYED_DIRS+=("$PROD_DIR")
done

echo ""
echo "========================================================================="
echo "Checking git status..."
echo "========================================================================="

# Check if there are any changes
cd "${REPO_ROOT}"
if git diff --quiet && git diff --cached --quiet; then
    echo -e "${GREEN}No changes to commit${NC}"
    echo "All files are already in sync with production paths"
    exit 0
fi

# Show changes
echo ""
echo "Changes detected:"
git status --short

echo ""
echo "Detailed diff:"
git diff

# Prompt for commit
echo ""
echo "========================================================================="
read -p "Do you want to commit these changes? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled. Changes are staged but not committed.${NC}"
    exit 0
fi

# Get commit message
echo ""
echo "Enter commit message (or press Enter for default):"
read -r commit_msg

if [ -z "$commit_msg" ]; then
    commit_msg="Deploy: Sync test scripts to production with path corrections"
fi

# Add all changes in deployed production directories
for prod_dir in "${DEPLOYED_DIRS[@]}"; do
    if [ -d "$prod_dir" ]; then
        # Add all script files recursively
        find "$prod_dir" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.R" \) -exec git add {} \; 2>/dev/null || true
    fi
done

# Commit
if git commit -m "$commit_msg"; then
    echo ""
    echo -e "${GREEN}=========================================================================${NC}"
    echo -e "${GREEN}Deployment successful!${NC}"
    echo -e "${GREEN}=========================================================================${NC}"
    echo ""
    echo "Committed changes with message: '$commit_msg'"
    echo ""
    echo "Latest commit:"
    git log -1 --oneline
    echo ""
    echo -e "${YELLOW}Note: Changes are committed locally. Don't forget to push to remote!${NC}"
    echo "  git push origin $(git branch --show-current)"
else
    echo -e "${RED}Error: Commit failed${NC}"
    exit 1
fi
