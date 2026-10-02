# flake-update-bot: update flake.lock, open a PR, gate it on Hydra, and let
# Claude Code try to fix a failing build. Configured through the environment
# by modules/nixos/flake-update-bot; secrets come from systemd credentials.

: "${FUB_REPO:?owner/name of the GitHub repo}"
: "${FUB_HOSTS:?space-separated hosts whose nixos.<host> job gates the PR}"
FUB_BRANCH=${FUB_BRANCH:-flake-update}
FUB_BASE=${FUB_BASE:-master}
FUB_HYDRA_URL=${FUB_HYDRA_URL:-http://127.0.0.1:3001}
FUB_HYDRA_PUBLIC_URL=${FUB_HYDRA_PUBLIC_URL:-$FUB_HYDRA_URL}
FUB_HYDRA_PROJECT=${FUB_HYDRA_PROJECT:-all-the-nix}
FUB_HYDRA_JOBSET=${FUB_HYDRA_JOBSET:-flake-update}
FUB_MAX_FIX_ATTEMPTS=${FUB_MAX_FIX_ATTEMPTS:-3}
FUB_STATE_DIR=${FUB_STATE_DIR:-$HOME/.local/state/flake-update-bot}
FUB_EVAL_TIMEOUT=${FUB_EVAL_TIMEOUT:-2700}
FUB_BUILD_TIMEOUT=${FUB_BUILD_TIMEOUT:-14400}
FUB_CLAUDE_TIMEOUT=${FUB_CLAUDE_TIMEOUT:-3600}
FUB_POLL=${FUB_POLL:-30}
# Testing aid: skip the lock update and gate whatever is already on FUB_BRANCH.
FUB_SKIP_UPDATE=${FUB_SKIP_UPDATE:-}

EVAL_JSON=""
EVAL_ERROR=""
SUMMARY=""
TMP_DIR=""

log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }

cred() { cat "${CREDENTIALS_DIRECTORY:?not started by systemd}/$1"; }

hydra_get() {
  curl -fsS --retry 5 --retry-all-errors --retry-delay 5 \
    -H 'Accept: application/json' "$FUB_HYDRA_URL$1"
}

jobset_path() { printf '/jobset/%s/%s' "$FUB_HYDRA_PROJECT" "$FUB_HYDRA_JOBSET"; }

# Print the evaluation whose locked flake ref contains revision $1, if any.
# Hydra only lists evaluations that produced new builds.
find_eval() {
  hydra_get "$(jobset_path)/evals" |
    jq -c --arg rev "$1" 'first(.evals[] | select((.flake // "") | contains($rev))) // empty'
}

# stdin: JSON array of Hydra build objects. args: gating hosts.
# stdout: {state, missing, pending, failed, ok}; state is pending|failure|success.
gating_summary() {
  local hosts_json
  hosts_json=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
  jq -c --argjson hosts "$hosts_json" '
    def done: .finished == 1 or .finished == true;
    . as $builds
    | [ $hosts[] | "nixos." + . | . as $job
        | { job: $job, build: ($builds | map(select(.job == $job)) | first) } ] as $rows
    | {
        missing: [ $rows[] | select(.build == null) | .job ],
        pending: [ $rows[] | select(.build != null and (.build | done | not))
                   | { job, id: .build.id } ],
        failed:  [ $rows[] | select(.build != null and (.build | done) and .build.buildstatus != 0)
                   | { job, id: .build.id, buildstatus: .build.buildstatus, drvpath: .build.drvpath } ],
        ok:      [ $rows[] | select(.build != null and (.build | done) and .build.buildstatus == 0)
                   | { job, id: .build.id, out: (.build.buildoutputs.out.path // null) } ]
      }
    | .state = (if (.pending | length) > 0 then "pending"
                elif ((.missing | length) + (.failed | length)) > 0 then "failure"
                else "success" end)'
}

# Wait for Hydra to evaluate revision $1, pushed at epoch $2.
# Returns 0 with EVAL_JSON set; 1 with EVAL_ERROR set when the flake fails to
# evaluate (something a fix can address); 2 with EVAL_ERROR set when Hydra
# gave no answer (unreachable, or timed out).
wait_for_eval() {
  local rev=$1 since=$2 deadline=$((SECONDS + FUB_EVAL_TIMEOUT))
  local first_check="" js lct errtime msg
  EVAL_JSON="" EVAL_ERROR=""
  while ((SECONDS < deadline)); do
    EVAL_JSON=$(find_eval "$rev") || EVAL_JSON=""
    [[ -n $EVAL_JSON ]] && return 0
    js=$(hydra_get "$(jobset_path)") || js='{}'
    lct=$(jq -r '.lastcheckedtime // 0' <<<"$js")
    if ((lct >= since)); then
      errtime=$(jq -r '.errortime // 0' <<<"$js")
      msg=$(jq -r '.errormsg // ""' <<<"$js")
      if [[ -n $msg ]] && ((errtime >= since)); then
        EVAL_ERROR=$msg
        return 1
      fi
      # A fetch error is usually transient: remember it and keep polling.
      EVAL_ERROR=$(jq -r '.fetcherrormsg // ""' <<<"$js")
      if [[ -z $EVAL_ERROR ]]; then
        if [[ -z $first_check ]]; then
          first_check=$lct
        elif ((lct > first_check)); then
          # Checked twice since the push and still no evaluation for this
          # revision: the jobs are identical to the latest listed evaluation.
          EVAL_JSON=$(hydra_get "$(jobset_path)/evals" | jq -c '.evals[0] // empty') || EVAL_JSON=""
          [[ -n $EVAL_JSON ]] && return 0
          EVAL_ERROR="Hydra checked the jobset but has no evaluation at all."
          return 2
        fi
      fi
    fi
    sleep "$FUB_POLL"
  done
  EVAL_ERROR=${EVAL_ERROR:-"Timed out after ${FUB_EVAL_TIMEOUT}s waiting for Hydra to evaluate $rev."}
  return 2
}

# Print the builds of EVAL_JSON as a JSON array. Fails if any cannot be read,
# so an unreachable Hydra is never mistaken for a missing job.
fetch_builds() {
  local id
  for id in $(jq -r '.builds[]' <<<"$EVAL_JSON"); do
    hydra_get "/build/$id" || return 1
  done | jq -sc .
}

# Wait for the gating builds of EVAL_JSON to finish. Sets SUMMARY, whose state
# is success, failure, or timeout (builds unfinished or Hydra unreachable).
wait_for_builds() {
  local deadline=$((SECONDS + FUB_BUILD_TIMEOUT)) builds
  local -a hosts
  read -r -a hosts <<<"$FUB_HOSTS"
  SUMMARY='{"missing":[],"pending":[],"failed":[],"ok":[]}'
  while :; do
    if builds=$(fetch_builds); then
      SUMMARY=$(gating_summary "${hosts[@]}" <<<"$builds")
      [[ $(jq -r .state <<<"$SUMMARY") != pending ]] && return 0
    fi
    if ((SECONDS >= deadline)); then
      SUMMARY=$(jq -c '.state = "timeout"' <<<"$SUMMARY")
      return 0
    fi
    sleep "$FUB_POLL"
  done
}

# Re-run a failed derivation locally to get Nix's own error and log tail.
# Everything that did build is already in the store, so only the failure reruns.
build_log_tail() {
  timeout 2h nix build --no-link --keep-going --log-lines 60 "$1^*" </dev/null 2>&1 | tail -n 80 || true
}

success_report() {
  jq -r --arg url "$FUB_HYDRA_PUBLIC_URL" '
    "| Host | Hydra build | Output |", "|---|---|---|",
    (.ok[] | "| `\(.job | ltrimstr("nixos."))` | [\(.id)](\($url)/build/\(.id)) | `\(.out)` |")' <<<"$SUMMARY"
}

failure_report() {
  local job id status drv missing
  while IFS=$'\t' read -r job id status drv; do
    printf '#### `%s`: [build %s](%s/build/%s) failed (status %s)\n\n```\n' \
      "$job" "$id" "$FUB_HYDRA_PUBLIC_URL" "$id" "$status"
    build_log_tail "$drv"
    printf '```\n\n'
  done < <(jq -r '.failed[] | [.job, .id, .buildstatus, .drvpath] | @tsv' <<<"$SUMMARY")
  missing=$(jq -r '[.missing[]] | join(", ")' <<<"$SUMMARY")
  if [[ -n $missing ]]; then
    printf '#### Not evaluated: %s\n\n```\n' "$missing"
    hydra_get "$(jobset_path)" | jq -r '.errormsg // ""' | tail -n 60
    printf '```\n\n'
  fi
}

# Gate revision $1 (pushed at epoch $2) on Hydra. Writes markdown to $3.
# Returns 0 when the gating builds succeeded, 1 when the flake failed to
# evaluate or build, 2 when Hydra gave no result (nothing to fix).
gate() {
  local rev=$1 since=$2 out=$3 rc=0
  log "waiting for Hydra to evaluate $rev"
  wait_for_eval "$rev" "$since" || rc=$?
  if ((rc != 0)); then
    printf 'Hydra did not produce an evaluation for `%s`.\n\n```\n%s\n```\n' \
      "$rev" "$(tail -n 60 <<<"$EVAL_ERROR")" >"$out"
    return "$rc"
  fi
  log "evaluation $(jq -r .id <<<"$EVAL_JSON"); waiting for builds"
  wait_for_builds
  case $(jq -r .state <<<"$SUMMARY") in
    success)
      success_report >"$out"
      return 0
      ;;
    timeout)
      printf 'No result from Hydra after %ss for evaluation %s. Still pending: %s\n' \
        "$FUB_BUILD_TIMEOUT" "$(jq -r .id <<<"$EVAL_JSON")" \
        "$(jq -r '[.pending[].job] | join(", ") | if . == "" then "unknown" else . end' <<<"$SUMMARY")" >"$out"
      return 2
      ;;
  esac
  failure_report >"$out"
  return 1
}

gh_() { GH_TOKEN=$(cred gh-token) gh "$@"; }

# stdin to stdout, with the value of every credential replaced. Claude's
# output and build logs end up in public PR comments.
redact() {
  local name secret text
  text=$(cat)
  for name in gh-token claude-token pushover-user pushover-token; do
    [[ -r ${CREDENTIALS_DIRECTORY:-}/$name ]] || continue
    secret=$(cred "$name")
    if [[ -n $secret ]]; then
      text=${text//"$secret"/[redacted]}
    fi
  done
  printf '%s\n' "$text"
}

comment() {
  redact <"$2" >"$2.safe"
  truncate -s '<60000' "$2.safe" # GitHub rejects comment bodies over 65536 characters
  gh_ pr comment "$1" -R "$FUB_REPO" --body-file "$2.safe" >/dev/null
}

push_branch() {
  local token_file="$CREDENTIALS_DIRECTORY/gh-token" name hits
  for name in gh-token claude-token; do
    hits=$(git log -p "origin/$FUB_BASE..HEAD" | grep -cF -- "$(cred "$name")" || true)
    if [[ $hits != 0 ]]; then
      log "refusing to push: a commit contains the $name secret"
      exit 1
    fi
  done
  # The helper is scoped to github.com and the URL is explicit, so the token
  # cannot be sent to whatever the clone's remotes have been edited to.
  git -c credential.helper= \
    -c "credential.https://github.com.helper=!f() { echo username=x-access-token; echo \"password=\$(cat '$token_file')\"; }; f" \
    push --force "https://github.com/$FUB_REPO.git" "HEAD:refs/heads/$FUB_BRANCH"
}

notify() {
  local dir=${CREDENTIALS_DIRECTORY:-}
  [[ -r $dir/pushover-user && -r $dir/pushover-token ]] || return 0
  # Passed as a config on stdin so the keys never appear in curl's arguments.
  curl -fsS -o /dev/null -K - <<EOF || log "pushover notification failed"
url = "https://api.pushover.net/1/messages.json"
form-string = "token=$(cred pushover-token)"
form-string = "user=$(cred pushover-user)"
form-string = "title=flake update"
form-string = "message=$1"
EOF
}

# Hydra gave no result for PR $1 (report in $2): say so and stop. There is no
# build failure for Claude to fix.
stop_without_result() {
  { printf '### ⚠️ No result from Hydra\n\n'; cat "$2"; printf '\nNo fix was attempted.\n'; } >"$TMP_DIR/comment"
  comment "$1" "$TMP_DIR/comment"
  notify "PR #$1: no result from Hydra"
  exit 1
}

# Let Claude Code attempt a fix. $1: failure report, $2: file for its summary.
# Returns 0 only if it committed something.
run_claude() {
  local report=$1 summary=$2 before prompt
  before=$(git rev-parse HEAD)
  prompt=$(
    cat <<EOF
You are running unattended in a clone of the $FUB_REPO flake, on branch
$FUB_BRANCH. The last commits updated flake.lock, and Hydra failed to build the
NixOS system closures for: $FUB_HOSTS. The failure report follows.

$(cat "$report")

Fix it so that this builds for every host listed above:

  nix build --no-link .#nixosConfigurations.<host>.config.system.build.toplevel

Rules:
- Make the smallest change that fixes the build. Do not refactor.
- Do not remove features, hosts or packages to get a green build, unless the
  package was removed upstream; say so if that is the case.
- Pinning a single input back to its previous revision is acceptable if a real
  fix is not practical. Explain why.
- Run the nix build above for each failing host and confirm it succeeds.
- New files must be git-added before nix can see them.
- Commit your fix on the current branch. Do not push.
- Your final message is posted on the pull request: say what was wrong, what
  you changed, and how you verified it, in under 200 words.
EOF
  )
  log "running claude"
  CLAUDE_CODE_OAUTH_TOKEN=$(cred claude-token) \
    CLAUDE_CONFIG_DIR="$FUB_STATE_DIR/claude" \
    BASH_DEFAULT_TIMEOUT_MS=3600000 BASH_MAX_TIMEOUT_MS=3600000 \
    env -u CREDENTIALS_DIRECTORY \
    timeout "$FUB_CLAUDE_TIMEOUT" claude -p "$prompt" \
    --permission-mode dontAsk \
    --allowedTools Read Edit Write Glob Grep \
    'Bash(nix:*)' 'Bash(git add:*)' 'Bash(git commit:*)' 'Bash(git diff:*)' \
    'Bash(git status:*)' 'Bash(git log:*)' 'Bash(git show:*)' \
    >"$summary" 2>"$FUB_STATE_DIR/claude-stderr.log" || log "claude exited non-zero"
  git reset --hard -q
  git clean -fdq
  [[ $(git rev-parse HEAD) != "$before" ]]
}

prepare_repo() {
  local repo="$FUB_STATE_DIR/repo"
  if [[ ! -d $repo/.git ]]; then
    git clone "https://github.com/$FUB_REPO.git" "$repo"
  fi
  cd "$repo"
  git fetch --prune origin
  git reset --hard -q
  git clean -fdq
}

open_pr_number() {
  gh_ pr list -R "$FUB_REPO" --head "$FUB_BRANCH" --state open --json number --jq '.[0].number // empty'
}

main() {
  local tmp update_log pr rev since report summary attempt=0 old rc
  mkdir -p "$FUB_STATE_DIR"
  exec 9>"$FUB_STATE_DIR/lock"
  flock -n 9 || {
    log "another run holds the lock"
    exit 0
  }
  # Global, because the EXIT trap also runs after main's locals are gone.
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT
  tmp=$TMP_DIR
  report=$tmp/report.md
  summary=$tmp/claude-summary.md
  update_log=$tmp/update.log

  prepare_repo
  if [[ -n $FUB_SKIP_UPDATE ]]; then
    git checkout -q -B "$FUB_BRANCH" "origin/$FUB_BRANCH"
    pr=$(open_pr_number)
    since=$(date +%s)
  else
    git checkout -q -B "$FUB_BRANCH" "origin/$FUB_BASE"
    nix flake update 2>"$update_log" || {
      cat "$update_log" >&2
      exit 1
    }
    if git diff --quiet -- flake.lock; then
      log "flake.lock is already up to date"
      exit 0
    fi
    {
      printf 'flake update %s\n\n' "$(date +%F)"
      grep -v '^warning:' "$update_log" || true
    } >"$tmp/commit-msg"
    git commit -q -F "$tmp/commit-msg" -- flake.lock
    old=$(open_pr_number)
    if [[ -n $old ]]; then
      gh_ pr close "$old" -R "$FUB_REPO" --comment "Superseded by this week's update."
    fi
    push_branch
    # Taken after the push: a Hydra check that finished before it has not
    # seen this commit and must not count as "checked since the push".
    since=$(date +%s)
    pr=""
  fi
  if [[ -z $pr ]]; then
    {
      printf 'Weekly `nix flake update`. Hydra builds: %s.\n\n```\n' "$FUB_HOSTS"
      git log -1 --format=%b
      printf '```\n'
    } >"$tmp/pr-body"
    gh_ pr create -R "$FUB_REPO" --base "$FUB_BASE" --head "$FUB_BRANCH" \
      --title "$(git log -1 --format=%s)" --body-file "$tmp/pr-body" >/dev/null
    pr=$(open_pr_number)
  fi
  rev=$(git rev-parse HEAD)
  log "PR #$pr at $rev"

  rc=0
  gate "$rev" "$since" "$report" || rc=$?
  if ((rc == 0)); then
    { printf '### ✅ Hydra build succeeded\n\n'; cat "$report"; } >"$tmp/comment"
    comment "$pr" "$tmp/comment"
    notify "PR #$pr: build succeeded"
    exit 0
  elif ((rc == 2)); then
    stop_without_result "$pr" "$report"
  fi
  { printf '### ❌ Hydra build failed\n\n'; cat "$report"; } >"$tmp/comment"
  comment "$pr" "$tmp/comment"

  while ((attempt < FUB_MAX_FIX_ATTEMPTS)); do
    attempt=$((attempt + 1))
    if ! run_claude "$report" "$summary"; then
      printf '### ❌ Fix attempt %s: Claude did not produce a commit\n\n%s\n' \
        "$attempt" "$(cat "$summary")" >"$tmp/comment"
      comment "$pr" "$tmp/comment"
      continue
    fi
    push_branch
    since=$(date +%s)
    rev=$(git rev-parse HEAD)
    rc=0
    gate "$rev" "$since" "$report" || rc=$?
    if ((rc == 2)); then
      stop_without_result "$pr" "$report"
    elif ((rc == 0)); then
      {
        printf '### ✅ Fixed by Claude on attempt %s\n\n%s\n\n' "$attempt" "$(cat "$summary")"
        cat "$report"
      } >"$tmp/comment"
      comment "$pr" "$tmp/comment"
      notify "PR #$pr: build fixed by Claude on attempt $attempt"
      exit 0
    fi
    {
      printf '### ❌ Fix attempt %s did not build\n\n%s\n\n' "$attempt" "$(cat "$summary")"
      cat "$report"
    } >"$tmp/comment"
    comment "$pr" "$tmp/comment"
  done

  printf '### 🛑 Giving up after %s fix attempt(s)\n\nThe branch is left as it is for a human.\n' \
    "$attempt" >"$tmp/comment"
  comment "$pr" "$tmp/comment"
  notify "PR #$pr: build failed, gave up after $attempt fix attempt(s)"
  exit 1
}

if [[ -z ${FUB_LIB_ONLY:-} ]]; then
  main "$@"
fi
