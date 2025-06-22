#!/bin/bash

# Get input data from action args
INPUT_DATA="$1"

# Function to trigger workflow and get result
run_workflow() {
  local workflow_name=$1
  local input_name=$2
  local input_value=$3
  
  # Trigger workflow
  curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/koushik309/Workflow/actions/workflows/$workflow_name/dispatches" \
    -d "{\"ref\":\"main\", \"inputs\":{\"$input_name\":\"$input_value\"}}"
  
  # Wait for completion
  sleep 10
  
  # Get latest run ID
  local run_id=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflow/actions/runs?workflow=$workflow_name" | \
    jq -r '.workflow_runs[0].id')
  
  # Download and return artifact
  curl -s -L \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflow/actions/runs/$run_id/artifacts" | \
    jq -r '.artifacts[0].archive_download_url' | \
    xargs curl -s -L -o artifact.zip
  
  unzip -p artifact.txt
}

# Run job1 and capture output
JOB1_OUTPUT=$(run_workflow "job1.yml" "input_data" "$INPUT_DATA")

echo "Job1 output: $JOB1_OUTPUT"

# Run job2 with job1's output
run_workflow "job2.yml" "job1_output" "$JOB1_OUTPUT"