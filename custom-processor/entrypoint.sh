#!/bin/bash
set -e

# Get input data from action args
INPUT_DATA="$1"

# Function to trigger workflow and get result
run_workflow() {
  local workflow_name=$1
  local input_name=$2
  local input_value=$3
  
  # Trigger workflow
  echo "Triggering $workflow_name with $input_name=$input_value" >&2
  curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/koushik309/Workflow/actions/workflows/$workflow_name/dispatches" \
    -d "{\"ref\":\"main\", \"inputs\":{\"$input_name\":\"$input_value\"}}"
  
  # Wait 10 seconds for workflow to start
  sleep 10
  
  # Get latest run ID
  local run_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflow/actions/runs?workflow=$workflow_name&status=in_progress")
  local run_id=$(echo "$run_info" | jq -r '.workflow_runs[0].id')
  echo "Triggered run ID: $run_id" >&2
  
  # Wait for completion with timeout (max 10 minutes)
  local timeout=600
  local start_time=$(date +%s)
  while true; do
    local status_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/koushik309/Workflow/actions/runs/$run_id")
    local status=$(echo "$status_info" | jq -r '.status')
    echo "Current status: $status" >&2
    
    [ "$status" = "completed" ] && break
    
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    if [ $elapsed -ge $timeout ]; then
      echo "Timeout waiting for workflow $workflow_name to complete" >&2
      return 1
    fi
    sleep 15
  done
  
  # Get artifacts
  local artifacts_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflow/actions/runs/$run_id/artifacts")
  local download_url=$(echo "$artifacts_info" | jq -r '.artifacts[0].archive_download_url')
  
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

# Run job1 and capture output
echo "Starting Job1..." >&2
JOB1_OUTPUT=$(run_workflow "job1.yml" "input_data" "$INPUT_DATA")
echo "Job1 output: $JOB1_OUTPUT" >&2

# Run job2 with job1's output
echo "Starting Job2..." >&2
run_workflow "job2.yml" "job1_output" "$JOB1_OUTPUT"