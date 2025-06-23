#!/bin/bash
set -e

INPUT_DATA="$1"

run_workflow() {
  local workflow_name=$1
  local input_name=$2
  local input_value=$3
  
  echo "Getting ID for workflow: $workflow_name" >&2
  local workflow_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflows/actions/workflows")
  
  if [ -z "$workflow_info" ] || [ "$workflow_info" = "null" ]; then
    echo "ERROR: Empty response from workflows API" >&2
    return 1
  fi
  
  if echo "$workflow_info" | grep -q '"message"'; then
    echo "ERROR: Workflows API returned error" >&2
    echo "$workflow_info" | jq . >&2
    return 1
  fi
  
  local workflow_id=$(echo "$workflow_info" | jq -r \
    --arg path ".github/workflows/$workflow_name" \
    '.workflows[] | select(.path == $path) | .id')
  
  if [ -z "$workflow_id" ] || [ "$workflow_id" = "null" ]; then
    echo "ERROR: Workflow '$workflow_name' not found" >&2
    return 1
  fi
  
  echo "Triggering $workflow_name (ID: $workflow_id) with $input_name=$input_value" >&2
  response=$(curl -s -w "%{http_code}" -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/koushik309/Workflows/actions/workflows/$workflow_id/dispatches" \
    -d "{\"ref\":\"main\", \"inputs\":{\"$input_name\":\"$input_value\"}}")
  
  http_code=${response: -3}
  body=${response%$http_code}
  
  if [ "$http_code" != "204" ]; then
    echo "ERROR: Failed to trigger workflow. HTTP $http_code: $body" >&2
    return 1
  fi
  
  echo "Workflow triggered successfully. Waiting 20 seconds..." >&2
  sleep 20
  
  local run_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/koushik309/Workflows/actions/runs?workflow=$workflow_id&event=workflow_dispatch")
  
  local run_id=$(echo "$run_info" | jq -r '.workflow_runs[0].id')
  
  if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
    echo "ERROR: Failed to get run ID" >&2
    return 1
  fi
  
  echo "Workflow run URL: https://github.com/koushik309/Workflows/actions/runs/$run_id" >&2
  
  local timeout=1800
  local start_time=$(date +%s)
  while true; do
    local status_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/koushik309/Workflows/actions/runs/$run_id")
    
    local status=$(echo "$status_info" | jq -r '.status')
    local conclusion=$(echo "$status_info" | jq -r '.conclusion')
    
    echo "Status: $status, Conclusion: $conclusion" >&2
    
    if [[ "$status" == "completed" ]]; then
      if [[ "$conclusion" != "success" ]]; then
        echo "ERROR: Workflow failed with conclusion: $conclusion" >&2
        return 1
      fi
      break
    fi
    
    if [ $(($(date +%s) - start_time)) -ge $timeout ]; then
      echo "ERROR: Timeout waiting for workflow" >&2
      return 1
    fi
    sleep 10
  done
  
  # Get artifacts with retries
  local retries=3
  local artifacts_info=""
  for i in $(seq 1 $retries); do
    echo "Fetching artifacts (attempt $i/$retries)..." >&2
    artifacts_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/repos/koushik309/Workflows/actions/runs/$run_id/artifacts")
    
    if [ $(echo "$artifacts_info" | jq '.total_count') -gt 0 ]; then
      break
    fi
    sleep 5
  done
  
  if [ $(echo "$artifacts_info" | jq '.total_count') -eq 0 ]; then
    echo "ERROR: No artifacts found after $retries attempts" >&2
    echo "Artifact API response: $artifacts_info" >&2
    return 1
  fi
  
  local download_url=$(echo "$artifacts_info" | jq -r '.artifacts[0].archive_download_url')
  
  echo "Downloading artifact from $download_url" >&2
  curl -s -L -H "Authorization: token $GITHUB_TOKEN" -o artifact.zip "$download_url"
  unzip -p artifact.zip output.txt
  rm artifact.zip
}

# Validate token
if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN missing" >&2
  exit 1
fi

# Run job1 and capture output
JOB1_OUTPUT=$(run_workflow "job1.yml" "input_data" "$INPUT_DATA")

# Run job2 with job1's output
JOB2_OUTPUT=$(run_workflow "job2.yml" "job1_output" "$JOB1_OUTPUT")

# Final output
echo "Final result: $JOB2_OUTPUT"