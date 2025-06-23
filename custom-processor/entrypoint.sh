#!/bin/bash
set -e

# Get input data from action args
INPUT_DATA="$1"

# Function to trigger workflow and get result
run_workflow() {
  local workflow_name=$1
  local input_name=$2
  local input_value=$3
  
  # Get workflow ID
  echo "Getting ID for workflow: $workflow_name" >&2
  local workflow_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflows/actions/workflows")
  
  # Debug: Show API response
  echo "API Response: $workflow_info" >&2
  
  # Handle empty response
  if [ -z "$workflow_info" ] || [ "$workflow_info" = "null" ]; then
    echo "ERROR: Empty response from workflows API" >&2
    return 1
  fi
  
  # Check for API errors
  if echo "$workflow_info" | grep -q '"message"'; then
    echo "ERROR: Workflows API returned error" >&2
    echo "$workflow_info" | jq . >&2
    return 1
  fi
  
  # Extract workflow ID using path
  local workflow_id=$(echo "$workflow_info" | jq -r \
    --arg path ".github/workflows/$workflow_name" \
    '.workflows[] | select(.path == $path) | .id')
  
  if [ -z "$workflow_id" ] || [ "$workflow_id" = "null" ]; then
    echo "ERROR: Workflow '$workflow_name' not found" >&2
    echo "Available workflows:" >&2
    echo "$workflow_info" | jq '.workflows[] | {id, name, path}' >&2
    return 1
  fi
  echo "Found workflow ID: $workflow_id" >&2
  
  # Trigger workflow
  echo "Triggering $workflow_name (ID: $workflow_id) with $input_name=$input_value" >&2
  response=$(curl -s -w "%{http_code}" -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/koushik309/Workflows/actions/workflows/$workflow_id/dispatches" \
    -d "{\"ref\":\"main\", \"inputs\":{\"$input_name\":\"$input_value\"}}")
  
  http_code=${response: -3}
  body=${response%$http_code}
  
  # Check for successful trigger
  if [ "$http_code" != "204" ]; then
    echo "ERROR: Failed to trigger workflow $workflow_name. HTTP $http_code: $body" >&2
    return 1
  fi
  echo "Workflow triggered successfully" >&2
  
  # Wait 20 seconds for workflow to start
  sleep 20
  
  # Get latest run ID
  local run_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflows/actions/runs?workflow=$workflow_id&event=workflow_dispatch")
  
  # Debug: Show run info
  echo "Run info: $run_info" >&2
  
  local run_id=$(echo "$run_info" | jq -r '.workflow_runs[0].id')
  
  if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
    echo "ERROR: Failed to get run ID for workflow $workflow_name" >&2
    return 1
  fi
  echo "Triggered run ID: $run_id" >&2
  
  # Wait for completion with timeout (max 30 minutes)
  local timeout=1800
  local start_time=$(date +%s)
  while true; do
    local status_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/koushik309/Workflows/actions/runs/$run_id")
    local status=$(echo "$status_info" | jq -r '.status')
    [ -z "$status" ] && status="unknown"
    
    echo "Current status: $status" >&2
    [[ "$status" = "completed" ]] && break
    
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    if [ $elapsed -ge $timeout ]; then
      echo "Timeout waiting for workflow $workflow_name to complete" >&2
      return 1
    fi
    sleep 30
  done
  
  # Get artifacts
  local artifacts_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflows/actions/runs/$run_id/artifacts")
  local download_url=$(echo "$artifacts_info" | jq -r '.artifacts[0].archive_download_url')
  
  if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
    echo "ERROR: Failed to get artifact download URL" >&2
    return 1
  fi
  
  echo "Downloading artifact from $download_url" >&2
  curl -s -L -H "Authorization: token $GITHUB_TOKEN" -o artifact.zip "$download_url"
  
  # Extract and return artifact content
  unzip -p artifact.zip output.txt
}

# Validate token exists
if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN is not set" >&2
  exit 1
fi

# Verify token permissions
RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)
USER_LOGIN=$(echo "$RESPONSE" | jq -r '.login')

if [ -z "$USER_LOGIN" ] || [ "$USER_LOGIN" = "null" ]; then
  echo "ERROR: Invalid token - cannot authenticate" >&2
  echo "API Response: $RESPONSE" >&2
  exit 1
fi

echo "Authenticated as: $USER_LOGIN" >&2

# Verify repository access
echo "Verifying repository access..." >&2
REPO_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/koushik309/Workflows")

if echo "$REPO_INFO" | grep -q "Not Found"; then
  echo "ERROR: Repository not found" >&2
  echo "Check: https://github.com/koushik309/Workflows" >&2
  echo "API Response: $REPO_INFO" >&2
  exit 1
fi

echo "Repository found: $(echo "$REPO_INFO" | jq -r '.full_name')" >&2

# Run job1 and capture output
echo "Starting Job1..." >&2
JOB1_OUTPUT=$(run_workflow "job1.yml" "input_data" "$INPUT_DATA")
echo "Job1 output: $JOB1_OUTPUT" >&2

# Run job2 with job1's output
echo "Starting Job2..." >&2
run_workflow "job2.yml" "job1_output" "$JOB1_OUTPUT"