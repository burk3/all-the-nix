# Print the store path Hydra built for a host at the commit checked out in the
# current directory, for: nh os switch "$(t11s-cached-system)"
# Exits non-zero when Hydra has no finished, successful build of that commit.

host=${1:-$(</proc/sys/kernel/hostname)}
url=${T11S_HYDRA_URL:-https://hydra.ts.t11s.net}
jobset=${T11S_HYDRA_JOBSET:-all-the-nix/master}

die() {
  echo "t11s-cached-system: $*" >&2
  exit 1
}

get() { curl -fsS -H 'Accept: application/json' "$url$1"; }

[[ -z $(git status --porcelain --untracked-files=no) ]] ||
  die "the working tree has uncommitted changes, so Hydra cannot have built it"
rev=$(git rev-parse HEAD)

# Hydra lists only evaluations that changed the set of builds, so a commit
# that leaves every system unchanged has no entry here.
eval_json=$(get "/jobset/$jobset/evals" |
  jq -c --arg rev "$rev" 'first(.evals[] | select((.flake // "") | contains($rev))) // empty')
[[ -n $eval_json ]] || die "Hydra has no evaluation of $rev in $jobset"

for id in $(jq -r '.builds[]' <<<"$eval_json"); do
  build=$(get "/build/$id")
  [[ $(jq -r .job <<<"$build") == "nixos.$host" ]] || continue
  [[ $(jq -r '(.finished == 1 or .finished == true) and .buildstatus == 0' <<<"$build") == true ]] ||
    die "build $id of nixos.$host is unfinished or failed: $url/build/$id"
  jq -r '.buildoutputs.out.path' <<<"$build"
  exit 0
done
die "the evaluation of $rev has no nixos.$host job"
