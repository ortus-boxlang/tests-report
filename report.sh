#!/bin/bash

# Organization name
org_name=$1

# CFML Engine to query (e.g., "boxlang@1")
cfml_engine=$2

# File to store the final JSON output for workflows that match with CFML Engine Tests
output_file="workflows_status.json"

# File to store the final JSON output for repositories excluded due no CFML Engine Tests found
excluded_file="excluded_repos.json"

# File to store the summary output in JSON format
summary_file="summary.json"

# Initialize the JSON objects in the output files
echo "{" > "$output_file"
echo "{" > "$excluded_file"
echo "{" > "$summary_file"

# Initialize counters
repos_with_cfml_engine=0
repos_with_no_cfml_engine=0
success_count=0
failure_count=0
neutral_count=0

# Fetch all repositories from the organization
page=1
while true; do
  # Fetch repositories from the API
  repos_response=$(gh api "/orgs/${org_name}/repos?per_page=100&page=${page}")
  repo_count=$(echo "$repos_response" | jq '. | length')

  if [[ $repo_count -eq 0 ]]; then
    # No more repositories, exit the loop
    break
  fi

  # Extract repository names and visibility
  repo_info=$(echo "$repos_response" | jq -r '.[] | {name: .name, visibility: .visibility}')

  # Iterate through each repository
  for row in $(echo "$repo_info" | jq -r '. | @base64'); do
    _jq() {
      echo ${row} | base64 --decode | jq -r ${1}
    }

    repo_name=$(_jq '.name')
    repo_visibility=$(_jq '.visibility')

    echo "Processing repository: $repo_name (Visibility: $repo_visibility)"

    # Fetch the latest workflow run for the repository (per_page=1)
    workflows_response=$(gh api "/repos/${org_name}/${repo_name}/actions/runs?per_page=1")

    # Initialize an array to hold job statuses
    jobs_status="["

    # Flag to track if any job matched the filter
    has_cfml_engine_job=false

    # Extract workflow run count (should be 1 as we're limiting to the latest)
    workflow_count=$(echo "$workflows_response" | jq '.workflow_runs | length')

    if [[ $workflow_count -gt 0 ]]; then
      # Extract workflow run ID (latest run)
      run_id=$(echo "$workflows_response" | jq -r ".workflow_runs[0].id")

      # Fetch job details for the latest workflow run
      jobs_response=$(gh api "/repos/${org_name}/${repo_name}/actions/runs/${run_id}/jobs")
      
      # Iterate over the jobs in the workflow run
      job_count=$(echo "$jobs_response" | jq '.jobs | length')
      for ((j=0; j<job_count; j++)); do
        # Get the job name
        job_name=$(echo "$jobs_response" | jq -r ".jobs[$j].name")

        # Exclude jobs that contain the string "tests / Tests"
        if [[ "$job_name" == *"Tests Results"* ]]; then
          continue
        fi

        # Check if the job contains the CFML Engine queried
        if [[ "$job_name" == *"${cfml_engine}"* ]]; then
          # If job name contains CFML Engine queried, capture status and conclusion
          job_status=$(echo "$jobs_response" | jq -r ".jobs[$j] | {name: .name, status: .status, conclusion: .conclusion}")
          
          # Add the job status to the jobs_status array
          jobs_status+="$job_status,"
          
          # Mark that we found a matching job
          has_cfml_engine_job=true

          # Count conclusion results
          conclusion=$(echo "$jobs_response" | jq -r ".jobs[$j].conclusion")
          if [[ "$conclusion" == "success" ]]; then
            ((success_count++))
          elif [[ "$conclusion" == "failure" ]]; then
            ((failure_count++))
          elif [[ "$conclusion" == "neutral" ]]; then
            ((neutral_count++))  
          fi
        fi
      done
    fi

    # Remove the trailing comma and close the jobs array
    jobs_status=${jobs_status%,}
    jobs_status+="]"

    # Append the repository data to the JSON file if there is a matching job
    if [[ "$has_cfml_engine_job" == true ]]; then
      echo "\"$repo_name\": {\"visibility\": \"$repo_visibility\", \"jobs\": $jobs_status}," >> "$output_file"
      ((repos_with_cfml_engine++))
    else
      # If no jobs matched the filter, add it to the excluded file
      echo "\"$repo_name\": {\"visibility\": \"$repo_visibility\", \"jobs\": []}," >> "$excluded_file"
      ((repos_with_no_cfml_engine++))
    fi
  done

  # Increment page for the next batch of repositories
  ((page++))
done

# Finalize both JSON objects (remove trailing commas and close the objects)
sed -i '$ s/,$//' "$output_file"  # Remove the trailing comma
sed -i '$ s/,$//' "$excluded_file"  # Remove the trailing comma
echo "}" >> "$output_file"
echo "}" >> "$excluded_file"

# Write summary to JSON file
echo "{
  \"repos_with_cfml_engine\": $repos_with_cfml_engine,
  \"repos_with_no_cfml_engine\": $repos_with_no_cfml_engine,
  \"job_conclusions\": {
    \"success\": $success_count,
    \"failure\": $failure_count,
    \"neutral\": $neutral_count
  }
}" > "$summary_file"

# Print the summary in JSON format to the console
cat "$summary_file"

# Print the summary to the console
echo ""
echo "Workflow statuses for repositories with CFML Engine Tests have been stored in $output_file"
echo "Repositories with no CFML Engine Tests jobs have been stored in $excluded_file"
