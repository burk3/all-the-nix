# fub: the fixed set of privileged actions Claude Code may take while fixing a
# build for flake-update-bot. Claude's shell runs in a sandbox with no network,
# no Nix daemon and no view of the home directory; this is the one command
# excluded from it. So every argument is validated, and nothing here accepts
# arbitrary shell or Nix expressions.

base=${FUB_BASE:-master}

die() {
  echo "fub: $*" >&2
  exit 2
}

usage() {
  cat >&2 <<'EOF'
usage: fub <command>
  build <host>...          build each host's system closure; prints the failure tail
  log <drv> [lines]        tail of a derivation's build log (default 200 lines)
  eval <host> <option>     print a NixOS option value as JSON, e.g. boot.kernelPackages.kernel.version
  input-path <input>       print the store path of a flake input's source
  hold-back <input>...     restore the pre-update flake.lock, then update every input except these
  fmt                      format the .nix files changed on this branch
  commit <message>         stage everything and commit
Run fub as the entire command: no pipes, ;, && or $(...).
EOF
  exit 2
}

name_ok() {
  [[ ${1:-} =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid name: '${1:-}'"
}

# The sandbox blocks the Nix daemon socket. Getting here inside it means fub
# was combined with other shell, which puts the whole command in the sandbox.
need_daemon() {
  nix store info >/dev/null 2>&1 ||
    die "cannot reach the Nix daemon. Run fub as the entire command: no pipes, ;, && or \$(...)."
}

# With lazy-trees, nix only sees files git knows about.
stage() { git add -A; }

cmd=${1:-}
shift || true
case $cmd in
  build)
    (($# > 0)) || usage
    for host in "$@"; do name_ok "$host"; done
    need_daemon
    stage
    rc=0
    for host in "$@"; do
      echo "== $host"
      if out=$(nix build --no-link --log-lines 80 \
        ".#nixosConfigurations.$host.config.system.build.toplevel" 2>&1); then
        echo "BUILD OK: $host"
      else
        tail -n 150 <<<"$out"
        echo "BUILD FAILED: $host"
        rc=1
      fi
    done
    exit "$rc"
    ;;
  log)
    [[ ${1:-} =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9+._?=-]+$ ]] || usage
    lines=${2:-200}
    [[ $lines =~ ^[0-9]+$ ]] || die "lines must be a number"
    need_daemon
    nix log "$1" | tail -n "$lines"
    ;;
  eval)
    (($# == 2)) || usage
    name_ok "$1"
    [[ $2 =~ ^[A-Za-z0-9_.\"-]+$ ]] || die "invalid option path: '$2'"
    need_daemon
    stage
    nix eval --json ".#nixosConfigurations.$1.config.$2" | head -c 20000
    echo
    ;;
  input-path)
    (($# == 1)) || usage
    name_ok "$1"
    need_daemon
    nix eval --impure --raw --expr "(builtins.getFlake (toString ./.)).inputs.\"$1\".outPath"
    echo
    ;;
  hold-back)
    (($# > 0)) || usage
    for input in "$@"; do
      name_ok "$input"
      jq -e --arg i "$input" '.nodes.root.inputs | has($i)' flake.lock >/dev/null ||
        die "no such flake input: $input"
    done
    need_daemon
    git checkout "origin/$base" -- flake.lock
    held=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
    mapfile -t rest < <(jq -r --argjson held "$held" \
      '.nodes.root.inputs | keys[] | select(. as $k | $held | index($k) | not)' flake.lock)
    nix flake update "${rest[@]}" 2>&1 | grep -E '^(•| )' || true
    echo "held back at the pre-update revision: $*"
    ;;
  fmt)
    need_daemon
    stage
    mapfile -t files < <(git diff --cached --name-only --diff-filter=AM "origin/$base" -- '*.nix')
    ((${#files[@]} > 0)) || {
      echo "no changed .nix files"
      exit 0
    }
    nix fmt -- "${files[@]}"
    ;;
  commit)
    (($# == 1)) && [[ -n $1 ]] || usage
    stage
    git diff --cached --quiet && die "nothing to commit"
    if grep -qi "^co-authored-by:" <<<"$1"; then
      git commit -q -m "$1"
    else
      git commit -q -m "$1" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
    fi
    git log --oneline -1
    ;;
  *)
    usage
    ;;
esac
