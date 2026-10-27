#!/bin/bash
# Keep reviewed PR text in a file; never interpolate it into shell commands.
set -euo pipefail
: "${GH_REPO:?Set GH_REPO to owner/repository}"
mode="${1:?Use generate or resolve}"
tag="${2:?Tag required}"
commit="${3:?Commit required}"
output="${4:?Output file required}"
pr="${5:-}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

generate_notes() {
    gh api --method POST "repos/$GH_REPO/releases/generate-notes" \
        -f "tag_name=$tag" -f "target_commitish=$commit" > "$temporary/notes.json"
}

case "$mode" in
    generate)
        generate_notes
        ;;
    resolve)
        if [[ -z "$pr" ]]; then
            gh api --paginate "repos/$GH_REPO/commits/$commit/pulls?per_page=100" > "$temporary/pulls.json"
            jq --slurp --arg repo "$GH_REPO" --arg branch "release/$tag" --arg commit "$commit" \
                '[.[][] | select(.merged_at != null and .base.ref == "main" and
                  .base.repo.full_name == $repo and .head.repo.full_name == $repo and
                  .head.ref == $branch and .merge_commit_sha == $commit)] | unique_by(.number)' \
                "$temporary/pulls.json" > "$temporary/matches.json"
            count="$(jq length "$temporary/matches.json")"
            if [[ "$count" -gt 1 ]]; then
                printf '%s\n' 'Multiple release PRs match this tag; refusing to choose.' >&2
                exit 1
            fi
            pr="$(jq -r '.[0].number // empty' "$temporary/matches.json")"
        fi
        if [[ -n "$pr" ]]; then
            [[ "$pr" =~ ^[1-9][0-9]*$ ]]
            gh api "repos/$GH_REPO/pulls/$pr" > "$temporary/notes.json"
            jq -e --arg repo "$GH_REPO" --arg branch "release/$tag" --arg commit "$commit" \
                '.merged_at != null and .base.ref == "main" and
                 .base.repo.full_name == $repo and .head.repo.full_name == $repo and
                 .head.ref == $branch and .merge_commit_sha == $commit' \
                "$temporary/notes.json" >/dev/null
        else
            generate_notes
        fi
        ;;
    *) printf '%s\n' 'Use generate or resolve.' >&2; exit 1 ;;
esac

# Preserve all bytes, including Markdown, shell-looking text and final newlines.
# An empty reviewed PR body is an error, rather than a reason to regenerate it.
jq -je '.body | select(type == "string" and test("\\S"))' "$temporary/notes.json" > "$temporary/body.md"
mv "$temporary/body.md" "$output"
