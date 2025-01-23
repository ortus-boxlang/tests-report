## Test report
This script take last execution of workflow under snapshot.yml (that include test) worflow file and look for status of Boxlang tests.

Three JSON files are generated:
`tests_status.json` to store status of found tests, `repos_with_no_tests.json` file to store repos without found tests and `summary.json`file to store a summary of found tests and status of them

### How to run
```shell
./report.sh [organization_name_to_lookup_tests]
```

### Sample execution:
```shell
./report.sh ortus-boxlang
```

### Summary sample:
```json
{
  "organization": "ortus-boxlang",
  "repositories_with_tests": 33,
  "repositories_without_tests": 11,
  "analyzed_repositories": 44,
  "job_conclusions": {
    "success": 59,
    "failure": 7,
    "neutral": 0
  }
}
```