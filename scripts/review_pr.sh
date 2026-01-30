#!/bin/bash

# =============================================================================
# PR REVIEW SCRIPT - AI CODE REVIEW WORKFLOW
# =============================================================================
#
# This script generates a comprehensive review document for AI analysis.
# Follow these steps to get detailed feedback on your code changes:
#
# STEP 1: Run the Review Script
# -----------------------------
# Basic usage - generates reviews/pr_review_for_cursor.txt
# ./scripts/review_pr.sh your-feature-branch main
#
# With custom output filename (saved under reviews/ automatically)
# ./scripts/review_pr.sh your-feature-branch main my_pr_review.txt
#
# Examples for different scenarios:
# ./scripts/review_pr.sh feat/user-authentication develop auth_review.txt
# ./scripts/review_pr.sh bugfix/login-validation main login_fix_review.txt
# ./scripts/review_pr.sh origin/feature-x upstream/main fork_review.txt
#
# STEP 2: Copy Content to LLM IDE (e.g. Curosr or AntiGravity) for AI Review
# ---------------------------------------------
# 1. Open the generated review file (e.g., pr_review_for_cursor.txt)
# 2. Copy the entire content of the file
# 3. Paste it into to LLM IDE (e.g. Curosr or AntiGravity) and ask the AI to review it
# 4. The AI will analyze your code changes and provide detailed feedback
#
# STEP 3: Review the AI Analysis
# ------------------------------
# The AI will provide a comprehensive review that includes:
# - Changes Overview: Analysis of all modified files with statistics
# - GitHub-style Diffs: Detailed review of each file's changes
# - Review Instructions: Feedback based on the 4 review rules
# - Summary Table: Issues found that need your attention
#
# STEP 4: Use Markdown Preview
# ----------------------------
# 1. Use Markdown Preview in to LLM IDE (e.g. Curosr or AntiGravity) to view the AI's formatted response
# 2. Review the suggestions and recommendations
# 3. Copy the Review Summary table from the AI's response
#
# STEP 5: Update Your PR Description
# ----------------------------------
# Paste the AI-generated summary table into your PR description with your responses:
#
# | Issue Name        | Description                                                   | Status          | Notes                               |
# | ----------------- | ------------------------------------------------------------- | --------------- | ----------------------------------- |
# | Filename Typo     | fake_app_bootstarp.dart should be fake_app_bootstrap.dart | ✅ Addressed    | Renamed file to correct spelling    |
# | Missing Tests     | AuthService needs unit tests                                  | 📋 Future Story | Created YouTrack story: AUTH-123    |
# | Performance Issue | N+1 query in user list                                        | ❌ Disagree     | Query is optimized for our use case |
#
# STATUS OPTIONS:
# - ✅ Addressed: Issue has been fixed in this PR
# - 📋 Future Story: Issue will be addressed in a separate YouTrack story
# - ❌ Disagree: You disagree with the AI's assessment
# - 🔄 In Progress: Issue is being worked on but not complete
#
# NOTES REQUIREMENTS:
# - If You Agree and Have Addressed: Describe what changes were made
# - If You Agree but Needs Another Story: List the YouTrack story name for the refactor
# - If You Disagree: State the reason for disagreement with specific technical justification
#
# =============================================================================

# Check if enough parameters are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 pr_branch base_branch [output_file]"
    echo "Example: $0 feature-branch main pr_review.txt"
    exit 1
fi

# Set variables from parameters
PR_BRANCH="$1"      # Branch with your changes
BASE_BRANCH="$2"    # Branch you want to merge into (target)

# Always write outputs under the reviews/ directory
OUTPUT_DIR="reviews"
mkdir -p "$OUTPUT_DIR"

if [ -n "$3" ]; then
    # If a name is provided, use only its basename under reviews/
    OUTPUT_FILE="$OUTPUT_DIR/$(basename "$3")"
else
    OUTPUT_FILE="$OUTPUT_DIR/pr_review_for_cursor.txt"
fi

# Verify branches exist
if ! git rev-parse --verify "$PR_BRANCH" >/dev/null 2>&1; then
    echo "Error: PR branch '$PR_BRANCH' does not exist"
    exit 1
fi

if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "Error: Base branch '$BASE_BRANCH' does not exist"
    exit 1
fi

# Create header
echo "# PR Review Request: $PR_BRANCH → $BASE_BRANCH" > "$OUTPUT_FILE"
echo "PR Branch: $PR_BRANCH (with changes)" >> "$OUTPUT_FILE"
echo "Base Branch: $BASE_BRANCH (target)" >> "$OUTPUT_FILE"
echo "Date: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Get list of changed files - show what's in PR_BRANCH that's not in BASE_BRANCH
# Filter out generated files and binary files
CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH".."$PR_BRANCH" | grep -v -E '\.(g\.dart|freezed\.dart|gr\.dart|config\.dart|chopper\.dart|mocks\.dart)$' | grep -v -E '\.(png|jpg|jpeg|gif|svg|ico|webp|ttf|otf|woff|woff2|pdf|zip|tar|gz|rar|7z|exe|dll|so|dylib)$')

# Check if there are any changes
if [ -z "$CHANGED_FILES" ]; then
    echo "No changes found between PR branch $PR_BRANCH and base branch $BASE_BRANCH"
    exit 0
fi

# Generate overview table
echo "## CHANGES OVERVIEW" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| File | Changes | Type |" >> "$OUTPUT_FILE"
echo "|------|---------|------|" >> "$OUTPUT_FILE"

for FILE in $CHANGED_FILES; do
    # Get file status (modified, added, deleted)
    STATUS=$(git diff --name-status "$BASE_BRANCH".."$PR_BRANCH" -- "$FILE" | cut -f1)
    
    case $STATUS in
        M) STATUS_DESC="Modified" ;;
        A) STATUS_DESC="Added" ;;
        D) STATUS_DESC="Deleted" ;;
        R*) STATUS_DESC="Renamed" ;;
        C*) STATUS_DESC="Copied" ;;
        *) STATUS_DESC="Changed" ;;
    esac
    
    # Get file type
    if git show "$PR_BRANCH":"$FILE" &>/dev/null 2>&1; then
        if file --mime-type "$FILE" 2>/dev/null | grep -q "text/"; then
            FILE_TYPE="Text"
            # Count lines changed
            STATS=$(git diff --stat "$BASE_BRANCH".."$PR_BRANCH" -- "$FILE" | tail -n1)
            echo "| $FILE | $STATUS_DESC: $STATS | $FILE_TYPE |" >> "$OUTPUT_FILE"
        else
            FILE_TYPE="Binary"
            echo "| $FILE | $STATUS_DESC | $FILE_TYPE |" >> "$OUTPUT_FILE"
        fi
    else
        FILE_TYPE="Unknown"
        echo "| $FILE | $STATUS_DESC | $FILE_TYPE |" >> "$OUTPUT_FILE"
    fi
done

echo "" >> "$OUTPUT_FILE"

# Create GitHub-style diff with context
echo "## GITHUB-STYLE DIFF WITH CONTEXT" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

for FILE in $CHANGED_FILES; do
    # Skip binary files
    if git show "$PR_BRANCH":"$FILE" &>/dev/null 2>&1 && ! file --mime-type "$FILE" 2>/dev/null | grep -q "binary"; then
        # Get the file extension for syntax highlighting
        FILE_EXT="${FILE##*.}"
        
        # Determine if file is added, modified, or deleted
        STATUS=$(git diff --name-status "$BASE_BRANCH".."$PR_BRANCH" -- "$FILE" | cut -f1)
        
        case $STATUS in
            A) CHANGE_TYPE="Added" ;;
            M) CHANGE_TYPE="Modified" ;;
            D) CHANGE_TYPE="Deleted" ;;
            R*) CHANGE_TYPE="Renamed" ;;
            C*) CHANGE_TYPE="Copied" ;;
            *) CHANGE_TYPE="Changed" ;;
        esac
        
        echo "### $FILE ($CHANGE_TYPE)" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        # Generate GitHub-style diff with context
        # Using -U3 to show 3 lines of context before and after changes
        echo "\`\`\`$FILE_EXT" >> "$OUTPUT_FILE"
        
        # Use git diff directly with line numbers (simplified approach)
        git diff --no-prefix -U3 "$BASE_BRANCH".."$PR_BRANCH" -- "$FILE" >> "$OUTPUT_FILE"
        
        echo "\`\`\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        # Add placeholder for code review comments
        echo "#### Suggestions for $FILE" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "<!-- Example suggestion format below -->" >> "$OUTPUT_FILE"
        echo "<!--" >> "$OUTPUT_FILE"
        echo "**Line XX:** ✅/❌ Comment about the code" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "**Suggested Change:**" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "\`\`\`$FILE_EXT" >> "$OUTPUT_FILE"
        echo "// Suggested implementation" >> "$OUTPUT_FILE"
        echo "\`\`\`" >> "$OUTPUT_FILE"
        echo "-->" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        echo "### $FILE (Binary or Deleted - diff not shown)" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done


# =============================================================================
# REVIEW INSTRUCTIONS SECTION
# =============================================================================
echo "## REVIEW INSTRUCTIONS" >> "$OUTPUT_FILE"
echo "Please review this PR with the following considerations:" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# RULE 1: DIGESTIBLE PR RULE
# =============================================================================
echo "### 📋 RULE 1: DIGESTIBLE PR RULE" >> "$OUTPUT_FILE"
echo "**Reference:** For detailed guidelines, search: https://gist.github.com/ripplearcgit/551ccf7208a1dcf3f3edd27cac002214" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Size Classification (Production Code Only):**" >> "$OUTPUT_FILE"
echo "- XS: <50 lines | S: 50-100 lines | M: 100-200 lines | L: 200+ lines" >> "$OUTPUT_FILE"
echo "- **Action Required:** If PR is >M size, recommend breaking into smaller, focused PRs" >> "$OUTPUT_FILE"
echo "- **Focus:** Each PR should have single, clear purpose and pass tests independently" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# RULE 2: GENERAL CODE REVIEW CRITERIA
# =============================================================================
echo "### 🔍 RULE 2: GENERAL CODE REVIEW CRITERIA" >> "$OUTPUT_FILE"
echo "1. 📝 Code quality and best practices" >> "$OUTPUT_FILE"
echo "2. 🐛 Potential bugs or edge cases" >> "$OUTPUT_FILE"
echo "3. ⚡ Performance implications" >> "$OUTPUT_FILE"
echo "4. 🔒 Security concerns" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Review Output Format:**" >> "$OUTPUT_FILE"
echo "Please provide detailed comments with context for each file. If issues are found that need to be addressed, include the summary table below. If no issues are found, omit the table entirely." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# RULE 3: PERFORMANCE EFFICIENCY OF OPERATIONS AND POLICIES
# =============================================================================
echo "### ⚡RULE 3: PERFORMANCE EFFICIENCY OF OPERATIONS AND POLICIES" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Database Operations:**" >> "$OUTPUT_FILE"
echo "- 🔍 **Query Optimization:** Check for N+1 queries, missing indexes, and inefficient joins" >> "$OUTPUT_FILE"
echo "- 📊 **Data Access Patterns:** Verify appropriate use of SELECT, INSERT, UPDATE, DELETE operations" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**RLS (Row Level Security) Policies:**" >> "$OUTPUT_FILE"
echo "- 🛡️ **Policy Efficiency:** Check if RLS policies are optimized and don't cause performance bottlenecks" >> "$OUTPUT_FILE"
echo "- 🔐 **Security vs Performance:** Balance security requirements with query performance" >> "$OUTPUT_FILE"
echo "- 📈 **Index Usage:** Ensure RLS policies can leverage existing indexes effectively" >> "$OUTPUT_FILE"
echo "- 🎯 **Policy Scope:** Verify policies are scoped appropriately to avoid unnecessary checks" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**API Operations:**" >> "$OUTPUT_FILE"
echo "- ⚡ **Response Times:** Check for potential slow endpoints or blocking operations" >> "$OUTPUT_FILE"
echo "- 🔄 **Caching Strategy:** Verify appropriate use of caching mechanisms" >> "$OUTPUT_FILE"
echo "- 📦 **Data Transfer:** Ensure minimal data transfer and efficient serialization" >> "$OUTPUT_FILE"
echo "- 🔀 **Concurrency:** Check for proper handling of concurrent requests and race conditions" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Migration and Seeder Performance:**" >> "$OUTPUT_FILE"
echo "- 🚀 **Migration Speed:** Verify migrations run efficiently without blocking production" >> "$OUTPUT_FILE"
echo "- 📊 **Seeder Optimization:** Check if seeders use bulk operations and proper indexing" >> "$OUTPUT_FILE"
echo "- 🔄 **Rollback Strategy:** Ensure migrations can be rolled back efficiently" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# RULE 4: SAFETY AND RELIABILITY
# =============================================================================
echo "### 🛡️ RULE 4: SAFETY AND RELIABILITY" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Data Safety:**" >> "$OUTPUT_FILE"
echo "- 🔒 **Data Integrity:** Verify foreign key constraints, check constraints, and data validation" >> "$OUTPUT_FILE"
echo "- 🔄 **Transaction Safety:** Ensure proper use of transactions and rollback mechanisms" >> "$OUTPUT_FILE"
echo "- 📊 **Data Consistency:** Verify data remains consistent across related tables and operations" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Operational Safety:**" >> "$OUTPUT_FILE"
echo "- ⚠️ **Breaking Changes:** Check for backward compatibility and migration safety" >> "$OUTPUT_FILE"
echo "- 🔄 **Deployment Safety:** Verify zero-downtime deployment strategies where applicable" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Security Safety:**" >> "$OUTPUT_FILE"
echo "- 🔐 **Sensitive Data:** Verify proper handling of PII, passwords, and sensitive information" >> "$OUTPUT_FILE"
echo "- 🛡️ **RLS Policy Safety:** Check RLS policies don't accidentally expose or restrict data" >> "$OUTPUT_FILE"
echo "- 🔑 **Permission Safety:** Verify role-based access controls are properly implemented" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# RULE 5: RLS POLICY CORRECTNESS AND SECURITY EVALUATION
# =============================================================================
echo "### 🔐 RULE 5: RLS POLICY CORRECTNESS AND SECURITY EVALUATION" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**RLS Policy Analysis:**" >> "$OUTPUT_FILE"
echo "- 🎯 **Policy Logic:** Verify RLS policies implement the intended access control logic correctly" >> "$OUTPUT_FILE"
echo "- 🔍 **Policy Coverage:** Check that all necessary tables have appropriate RLS policies enabled" >> "$OUTPUT_FILE"
echo "- 🚫 **Policy Gaps:** Identify any tables or operations that lack proper RLS protection" >> "$OUTPUT_FILE"
echo "- 🔄 **Policy Consistency:** Ensure RLS policies are consistent across related tables and operations" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Security Hole Detection:**" >> "$OUTPUT_FILE"
echo "- 🕳️ **Data Leakage:** Check for policies that might accidentally expose sensitive data" >> "$OUTPUT_FILE"
echo "- 🔓 **Privilege Escalation:** Verify policies prevent users from accessing data they shouldn't" >> "$OUTPUT_FILE"
echo "- 🎭 **Bypass Vulnerabilities:** Look for ways users might bypass RLS policies through direct queries" >> "$OUTPUT_FILE"
echo "- 🔀 **Cross-User Access:** Ensure users cannot access other users' data inappropriately" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**RLS Implementation Quality:**" >> "$OUTPUT_FILE"
echo "- 📝 **Policy Documentation:** Verify RLS policies are well-documented and understandable" >> "$OUTPUT_FILE"
echo "- 🧪 **Policy Testing:** Ensure RLS policies are properly tested with various scenarios" >> "$OUTPUT_FILE"
echo "- 🔄 **Policy Maintenance:** Check that policies can be easily maintained and updated" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# RULE 6: DATABASE SCHEMA AND MIGRATION INTEGRITY
# =============================================================================
echo "### 🗄️ RULE 6: DATABASE SCHEMA AND MIGRATION INTEGRITY" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Schema Design:**" >> "$OUTPUT_FILE"
echo "- 🏗️ **Table Structure:** Verify proper table design with appropriate primary keys, foreign keys, and constraints" >> "$OUTPUT_FILE"
echo "- 📊 **Data Types:** Check for appropriate data types and precision (e.g., decimal precision for financial data)" >> "$OUTPUT_FILE"
echo "- 🔗 **Relationships:** Ensure foreign key relationships are properly defined and maintain referential integrity" >> "$OUTPUT_FILE"
echo "- 📝 **Naming Conventions:** Verify consistent naming conventions for tables, columns, and constraints" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Migration Safety:**" >> "$OUTPUT_FILE"
echo "- ⬆️ **Upward Compatibility:** Ensure migrations can be applied to existing databases without data loss" >> "$OUTPUT_FILE"
echo "- ⬇️ **Downward Compatibility:** Verify migrations can be rolled back safely" >> "$OUTPUT_FILE"
echo "- 🔄 **Migration Order:** Check that migration dependencies are properly ordered and numbered" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Enum and Type Management:**" >> "$OUTPUT_FILE"
echo "- 📋 **Enum Consistency:** Verify enum values are consistent across the application" >> "$OUTPUT_FILE"
echo "- 🔄 **Enum Evolution:** Check that enum changes don't break existing data" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# REVIEW SUMMARY TABLE
# =============================================================================
echo "## REVIEW SUMMARY" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**IMPORTANT:** Only include this table if you find issues that need to be addressed. If the PR has no outstanding issues, delete this entire section." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| Issue Name | Description | Status | Notes |" >> "$OUTPUT_FILE"
echo "|------------|-------------|--------|-------|" >> "$OUTPUT_FILE"
echo "| [Brief issue name] | [Detailed description of the issue] | [Author to fill out] | [Author to fill out] |" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Status Options (for PR Author to fill out - NOT for LLM):**" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "**Notes Requirements (for PR Author to fill out - NOT for LLM):**" >> "$OUTPUT_FILE"
echo "- **If Author Disagree:** State the reason for disagreement" >> "$OUTPUT_FILE"
echo "- **If Agree and Have Addressed:** Describe what changes were made" >> "$OUTPUT_FILE"
echo "- **If Agree but Needs Another Story:** List the YouTrack story name for the refactor" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# =============================================================================
# REVIEW OUTPUT FORMAT
# =============================================================================
echo "## REVIEW OUTPUT FORMAT" >> "$OUTPUT_FILE"
echo "Please provide your review in the following structured format:" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "### 1. PR SUMMARY" >> "$OUTPUT_FILE"
echo "Provide a concise summary of what this PR is doing and its main objective." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "### 2. REVIEW SUMMARY TABLE" >> "$OUTPUT_FILE"
echo "If issues are found that need to be addressed, include the summary table below. If no issues are found, omit the table entirely." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Review file created: $OUTPUT_FILE"
