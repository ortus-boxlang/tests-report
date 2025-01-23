#!/bin/bash

# Get essential information from params
organization_name=$1

# General configs
output_file="tests_status.json"
excluded_repos_file="repos_with_no_tests.json"
summary_file="summary.json"

# Init vars
repos_with_tests=0
repos_without_tests=0
success_tests=0
failed_tests=0
neutral_tests=0
repositories=""

# Init output files
echo "{" > "$output_file"
echo "{" > "$excluded_repos_file"
echo "{" > "$summary_file"

# Fetch repos in GitHub org
repositories=$(gh api "/orgs/${organization_name}/repos?per_page=100")
repositories_count=$(echo "$repositories" | jq '. | length')

if [[ $repositories_count -eq 0 ]]; then
    echo "NO REPOSITORIES FOUND IN ${organization_name} GITHUB ORGANIZATION"
    exit 1
fi

reposities_info=$(echo "$repositories" | jq -r '.[] | {name: .name, visibility: .visibility}')
for row in $(echo "$reposities_info" | jq -r '. | @base64'); do
    _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
    }
    repository_name=$(_jq '.name')
    repository_visibility=$(_jq '.visibility')

    echo "Processing repository: $repository_name (with $repository_visibility visibility)"

    workflow_runs=$(gh api "/repos/${organization_name}/${repository_name}/actions/workflows/snapshot.yml/runs?per_page=1")
    workflow_runs_counts=$(echo "$workflow_runs" | jq '.workflow_runs | length')

    # Initialize an array to hold jobs with tests
    test_jobs="["

    # Flag to track if any job matched the filter
    has_tests=false

    # Check if repository has workflow runs
    if [[ $workflow_runs_counts -gt 0 ]]; then
        workflow_run_id=$(echo "$workflow_runs" | jq -r '.workflow_runs[0].id')

        workflow_run_jobs=$(gh api "/repos/${organization_name}/${repository_name}/actions/runs/${workflow_run_id}/jobs")

        # Iterate over the jobs in the workflow run
        workflow_run_jobs_count=$(echo "$workflow_run_jobs" | jq '.jobs | length')
        for ((j=0; j<workflow_run_jobs_count; j++)); do
            # Get Workflow run job name
            job_name=$(echo "$workflow_run_jobs" | jq -r ".jobs[$j].name")

            # Exclude jobs that contain the string "tests / Tests"
            regex_to_exclude="^(build|Test Results|tests \/ Publish|Code Auto-Formatting|release)|^tests \/ Tests \(be,?\s*(lucee|adobe)@\d+\).*$ "
            if [[ "$job_name" =~ $regex_to_exclude ]]; then
                continue
            fi

            test_job=$(echo "$workflow_run_jobs" | jq -r ".jobs[$j] | {name: .name, status: .status, conclusion: .conclusion, completed_at: .completed_at, url: .html_url}")
            # Add job to test_jobs array
            test_jobs+="$test_job,"

            # Test found in job
            has_tests=true

            # Count conclusion results
            conclusion=$(echo "$test_job" | jq -r ".conclusion")
            if [[ "$conclusion" == "success" ]]; then
                ((success_tests++))
            elif [[ "$conclusion" == "failure" ]]; then
                ((failed_tests++))
            elif [[ "$conclusion" == "neutral" ]]; then
                ((neutral_tests++))  
            fi
        done
    fi

    # Remove the trailing comma and close the jobs array
    test_jobs=${test_jobs%,}
    test_jobs+="]"

    # Append the repository data to the JSON file if there is a matching job
    if [[ "$has_tests" == true ]]; then
      echo "\"$repository_name\": {\"visibility\": \"$repository_visibility\", \"jobs\": $test_jobs}," >> "$output_file"
      ((repos_with_tests++))
    else
      # If no jobs matched the filter, add it to the excluded file
      echo "\"$repository_name\": {\"visibility\": \"$repository_visibility\", \"jobs\": []}," >> "$excluded_repos_file"
      ((repos_without_tests++))
    fi
done

# Finalize both JSON objects (remove trailing commas and close the objects)
sed -i '$ s/,$//' "$output_file"  # Remove the trailing comma
sed -i '$ s/,$//' "$excluded_repos_file"  # Remove the trailing comma
echo "}" >> "$output_file"
echo "}" >> "$excluded_repos_file"

# Write summary to JSON file
echo "{
  \"organization\": \"$organization_name\",
  \"repositories_with_tests\": $repos_with_tests,
  \"repositories_without_tests\": $repos_without_tests,
  \"analyzed_repositories\": $repositories_count,
  \"job_conclusions\": {
    \"success\": $success_tests,
    \"failure\": $failed_tests,
    \"neutral\": $neutral_tests
  }
}" > "$summary_file"

# Print the summary in JSON format to the console
cat "$summary_file"
echo "================================================="
echo "Workflow statuses for repositories with Tests have been stored in $output_file"
echo "Repositories with no Tests jobs have been stored in $excluded_repos_file"
