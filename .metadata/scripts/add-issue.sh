#!/bin/bash
# add-issue.sh - Create GitHub issue with optional deadline and status
# Usage: ./add-issue.sh "Issue title" [deadline YYYY-MM-DD] [status: todo|next|in-progress|done]

set -e

# Configuration
REPO_OWNER="lucianstuparu"
REPO_NAME="inst.job"
PROJECT_ID="PVT_kwHOAKRZo84BON5B"
STATUS_FIELD_ID="PVTSSF_lAHOAKRZo84BON5Bzg8-9t0"
DEADLINE_FIELD_ID="PVTF_lAHOAKRZo84BON5Bzg8-93o"

# Status option IDs
declare -A STATUS_IDS=(
    ["todo"]="ac9844cf"
    ["next"]="acd48498"
    ["in-progress"]="4fba7b52"
    ["done"]="cce8eea9"
)

# Check required environment variable
if [[ -z "$GH_TOKEN" ]]; then
    echo "Error: GH_TOKEN environment variable not set"
    exit 1
fi

# Parse arguments
TITLE="$1"
DEADLINE=""
STATUS=""

if [[ -z "$TITLE" ]]; then
    echo "Usage: $0 \"Issue title\" [deadline YYYY-MM-DD] [status: todo|next|in-progress|done]"
    echo ""
    echo "Examples:"
    echo "  $0 \"Fix the bug\""
    echo "  $0 \"Submit report\" 2026-02-15"
    echo "  $0 \"Review document\" 2026-02-20 next"
    exit 1
fi

# Parse optional deadline (format: YYYY-MM-DD)
if [[ -n "$2" ]] && [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    DEADLINE="$2"
fi

# Parse optional status (could be $2 if no deadline, or $3 if deadline provided)
STATUS_ARG=""
if [[ -z "$DEADLINE" ]] && [[ -n "$2" ]]; then
    STATUS_ARG="$2"
elif [[ -n "$3" ]]; then
    STATUS_ARG="$3"
fi

if [[ -n "$STATUS_ARG" ]]; then
    STATUS_LOWER=$(echo "$STATUS_ARG" | tr '[:upper:]' '[:lower:]')
    if [[ -n "${STATUS_IDS[$STATUS_LOWER]}" ]]; then
        STATUS="$STATUS_LOWER"
    else
        echo "Warning: Invalid status '$STATUS_ARG'. Valid options: todo, next, in-progress, done"
        echo "Continuing without setting status..."
    fi
fi

echo "Creating issue: $TITLE"

# 1. Create the issue
ISSUE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/issues \
    -d "{\"title\":\"$TITLE\"}")

# Check for errors
if echo "$ISSUE_RESPONSE" | grep -q '"message"'; then
    echo "Error creating issue:"
    echo "$ISSUE_RESPONSE" | grep -o '"message":"[^"]*"'
    exit 1
fi

ISSUE_NUMBER=$(echo "$ISSUE_RESPONSE" | grep -o '"number": *[0-9]*' | head -1 | grep -o '[0-9]*')
ISSUE_NODE_ID=$(echo "$ISSUE_RESPONSE" | grep -o '"node_id": *"[^"]*"' | head -1 | sed 's/"node_id": *"\([^"]*\)"/\1/')

if [[ -z "$ISSUE_NUMBER" ]]; then
    echo "Error: Failed to extract issue number"
    echo "$ISSUE_RESPONSE"
    exit 1
fi

echo "✓ Created issue #$ISSUE_NUMBER"

# If no deadline or status, we're done
if [[ -z "$DEADLINE" ]] && [[ -z "$STATUS" ]]; then
    echo "Done! View at: https://github.com/$REPO_OWNER/$REPO_NAME/issues/$ISSUE_NUMBER"
    exit 0
fi

# 2. Add issue to project
echo "Adding issue to project..."
ADD_RESPONSE=$(curl -s -X POST \
    -H "Authorization: bearer $GH_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"mutation { addProjectV2ItemById(input: {projectId: \\\"$PROJECT_ID\\\", contentId: \\\"$ISSUE_NODE_ID\\\"}) { item { id } } }\"}" \
    https://api.github.com/graphql)

ITEM_ID=$(echo "$ADD_RESPONSE" | grep -o '"id":"PVTI_[^"]*"' | head -1 | sed 's/"id":"\([^"]*\)"/\1/')

if [[ -z "$ITEM_ID" ]]; then
    echo "Warning: Could not add item to project. Deadline/status not set."
    echo "$ADD_RESPONSE"
    echo "Issue created successfully at: https://github.com/$REPO_OWNER/$REPO_NAME/issues/$ISSUE_NUMBER"
    exit 0
fi

echo "✓ Added to project (Item ID: $ITEM_ID)"

# 3. Set deadline if provided
if [[ -n "$DEADLINE" ]]; then
    echo "Setting deadline to $DEADLINE..."
    DEADLINE_RESPONSE=$(curl -s -X POST \
        -H "Authorization: bearer $GH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"mutation { updateProjectV2ItemFieldValue(input: {projectId: \\\"$PROJECT_ID\\\", itemId: \\\"$ITEM_ID\\\", fieldId: \\\"$DEADLINE_FIELD_ID\\\", value: {date: \\\"$DEADLINE\\\"}}) { projectV2Item { id } } }\"}" \
        https://api.github.com/graphql)

    if echo "$DEADLINE_RESPONSE" | grep -q '"errors"'; then
        echo "Warning: Failed to set deadline"
        echo "$DEADLINE_RESPONSE"
    else
        echo "✓ Deadline set to $DEADLINE"
    fi
fi

# 4. Set status if provided
if [[ -n "$STATUS" ]]; then
    STATUS_ID="${STATUS_IDS[$STATUS]}"
    echo "Setting status to '$STATUS'..."
    STATUS_RESPONSE=$(curl -s -X POST \
        -H "Authorization: bearer $GH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"mutation { updateProjectV2ItemFieldValue(input: {projectId: \\\"$PROJECT_ID\\\", itemId: \\\"$ITEM_ID\\\", fieldId: \\\"$STATUS_FIELD_ID\\\", value: {singleSelectOptionId: \\\"$STATUS_ID\\\"}}) { projectV2Item { id } } }\"}" \
        https://api.github.com/graphql)

    if echo "$STATUS_RESPONSE" | grep -q '"errors"'; then
        echo "Warning: Failed to set status"
        echo "$STATUS_RESPONSE"
    else
        echo "✓ Status set to '$STATUS'"
    fi
fi

echo ""
echo "Done! View at: https://github.com/$REPO_OWNER/$REPO_NAME/issues/$ISSUE_NUMBER"
