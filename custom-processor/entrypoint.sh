#!/bin/bash
set -e  # Exit on error

INPUT_DATA="$1"

run_workflow() {
  local workflow_name=$1
  local input_name=$2
  local input_value=$3
  
  # Trigger workflow
  echo "Triggering $workflow_name with $input_name=$input_value"
  curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/koushik309/Workflow/actions/workflows/$workflow_name/dispatches" \
    -d "{\"ref\":\"main\", \"inputs\":{\"$input_name\":\"$input_value\"}}"
  
  # Wait for workflow to start
  echo "Waiting for workflow to start..."
  sleep 15
  
  # Get latest run ID
  run_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflow/actions/runs?workflow=$workflow_name&status=in_progress")
  run_id=$(echo "$run_info" | jq -r '.workflow_runs[0].id')
  
  # Wait for completion
  echo "Waiting for workflow $run_id to complete..."
  while true; do
    status=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/koushik309/Workflow/actions/runs/$run_id" | \
      jq -r '.status')
    [ "$status" = "completed" ] && break
    sleep 10
  done
  
  # Download artifact
  artifacts_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflow/actions/runs/$run_id/artifacts")
  download_url=$(echo "$artifacts_info" | jq -r '.artifacts[0].archive_download_url')
  
  echo "Downloading artifact from $download_url"
  curl -s -L -H "Authorization: token $GITHUB_TOKEN" -o artifact.zip "$download_url"
  unzip -p artifact.zip
}

# Run job1 and capture output
echo "Starting Job1..."
JOB1_OUTPUT=$(run_workflow "job1.yml" "input_data" "$INPUT_DATA")
echo "Job1 output: $JOB1_OUTPUT"

# Run job2 with job1's output
echo "Starting Job2..."
run_workflow "job2.yml" "job1_output" "$JOB1_OUTPUT"