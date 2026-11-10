#!/usr/bin/env bash
set -euo pipefail

variant=$1
manifest=packaging/plugins/$variant
package=caddy-$variant
branch=automation/plugin-$variant
candidate=$(mktemp)
trap 'rm -f "$candidate"' EXIT

{
    read -r revision revision_upstream
    while read -r alias module pinned id; do
        versions=$(go list -m -versions -retracted=false -json "$module")
        latest=$(jq -r '.Versions[]? | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' <<< "$versions" | sort -V | tail -n 1)
        if [[ -n $latest ]] && dpkg --compare-versions "${latest#v}" gt "${pinned#v}"; then
            pinned=$latest
        fi
        printf '%s %s %s %s\n' "$alias" "$module" "$pinned" "$id"
    done
} < "$manifest" > "$candidate"

if [[ ${VERIFY_CURRENT:-false} != true ]] && cmp -s <(tail -n +2 "$manifest") "$candidate"; then
    exit 0
fi

published=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
    --jq '.[] | select(.draft == false and .prerelease == false) | .assets[].name')
last=$(awk -v prefix="${package}_" 'index($0,prefix)==1 && /_amd64\.deb$/ {
    version=substr($0,length(prefix)+1)
    sub(/[+_].*$/, "", version)
    print version
}' <<< "$published" | sort -V | tail -n 1)
test -n "$last"
upstream=v${last%-*}
published_revision=${last##*-}
base=$(git rev-parse HEAD)

if [[ ${VERIFY_CURRENT:-false} == true ]]; then
    printf 'sha=%s\nupstream=%s\n' "$base" "$upstream" >> "$GITHUB_OUTPUT"
    exit 0
fi

if [[ $revision_upstream != "$upstream" ]] || ((revision < published_revision)); then
    revision=$published_revision
fi
{
    printf '%s %s\n' "$((revision + 1))" "$upstream"
    cat "$candidate"
} > "$manifest"

remote=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
if [[ -n $remote ]]; then
    git fetch --no-tags origin "refs/heads/$branch"
fi
if [[ -n $remote ]] && [[ $(git rev-parse "$remote^") == "$base" ]] && [[ $(git diff --name-only "$base" "$remote") == "$manifest" ]] && git diff --quiet "$remote" -- "$manifest"; then
    sha=$remote
else
    git add "$manifest"
    git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
        commit -m "Update $package plugin versions"
    sha=$(git rev-parse HEAD)
    git push --force-with-lease="refs/heads/$branch:$remote" origin "HEAD:refs/heads/$branch"
fi
pr=$(gh pr list --repo "$GITHUB_REPOSITORY" --base main --head "$branch" --json number --jq '.[0].number // empty')
if [[ -z $pr ]]; then
    url=$(gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" \
        --title "Update $package plugin versions" \
        --body "Updates the pinned Go modules and Debian revision for $upstream. Both native builds must pass before automation merges this PR.")
    pr=${url##*/}
fi
printf 'sha=%s\nupstream=%s\npr=%s\nbase=%s\n' "$sha" "$upstream" "$pr" "$base" >> "$GITHUB_OUTPUT"
