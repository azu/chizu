#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"
export MOCK_DIR="$fixture" GH_REPO=owner/repo
export PATH="$fixture/bin:$PATH"

cat > "$fixture/bin/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_DIR/calls"
[[ "${MOCK_FAIL:-false}" != true ]]
case "$*" in
    *'/releases/generate-notes'*) cat "$MOCK_DIR/generated.json" ;;
    *'/commits/'*) cat "$MOCK_DIR/pulls.json" ;;
    *'/pulls/42') cat "$MOCK_DIR/pr.json" ;;
    *) exit 1 ;;
esac
MOCK
chmod +x "$fixture/bin/gh"
cat > "$fixture/expected.md" <<'NOTES'
## Changes

- 日本語の変更内容 and `code`.
- Literal: $(touch PWNED) and $GITHUB_ENV
NOTES
printf '\n\n' >> "$fixture/expected.md"
jq -n --rawfile body "$fixture/expected.md" '{body: $body}' > "$fixture/generated.json"
jq -n --rawfile body "$fixture/expected.md" '{
  number: 42, body: $body, merged_at: "2026-10-18T00:00:00Z", merge_commit_sha: "commit",
  base: {ref: "main", repo: {full_name: "owner/repo"}},
  head: {ref: "release/v0.2.0", repo: {full_name: "owner/repo"}}
}' > "$fixture/pr.json"
jq -s '.' "$fixture/pr.json" > "$fixture/pulls.json"

run_notes() {
    (cd "$fixture" && bash "$project_dir/scripts/release-notes.sh" "$@" v0.2.0 commit "$fixture/actual.md")
}

# Generated notes become the PR body without a wrapper or newline changes.
run_notes generate
cmp "$fixture/expected.md" "$fixture/actual.md"
# A matching merged PR is used for tag dispatches and manual retries.
run_notes resolve
cmp "$fixture/expected.md" "$fixture/actual.md"
[[ ! -e "$fixture/PWNED" ]]
# A PR merge event can identify the PR directly, with the same byte preservation.
bash "$project_dir/scripts/release-notes.sh" resolve v0.2.0 commit "$fixture/actual.md" 42
cmp "$fixture/expected.md" "$fixture/actual.md"

# Empty reviewed text and API failures must not silently regenerate notes.
jq '.body = " \n\t"' "$fixture/pr.json" > "$fixture/empty.json"
mv "$fixture/empty.json" "$fixture/pr.json"
if bash "$project_dir/scripts/release-notes.sh" resolve v0.2.0 commit "$fixture/actual.md" 42 >/dev/null 2>&1; then
    printf '%s\n' 'Unexpectedly accepted empty reviewed notes.' >&2
    exit 1
fi
if MOCK_FAIL=true run_notes resolve >/dev/null 2>&1; then
    printf '%s\n' 'Unexpectedly ignored an API failure.' >&2
    exit 1
fi
cmp "$fixture/expected.md" "$fixture/actual.md"

# No matching PR (including unrelated commits or forks) uses generated notes.
jq '.[0].merge_commit_sha = "other"' "$fixture/pulls.json" > "$fixture/unrelated.json"
mv "$fixture/unrelated.json" "$fixture/pulls.json"
printf '%s' '{"body":"Generated fallback"}' > "$fixture/generated.json"
run_notes resolve
[[ "$(cat "$fixture/actual.md")" == 'Generated fallback' ]]
printf '%s\n' 'Release note checks passed.'
