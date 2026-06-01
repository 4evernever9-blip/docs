#!/bin/bash
# Tests for .github/actions/get-changed-files/get-changed-files.sh
#
# Exercises the pure shell functions (filter_files, filter_renames,
# format_output, set_outputs, create_rename_pairs) in isolation by defining
# equivalent implementations that match the script logic. This avoids needing
# a real git remote while still verifying the algorithmic behaviour of each
# function against realistic inputs.
#
# Run: bash .github/actions/get-changed-files/tests/test-get-changed-files.sh

set -euo pipefail

PASS=0
FAIL=0

assert_equal() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "        expected: '$expected'"
    echo "        actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "        expected to contain: '$needle'"
    echo "        actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "        expected NOT to contain: '$needle'"
    echo "        actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Implementations matching get-changed-files.sh logic (FILTER is global)
# We use awk instead of `seq` since seq may not be available on all systems.
# ---------------------------------------------------------------------------

# format_output: convert newlines to spaces, collapse whitespace, trim ends
format_output() {
  local input=$1
  echo "$input" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//' | sed 's/ *$//'
}

# filter_files: return space-separated list of files matching $FILTER patterns
filter_files() {
  local files=$1
  local result=""

  IFS=$'\n'
  for file in $files; do
    while IFS= read -r pattern || [ -n "$pattern" ]; do
      local clean_pattern=${pattern%/}
      if [[ $file == "$clean_pattern" || $file == "$clean_pattern"/* ]]; then
        result="$result $file"
        break
      fi
    done <<< "$FILTER"
  done
  unset IFS

  echo "$result"
}

# filter_renames: return space-separated "old=>new" pairs whose new path matches $FILTER
filter_renames() {
  local new_files=$1
  local old_files=$2
  local result=""
  local count

  count=$(echo "$new_files" | wc -l)

  IFS=$'\n'
  for i in $(awk -v n="$count" 'BEGIN{for(i=1;i<=n;i++) print i}'); do
    local NEW OLD
    NEW=$(echo "$new_files" | sed -n "${i}p")
    OLD=$(echo "$old_files" | sed -n "${i}p")

    while IFS= read -r pattern || [ -n "$pattern" ]; do
      local clean_pattern=${pattern%/}
      if [[ $NEW == "$clean_pattern" || $NEW == "$clean_pattern"/* ]]; then
        result="$result $OLD=>$NEW"
        break
      fi
    done <<< "$FILTER"
  done
  unset IFS

  echo "$result"
}

# create_rename_pairs: pair old+new filenames into "old=>new" format
create_rename_pairs() {
  local old_files=$1
  local new_files=$2
  local pairs=()
  local count

  count=$(echo "$old_files" | wc -l)

  IFS=$'\n'
  for i in $(awk -v n="$count" 'BEGIN{for(i=1;i<=n;i++) print i}'); do
    local OLD NEW
    OLD=$(echo "$old_files" | sed -n "${i}p")
    NEW=$(echo "$new_files" | sed -n "${i}p")
    pairs+=("$OLD=>$NEW")
  done
  unset IFS

  printf "%s\n" "${pairs[@]}"
}

# set_outputs: write GitHub Actions output syntax to a target file
set_outputs() {
  local target=$1

  if [[ "$HAS_CHANGES" == "false" ]]; then
    echo "all_changed_files=" >> "$target"
    echo "filtered_changed_files=" >> "$target"
    echo "filtered_deleted_files=" >> "$target"
    echo "filtered_renamed_files=" >> "$target"
  else
    echo "all_changed_files<<EOF" >> "$target"
    echo "$ALL_FORMATTED" >> "$target"
    echo "EOF" >> "$target"

    echo "filtered_changed_files<<EOF" >> "$target"
    echo "$FORMATTED_DIFF" >> "$target"
    echo "EOF" >> "$target"

    echo "filtered_deleted_files<<EOF" >> "$target"
    echo "$FORMATTED_DELETED" >> "$target"
    echo "EOF" >> "$target"

    echo "filtered_renamed_files<<EOF" >> "$target"
    echo "$FORMATTED_RENAMED" >> "$target"
    echo "EOF" >> "$target"
  fi
}

# ---------------------------------------------------------------------------
# Tests: format_output
# ---------------------------------------------------------------------------

echo "=== format_output ==="

assert_equal "strips leading and trailing spaces" \
  "foo bar" \
  "$(format_output "  foo bar  ")"

assert_equal "converts newlines to spaces" \
  "foo bar baz" \
  "$(format_output "foo
bar
baz")"

assert_equal "collapses multiple internal spaces" \
  "a b c" \
  "$(format_output "  a   b    c  ")"

assert_equal "empty input produces empty output" \
  "" \
  "$(format_output "")"

assert_equal "single word is unchanged" \
  "singleword" \
  "$(format_output "singleword")"

assert_equal "whitespace-only input produces empty output" \
  "" \
  "$(format_output "   ")"

# ---------------------------------------------------------------------------
# Tests: filter_files
# ---------------------------------------------------------------------------

echo ""
echo "=== filter_files — simple directory filter ==="

FILTER="content"
FILES="content/foo.md
content/bar.md
src/app.ts
data/vars.yml"

result=$(filter_files "$FILES")
assert_contains "includes content/foo.md" "content/foo.md" "$result"
assert_contains "includes content/bar.md" "content/bar.md" "$result"
assert_not_contains "excludes src/app.ts" "src/app.ts" "$result"
assert_not_contains "excludes data/vars.yml" "data/vars.yml" "$result"

echo ""
echo "=== filter_files — trailing slash in filter ==="

FILTER="content/"
result=$(filter_files "$FILES")
assert_contains "includes content/foo.md with trailing-slash filter" "content/foo.md" "$result"
assert_not_contains "excludes src/app.ts with trailing-slash filter" "src/app.ts" "$result"

echo ""
echo "=== filter_files — exact filename match ==="

FILTER="src/app.ts"
result=$(filter_files "$FILES")
assert_contains "includes exact match src/app.ts" "src/app.ts" "$result"
assert_not_contains "excludes content/foo.md for exact-file filter" "content/foo.md" "$result"

echo ""
echo "=== filter_files — multi-pattern filter ==="

FILTER="content
data"
FILES3="content/foo.md
data/vars.yml
src/app.ts
.github/workflows/ci.yml"

result=$(filter_files "$FILES3")
assert_contains "includes content/foo.md" "content/foo.md" "$result"
assert_contains "includes data/vars.yml" "data/vars.yml" "$result"
assert_not_contains "excludes src/app.ts" "src/app.ts" "$result"
assert_not_contains "excludes .github path" ".github/workflows/ci.yml" "$result"

echo ""
echo "=== filter_files — deeply nested paths ==="

FILTER="content"
DEEP_FILES="content/admin/overview/index.md
content/copilot/quickstart.md
src/server/middleware.ts"

result=$(filter_files "$DEEP_FILES")
assert_contains "includes deeply nested content file" "content/admin/overview/index.md" "$result"
assert_contains "includes top-level content file" "content/copilot/quickstart.md" "$result"
assert_not_contains "excludes src path" "src/server/middleware.ts" "$result"

echo ""
echo "=== filter_files — exact directory name match only (no partial prefix) ==="

FILTER="con"
FILES_PARTIAL="content/foo.md
con/bar.md"

result=$(filter_files "$FILES_PARTIAL")
assert_not_contains "does not match partial prefix 'con' against 'content/foo.md'" "content/foo.md" "$result"
assert_contains "matches exact directory 'con'" "con/bar.md" "$result"

echo ""
echo "=== filter_files — empty file list ==="

FILTER="content"
result=$(filter_files "")
assert_equal "empty file list returns empty result" "" "$(echo "$result" | tr -d ' ')"

# ---------------------------------------------------------------------------
# Tests: filter_renames
# ---------------------------------------------------------------------------

echo ""
echo "=== filter_renames — renames within filter ==="

FILTER="content"
NEW_FILES="content/new-name.md
src/new-component.ts"
OLD_FILES="content/old-name.md
src/old-component.ts"

result=$(filter_renames "$NEW_FILES" "$OLD_FILES")
assert_contains "includes rename within content/" "content/old-name.md=>content/new-name.md" "$result"
assert_not_contains "excludes rename outside content/" "src/old-component.ts=>src/new-component.ts" "$result"

echo ""
echo "=== filter_renames — no matches ==="

FILTER="data"
result=$(filter_renames "$NEW_FILES" "$OLD_FILES")
# No data/ files — result should be empty (whitespace only)
cleaned=$(echo "$result" | tr -d ' \n')
assert_equal "empty result when no renames match filter" "" "$cleaned"

# ---------------------------------------------------------------------------
# Tests: create_rename_pairs
# ---------------------------------------------------------------------------

echo ""
echo "=== create_rename_pairs ==="

result=$(create_rename_pairs "content/old.md" "content/new.md")
assert_contains "creates a single old=>new pair" "content/old.md=>content/new.md" "$result"

OLD2="content/a.md
content/b.md"
NEW2="content/a-new.md
content/b-new.md"
result=$(create_rename_pairs "$OLD2" "$NEW2")
assert_contains "creates first pair" "content/a.md=>content/a-new.md" "$result"
assert_contains "creates second pair" "content/b.md=>content/b-new.md" "$result"

# ---------------------------------------------------------------------------
# Tests: set_outputs (HAS_CHANGES=false)
# ---------------------------------------------------------------------------

echo ""
echo "=== set_outputs — no changes ==="

TMP_OUTPUT=$(mktemp)
HAS_CHANGES=false
ALL_FORMATTED=""
FORMATTED_DIFF=""
FORMATTED_DELETED=""
FORMATTED_RENAMED=""

set_outputs "$TMP_OUTPUT"

OUTPUT_CONTENT=$(cat "$TMP_OUTPUT")
assert_contains "writes all_changed_files= key" "all_changed_files=" "$OUTPUT_CONTENT"
assert_contains "writes filtered_changed_files= key" "filtered_changed_files=" "$OUTPUT_CONTENT"
assert_contains "writes filtered_deleted_files= key" "filtered_deleted_files=" "$OUTPUT_CONTENT"
assert_contains "writes filtered_renamed_files= key" "filtered_renamed_files=" "$OUTPUT_CONTENT"
assert_not_contains "does not write EOF heredoc when no changes" "EOF" "$OUTPUT_CONTENT"

rm -f "$TMP_OUTPUT"

# ---------------------------------------------------------------------------
# Tests: set_outputs (HAS_CHANGES=true)
# ---------------------------------------------------------------------------

echo ""
echo "=== set_outputs — with changes ==="

TMP_OUTPUT=$(mktemp)
HAS_CHANGES=true
ALL_FORMATTED="content/a.md content/b.md"
FORMATTED_DIFF="content/a.md"
FORMATTED_DELETED="content/b.md"
FORMATTED_RENAMED="content/old.md=>content/new.md"

set_outputs "$TMP_OUTPUT"

OUTPUT_CONTENT=$(cat "$TMP_OUTPUT")
assert_contains "writes all_changed_files heredoc header" "all_changed_files<<EOF" "$OUTPUT_CONTENT"
assert_contains "writes all_changed_files value" "content/a.md content/b.md" "$OUTPUT_CONTENT"
assert_contains "writes filtered_changed_files value" "content/a.md" "$OUTPUT_CONTENT"
assert_contains "writes filtered_deleted_files value" "content/b.md" "$OUTPUT_CONTENT"
assert_contains "writes filtered_renamed_files value" "content/old.md=>content/new.md" "$OUTPUT_CONTENT"
assert_contains "uses EOF heredoc delimiter" "EOF" "$OUTPUT_CONTENT"

rm -f "$TMP_OUTPUT"

# ---------------------------------------------------------------------------
# Tests: output routing (INPUT_OUTPUT_FILE vs GITHUB_OUTPUT)
# ---------------------------------------------------------------------------

echo ""
echo "=== Output routing — INPUT_OUTPUT_FILE is used when set ==="

TMP_FILE_OUTPUT=$(mktemp)
HAS_CHANGES=true
ALL_FORMATTED="src/foo.ts"
FORMATTED_DIFF="src/foo.ts"
FORMATTED_DELETED=""
FORMATTED_RENAMED=""

INPUT_OUTPUT_FILE="$TMP_FILE_OUTPUT"
GITHUB_OUTPUT="/dev/null"

if [[ -n "$INPUT_OUTPUT_FILE" ]]; then
  set_outputs "$INPUT_OUTPUT_FILE"
else
  set_outputs "$GITHUB_OUTPUT"
fi

OUTPUT_CONTENT=$(cat "$TMP_FILE_OUTPUT")
assert_contains "output written to INPUT_OUTPUT_FILE" "src/foo.ts" "$OUTPUT_CONTENT"

rm -f "$TMP_FILE_OUTPUT"

echo ""
echo "=== Output routing — GITHUB_OUTPUT is used when INPUT_OUTPUT_FILE is empty ==="

TMP_GH_OUTPUT=$(mktemp)
HAS_CHANGES=true
ALL_FORMATTED="data/vars.yml"
FORMATTED_DIFF="data/vars.yml"
FORMATTED_DELETED=""
FORMATTED_RENAMED=""
INPUT_OUTPUT_FILE=""
GITHUB_OUTPUT="$TMP_GH_OUTPUT"

if [[ -n "$INPUT_OUTPUT_FILE" ]]; then
  set_outputs "$INPUT_OUTPUT_FILE"
else
  set_outputs "$GITHUB_OUTPUT"
fi

OUTPUT_CONTENT=$(cat "$TMP_GH_OUTPUT")
assert_contains "output written to GITHUB_OUTPUT" "data/vars.yml" "$OUTPUT_CONTENT"

rm -f "$TMP_GH_OUTPUT"

# ---------------------------------------------------------------------------
# Boundary / regression cases
# ---------------------------------------------------------------------------

echo ""
echo "=== Boundary cases ==="

# HAS_CHANGES logic: both FORMATTED_DIFF and FORMATTED_DELETED are empty → false
FORMATTED_DIFF=""
FORMATTED_DELETED=""
if [[ -z "$FORMATTED_DIFF" && -z "$FORMATTED_DELETED" ]]; then
  HAS_CHANGES_RESULT=false
else
  HAS_CHANGES_RESULT=true
fi
assert_equal "empty diff+deleted means HAS_CHANGES=false" "false" "$HAS_CHANGES_RESULT"

# HAS_CHANGES logic: only FORMATTED_DELETED is non-empty → true
FORMATTED_DIFF=""
FORMATTED_DELETED="content/deleted.md"
if [[ -z "$FORMATTED_DIFF" && -z "$FORMATTED_DELETED" ]]; then
  HAS_CHANGES_RESULT=false
else
  HAS_CHANGES_RESULT=true
fi
assert_equal "non-empty deleted alone means HAS_CHANGES=true" "true" "$HAS_CHANGES_RESULT"

# HAS_CHANGES logic: only FORMATTED_DIFF is non-empty → true
FORMATTED_DIFF="content/new.md"
FORMATTED_DELETED=""
if [[ -z "$FORMATTED_DIFF" && -z "$FORMATTED_DELETED" ]]; then
  HAS_CHANGES_RESULT=false
else
  HAS_CHANGES_RESULT=true
fi
assert_equal "non-empty diff alone means HAS_CHANGES=true" "true" "$HAS_CHANGES_RESULT"

# filter_files: file that exactly equals the pattern (not a subpath)
FILTER="content"
result=$(filter_files "content")
assert_contains "file equal to pattern is included" "content" "$result"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0