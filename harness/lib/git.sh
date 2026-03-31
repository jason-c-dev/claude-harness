#!/usr/bin/env bash
# Git operations for the harness orchestrator

set -euo pipefail

# Source utils if not already loaded
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=utils.sh
[[ -z "${HARNESS_STATE:-}" ]] && source "${SCRIPT_DIR}/utils.sh"

# Create the harness branch from main
git_create_harness_branch() {
  local project_slug="$1"
  local harness_branch="harness/${project_slug}"

  # Determine base branch
  local base_branch
  base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

  # If no remote, use current branch or main
  if ! git rev-parse --verify "$base_branch" &>/dev/null; then
    base_branch=$(git branch --show-current 2>/dev/null || echo "main")
  fi

  log_info "Creating harness branch: ${harness_branch} from ${base_branch}"
  (git checkout -b "$harness_branch" "$base_branch" 2>/dev/null || git checkout "$harness_branch") >&2

  echo "$harness_branch"
}

# Create a sprint branch for the generator to work in
git_create_sprint_branch() {
  local harness_branch="$1"
  local sprint_num="$2"
  local sprint_branch="${harness_branch}-sprint-$(sprint_pad "$sprint_num")"

  log_info "Creating sprint branch: ${sprint_branch}"

  # Clean up any existing sprint branch (from a previous failed attempt)
  if git rev-parse --verify "$sprint_branch" &>/dev/null; then
    git branch -D "$sprint_branch" 2>/dev/null || true
  fi

  git checkout -b "$sprint_branch" "$harness_branch" >&2

  echo "$sprint_branch"
}

# Merge a sprint branch back to the harness branch on PASS
git_merge_sprint() {
  local harness_branch="$1"
  local sprint_num="$2"
  local attempt="$3"
  local sprint_branch="${harness_branch}-sprint-$(sprint_pad "$sprint_num")"

  log_info "Merging sprint $(sprint_pad "$sprint_num") to ${harness_branch}"

  # Commit any uncommitted changes on the sprint branch (evaluator may have written files)
  git add -A 2>/dev/null || true
  git diff --cached --quiet 2>/dev/null || git commit -q -m "harness(sprint-$(sprint_pad "$sprint_num")): evaluator artifacts"

  git checkout "$harness_branch" >&2
  git merge --no-ff "$sprint_branch" \
    -m "harness(sprint-$(sprint_pad "$sprint_num")): merge (PASS, attempt ${attempt})" >&2

  local merge_sha
  merge_sha=$(git rev-parse HEAD)

  # Tag the merge point
  local tag="harness/sprint-$(sprint_pad "$sprint_num")/pass"
  git tag "$tag"
  log_success "Tagged: ${tag}"

  # Delete the sprint branch (merged)
  git branch -d "$sprint_branch" >&2

  echo "$merge_sha"
}

# Tag a failed sprint attempt for forensics, then delete the branch
git_fail_sprint_attempt() {
  local harness_branch="$1"
  local sprint_num="$2"
  local attempt="$3"
  local sprint_branch="${harness_branch}-sprint-$(sprint_pad "$sprint_num")"

  # Tag for forensics
  local tag="harness/sprint-$(sprint_pad "$sprint_num")/attempt-${attempt}"
  git tag "$tag" 2>/dev/null || true
  log_warn "Tagged failed attempt: ${tag}"

  # Switch back to harness branch and delete the sprint branch
  # Stash any uncommitted changes from the failed attempt (evaluator may have written files)
  git stash -q 2>/dev/null || true
  git checkout "$harness_branch"
  git stash drop -q 2>/dev/null || true
  git branch -D "$sprint_branch" 2>/dev/null || true
}

# Commit harness-state files
git_commit_harness_state() {
  local message="$1"

  git add "${HARNESS_STATE}/" 2>/dev/null || true
  git add -u "${HARNESS_STATE}/" 2>/dev/null || true

  if git diff --cached --quiet 2>/dev/null; then
    log_info "No harness-state changes to commit"
    return
  fi

  git commit -m "$message"
}

# Create PR from harness branch to main
git_create_pr() {
  local harness_branch="$1"
  local project_slug="$2"
  local pr_body="$3"

  if ! command -v gh &>/dev/null; then
    log_warn "gh CLI not found -- skipping PR creation"
    log_info "Harness branch ready: ${harness_branch}"
    log_info "Create PR manually: git push && gh pr create"
    return
  fi

  # Check if remote exists
  if ! git remote get-url origin &>/dev/null; then
    log_warn "No git remote configured -- skipping PR creation"
    log_info "Harness branch ready: ${harness_branch}"
    return
  fi

  log_info "Pushing harness branch and creating PR..."
  git push -u origin "$harness_branch"

  local base_branch
  base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

  local pr_title="harness: ${project_slug}"
  # GitHub PR title limit is 256 characters
  if [[ ${#pr_title} -gt 256 ]]; then
    pr_title="${pr_title:0:253}..."
  fi

  gh pr create \
    --base "$base_branch" \
    --head "$harness_branch" \
    --title "$pr_title" \
    --body "$pr_body"
}

# Create a PR for a fix branch (instead of merging locally)
git_create_fix_pr() {
  local fix_branch="$1"
  local base_branch="$2"
  local fix_id="$3"
  local bug_description="$4"
  local issue_number="${5:-}"

  if ! command -v gh &>/dev/null; then
    log_warn "gh CLI not found -- skipping PR creation"
    log_info "Fix branch ready: ${fix_branch}"
    log_info "Create PR manually: git push && gh pr create"
    return
  fi

  if ! git remote get-url origin &>/dev/null; then
    log_warn "No git remote configured -- skipping PR creation"
    log_info "Fix branch ready: ${fix_branch}"
    return
  fi

  # If the base branch doesn't exist on the remote, fall back to default branch
  if ! git ls-remote --heads origin "$base_branch" | grep -q .; then
    local fallback
    fallback=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    log_warn "Base branch '${base_branch}' not found on remote, falling back to '${fallback}'"
    base_branch="$fallback"
  fi

  log_info "Pushing fix branch and creating PR..."
  git push -u origin "$fix_branch"
  git push origin "harness/${fix_id}/pass" 2>/dev/null || true

  local issue_ref=""
  if [[ -n "$issue_number" ]]; then
    issue_ref="Fixes #${issue_number}"
  fi

  local pr_body="## Fix: ${fix_id}

### Bug
${bug_description}

### Verification
- Fix evaluated and passed all criteria
- Regression registry updated
${issue_ref}

---
Built with the [Planner-Generator-Evaluator Harness](https://www.anthropic.com/engineering/harness-design-long-running-apps)"

  gh pr create \
    --base "$base_branch" \
    --head "$fix_branch" \
    --title "harness(${fix_id}): ${bug_description:0:50}" \
    --body "$pr_body"
}

# Create a GitHub issue for a bug fix. Echoes the issue number to stdout.
git_create_issue() {
  local title="$1"
  local body="$2"

  if ! command -v gh &>/dev/null; then
    log_warn "gh CLI not found -- skipping issue creation"
    echo ""
    return
  fi

  if ! git remote get-url origin &>/dev/null; then
    log_warn "No git remote configured -- skipping issue creation"
    echo ""
    return
  fi

  local issue_url
  issue_url=$(gh issue create \
    --title "$title" \
    --body "$body" \
    --label "harness-fix,bug" 2>/dev/null) || { log_warn "Failed to create issue"; echo ""; return; }

  # Extract issue number from URL (e.g., https://github.com/owner/repo/issues/42 -> 42)
  local issue_number
  issue_number=$(echo "$issue_url" | grep -o '[0-9]*$')
  echo "$issue_number"
}

# Generate PR body from harness state
generate_pr_body() {
  local project_name
  project_name=$(json_read "${HARNESS_STATE}/config.json" ".userPrompt" | head -c 80)

  local sprint_rows=""
  local sprint_count
  sprint_count=$(json_read "${HARNESS_STATE}/sprint-plan.json" ".sprints | length")

  for i in $(seq 1 "$sprint_count"); do
    local dir
    dir=$(sprint_dir "$i")
    local name
    name=$(json_read "${HARNESS_STATE}/sprint-plan.json" ".sprints[$(( i - 1 ))].name")
    local status="pending"
    local criteria="-" pass="-" fail="-" attempts="-"

    if file_exists "${dir}/eval-report.json"; then
      status=$(json_read "${dir}/eval-report.json" ".overallResult")
      criteria=$(json_read "${dir}/eval-report.json" ".passCount + .failCount")
      pass=$(json_read "${dir}/eval-report.json" ".passCount")
      fail=$(json_read "${dir}/eval-report.json" ".failCount")
      attempts=$(json_read "${dir}/eval-report.json" ".attempt")
    fi

    sprint_rows+="| $(sprint_pad "$i") | ${name} | ${status} | ${criteria} | ${pass} | ${fail} | ${attempts} | - |\n"
  done

  cat <<EOF
## Harness: ${project_name}

### Sprint Results

| Sprint | Name | Status | Criteria | Pass | Fail | Attempts | Cost |
|--------|------|--------|----------|------|------|----------|------|
$(echo -e "$sprint_rows")

### Configuration
- Model: $(json_read "${HARNESS_STATE}/config.json" ".model")
- Context strategy: $(json_read "${HARNESS_STATE}/config.json" ".contextStrategy")
- Project type: $(json_read "${HARNESS_STATE}/config.json" ".projectType")

---
Built with the [Planner-Generator-Evaluator Harness](https://www.anthropic.com/engineering/harness-design-long-running-apps)
EOF
}
