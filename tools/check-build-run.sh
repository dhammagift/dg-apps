#!/bin/bash
# Before play-upload.yml / ios-upload.yml send the files of an earlier Build App run to a store: is that
# run one a store may get? It must be a build-app.yml run that SUCCEEDED, built from main or a tag, with
# the app talking to https://dhamma.gift (its build-info artifact), and the named check job of that app
# must have passed in it (a green run can have skipped it). Verified 2026-10-10: Uposatha 488 went to
# Play from a failed run of a feature branch, and nothing here asked.
#
# Usage: tools/check-build-run.sh <run id> <name prefix of the check job that must have passed>
# Env: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT. Writes run_number=<n> to $GITHUB_OUTPUT.
set -euo pipefail
RUN_ID=$1; CHECK=$2
fail() { echo "::error::run $RUN_ID: $*"; exit 1; }
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || fail "not a run id"
run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID")
IFS=$'\t' read -r n conclusion event branch wf < <(jq -r '[.run_number, .conclusion, .event, .head_branch, .path] | @tsv' <<< "$run")
echo "run $RUN_ID = Build App #$n: $event on $branch, $conclusion"
[ "$wf" = .github/workflows/build-app.yml ] || fail "is not a Build App run ($wf)"
[ "$conclusion" = success ] || fail "did not succeed ($conclusion): a store gets only a build whose checks all passed"
case "$event:$branch" in
  push:*|workflow_dispatch:main) ;;
  *) fail "was built from $branch, not main or a tag" ;;
esac
passed=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID/jobs?per_page=100" \
  --jq ".jobs[] | select(.name | startswith(\"$CHECK\")) | .conclusion" | sort -u)
[ "$passed" = success ] || fail "its check '$CHECK' did not pass (${passed:-not run})"
dir=$(mktemp -d)
gh run download "$RUN_ID" -R "$GITHUB_REPOSITORY" -n "build-info-$n" -D "$dir" > /dev/null 2>&1 \
  || fail "has no build-info-$n artifact (built before the check existed, or expired): build again"
origin=$(jq -r .online_origin "$dir/build-info.json")
[ "$origin" = https://dhamma.gift ] || fail "talks to $origin, not https://dhamma.gift"
echo "dg-node $(jq -r .dg_node "$dir/build-info.json"), site $origin, '$CHECK' passed"
echo "run_number=$n" >> "$GITHUB_OUTPUT"
