#!/usr/bin/env bash
# Tests for the pure parts of flake-update-bot.sh, with Hydra's API stubbed.
# Run: bash packages/flake-update-bot/tests.sh
set -euo pipefail
cd "$(dirname "$0")"

export FUB_REPO=example/repo FUB_HOSTS="juicy-j freddie-kane" FUB_LIB_ONLY=1
export FUB_POLL=0 FUB_EVAL_TIMEOUT=5
# shellcheck source=flake-update-bot.sh
source ./flake-update-bot.sh

fails=0
check() { # name, expected, actual
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "  expected: $2"
    echo "  actual:   $3"
    fails=$((fails + 1))
  fi
}

REV=1111111111111111111111111111111111111111
EVALS_WITH_REV='{"evals":[{"id":7,"flake":"git+https://github.com/example/repo?ref=flake-update&rev='$REV'","builds":[70,71]},{"id":6,"flake":"git+https://github.com/example/repo?ref=flake-update&rev=0000","builds":[60]}]}'
EVALS_OLD_ONLY='{"evals":[{"id":6,"flake":"git+https://github.com/example/repo?ref=flake-update&rev=0000","builds":[60]}]}'

# --- find_eval -------------------------------------------------------------
EVALS=$EVALS_WITH_REV
hydra_get() { echo "$EVALS"; }
check "find_eval picks the eval for the revision" 7 "$(find_eval "$REV" | jq -r .id)"
EVALS=$EVALS_OLD_ONLY
check "find_eval prints nothing when no eval matches" "" "$(find_eval "$REV")"

# --- gating_summary --------------------------------------------------------
ok_j='{"id":70,"job":"nixos.juicy-j","finished":1,"buildstatus":0,"drvpath":"/nix/store/a.drv","buildoutputs":{"out":{"path":"/nix/store/a"}}}'
ok_f='{"id":71,"job":"nixos.freddie-kane","finished":1,"buildstatus":0,"drvpath":"/nix/store/b.drv","buildoutputs":{"out":{"path":"/nix/store/b"}}}'
bad_f='{"id":71,"job":"nixos.freddie-kane","finished":1,"buildstatus":2,"drvpath":"/nix/store/b.drv","buildoutputs":{}}'
run_f='{"id":71,"job":"nixos.freddie-kane","finished":0,"buildstatus":null,"drvpath":"/nix/store/b.drv","buildoutputs":{}}'
other='{"id":72,"job":"nixos.playground","finished":1,"buildstatus":1,"drvpath":"/nix/store/c.drv","buildoutputs":{}}'

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j,$ok_f,$other]")
check "all gating builds ok is success" success "$(jq -r .state <<<"$s")"
check "success lists output paths" "/nix/store/a /nix/store/b" "$(jq -r '[.ok[].out] | join(" ")' <<<"$s")"

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j,$bad_f]")
check "a failed gating build is failure" failure "$(jq -r .state <<<"$s")"
check "failure carries the drv path" "/nix/store/b.drv" "$(jq -r '.failed[0].drvpath' <<<"$s")"

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j,$run_f]")
check "an unfinished gating build is pending" pending "$(jq -r .state <<<"$s")"

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j]")
check "a gating job absent from the eval is failure" failure "$(jq -r .state <<<"$s")"
check "the absent job is reported as missing" "nixos.freddie-kane" "$(jq -r '.missing[0]' <<<"$s")"

s=$(gating_summary juicy-j <<<"[$ok_j,$other]")
check "a failing non-gating job does not gate" success "$(jq -r .state <<<"$s")"

# --- wait_for_eval ---------------------------------------------------------
JOBSET='{}'
hydra_get() {
  case $1 in
    */evals) echo "$EVALS" ;;
    *) echo "$JOBSET" ;;
  esac
}

EVALS=$EVALS_WITH_REV
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "wait_for_eval returns the eval for the revision" "0 7" "$rc $(jq -r .id <<<"$EVAL_JSON")"

EVALS=$EVALS_OLD_ONLY
JOBSET='{"lastcheckedtime":200,"errortime":200,"errormsg":"error: attribute missing","fetcherrormsg":null}'
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "an evaluation error after the push fails fast" "1 error: attribute missing" "$rc $EVAL_ERROR"

JOBSET='{"lastcheckedtime":50,"errortime":50,"errormsg":"stale error","fetcherrormsg":null}'
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "an error from before the push is ignored; the timeout is rc 2, not a build failure" 2 "$rc"
check "the timeout says so" "Timed out" "${EVAL_ERROR:0:9}"

# --- Hydra unreachable is not a build failure ---------------------------------
hydra_get() { return 22; }
FUB_EVAL_TIMEOUT=2
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "Hydra unreachable during the eval wait is rc 2" 2 "$rc"

EVAL_JSON='{"id":7,"builds":[70,71]}'
FUB_BUILD_TIMEOUT=2
wait_for_builds
check "Hydra unreachable during the build wait is a timeout, not a failure" timeout "$(jq -r .state <<<"$SUMMARY")"

hydra_get() {
  case $1 in
    /build/70) echo "$ok_j" ;;
    /build/71) echo "$ok_f" ;;
  esac
}
wait_for_builds
check "wait_for_builds reports success once builds are readable" success "$(jq -r .state <<<"$SUMMARY")"

# --- redact ----------------------------------------------------------------
CREDENTIALS_DIRECTORY=$(mktemp -d)
export CREDENTIALS_DIRECTORY
printf 'ghp_SECRETVALUE\n' >"$CREDENTIALS_DIRECTORY/gh-token"
check "redact removes a credential from text" "token is [redacted] ok" \
  "$(echo "token is ghp_SECRETVALUE ok" | redact)"
check "redact leaves other text alone" "nothing secret" "$(echo "nothing secret" | redact)"
rm -rf "$CREDENTIALS_DIRECTORY"
unset CREDENTIALS_DIRECTORY

# Hydra has checked twice since the push without producing a new evaluation:
# the jobs are unchanged, so the latest listed evaluation is the result.
# hydra_get runs in a command substitution, so count calls through a file.
count_file=$(mktemp)
echo 0 >"$count_file"
hydra_get() {
  case $1 in
    */evals) echo "$EVALS" ;;
    *)
      n=$(($(cat "$count_file") + 1))
      echo "$n" >"$count_file"
      echo "{\"lastcheckedtime\":$((200 + n)),\"errormsg\":\"\",\"fetcherrormsg\":null}"
      ;;
  esac
}
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "unchanged jobs fall back to the latest evaluation" "0 6" "$rc $(jq -r .id <<<"$EVAL_JSON")"
rm -f "$count_file"

# --- success_report --------------------------------------------------------
FUB_HYDRA_PUBLIC_URL=https://hydra.example
SUMMARY=$(gating_summary juicy-j <<<"[$ok_j]")
check "success_report renders a table row" \
  '| `juicy-j` | [70](https://hydra.example/build/70) | `/nix/store/a` |' \
  "$(success_report | tail -n 1)"

if ((fails > 0)); then
  echo "$fails test(s) failed"
  exit 1
fi
echo "all tests passed"
