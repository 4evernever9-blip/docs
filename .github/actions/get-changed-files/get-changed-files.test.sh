#!/usr/bin/env bash
# Tests for the pure functions defined in get-changed-files.sh.
#
# Run: bash .github/actions/get-changed-files/get-changed-files.test.sh
#
# The test harness re-defines the same functions from get-changed-files.sh so
# we can exercise their logic in isolation without touching git or GitHub Actions
# environment variables.

set -euo pipefail

# ---------------------------------------------------------------------------
# Minimal test harness
# ---------------------------------------------------------------------------

PASS=0
FAIL=0

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "    Expected: $(printf '%q' "$expected")"
    echo "    Actual:   $(printf '%q' "$actual")"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "    Expected to find: $(printf '%q' "$needle")"
    echo "    In:               $(printf '%q' "$haystack")"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "    Did not expect: $(printf '%q' "$needle")"
    echo "    In:             $(printf '%q' "$haystack")"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Re-define the pure functions from get-changed-files.sh
# (identical copies so the tests remain authoritative about the contract)
# ---------------------------------------------------------------------------

format_output() {
  local input=$1
  echo "$input" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//' | sed 's/ *$//'
}

create_rename_pairs() {
  local old_files=$1
  local new_files=$2
  local pairs=()
  local i=1
  local total
  total=$(echo "$old_files" | wc -l)

  IFS=$'\n'
  while [ "$i" -le "$total" ]; do
    OLD=$(echo "$old_files" | sed -n "${i}p")
    NEW=$(echo "$new_files" | sed -n "${i}p")
    pairs+=("$OLD=>$NEW")
    i=$((i + 1))
  done
  unset IFS

  printf "%s\n" "${pairs[@]}"
}

# filter_files uses FILTER from the outer scope
filter_files() {
  local files=$1
  local result=""

  IFS=$'\n'
  for file in $files; do
    while IFS= read -r pattern || [ -n "$pattern" ]; do
      clean_pattern=${pattern%/}
      if [[ $file == $clean_pattern || $file == $clean_pattern/* ]]; then
        result="$result $file"
        break
      fi
    done <<< "$FILTER"
  done
  unset IFS

  echo "$result"
}

# filter_renames uses FILTER from the outer scope
filter_renames() {
  local new_files=$1
  local old_files=$2
  local result=""
  local i=1
  local total
  total=$(echo "$new_files" | wc -l)

  IFS=$'\n'
  while [ "$i" -le "$total" ]; do
    NEW=$(echo "$new_files" | sed -n "${i}p")
    OLD=$(echo "$old_files" | sed -n "${i}p")

    while IFS= read -r pattern || [ -n "$pattern" ]; do
      clean_pattern=${pattern%/}
      if [[ $NEW == $clean_pattern || $NEW == $clean_pattern/* ]]; then
        result="$result $OLD=>$NEW"
        break
      fi
    done <<< "$FILTER"
    i=$((i + 1))
  done
  unset IFS

  echo "$result"
}

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

echo ""
echo "=== format_output ==="

assert_eq \
  "single file is returned as-is" \
  "content/foo.md" \
  "$(format_output "content/foo.md")"

assert_eq \
  "newline-separated files become space-separated" \
  "content/a.md content/b.md" \
  "$(format_output "$(printf 'content/a.md\ncontent/b.md')")"

assert_eq \
  "multiple consecutive spaces are collapsed" \
  "a b c" \
  "$(format_output "a  b   c")"

assert_eq \
  "leading whitespace is stripped" \
  "file.md" \
  "$(format_output "   file.md")"

assert_eq \
  "trailing whitespace is stripped" \
  "file.md" \
  "$(format_output "file.md   ")"

assert_eq \
  "empty string remains empty" \
  "" \
  "$(format_output "")"

assert_eq \
  "newline-only input becomes empty" \
  "" \
  "$(format_output "$(printf '\n')")"

assert_eq \
  "three files separated by newlines become space-separated" \
  "a/b.ts c/d.ts e/f.ts" \
  "$(format_output "$(printf 'a/b.ts\nc/d.ts\ne/f.ts')")"

# ---------------------------------------------------------------------------
# Tests: create_rename_pairs
# ---------------------------------------------------------------------------

echo ""
echo "=== create_rename_pairs ==="

OLD_FILES="$(printf 'old/foo.md')"
NEW_FILES="$(printf 'new/foo.md')"
PAIRS="$(create_rename_pairs "$OLD_FILES" "$NEW_FILES")"

assert_eq \
  "single rename produces old=>new pair" \
  "old/foo.md=>new/foo.md" \
  "$PAIRS"

OLD_FILES="$(printf 'old/a.md\nold/b.md')"
NEW_FILES="$(printf 'new/a.md\nnew/b.md')"
PAIRS="$(create_rename_pairs "$OLD_FILES" "$NEW_FILES")"

assert_contains \
  "two renames: first pair present" \
  "old/a.md=>new/a.md" \
  "$PAIRS"

assert_contains \
  "two renames: second pair present" \
  "old/b.md=>new/b.md" \
  "$PAIRS"

# ---------------------------------------------------------------------------
# Tests: filter_files
# ---------------------------------------------------------------------------

echo ""
echo "=== filter_files ==="

# Exact match
FILTER="content/foo.md"
RESULT="$(filter_files "$(printf 'content/foo.md\ndata/bar.json')")"
assert_contains "exact match: matching file included" "content/foo.md" "$RESULT"
assert_not_contains "exact match: non-matching file excluded" "data/bar.json" "$RESULT"

# Directory prefix match (trailing path separator stripping)
FILTER="content/"
RESULT="$(filter_files "$(printf 'content/foo.md\ncontent/bar/baz.md\ndata/other.json')")"
assert_contains "directory filter with trailing slash: file directly in dir included" "content/foo.md" "$RESULT"
assert_contains "directory filter with trailing slash: nested file included" "content/bar/baz.md" "$RESULT"
assert_not_contains "directory filter with trailing slash: sibling dir excluded" "data/other.json" "$RESULT"

# Directory prefix match without trailing slash
FILTER="content"
RESULT="$(filter_files "$(printf 'content/foo.md\ncontextual/other.md')")"
assert_contains "directory filter without trailing slash: direct child included" "content/foo.md" "$RESULT"
assert_not_contains "directory filter without trailing slash: file with longer matching prefix excluded" "contextual/other.md" "$RESULT"

# Multiple patterns (newline-separated)
FILTER="$(printf 'content\ndata')"
RESULT="$(filter_files "$(printf 'content/foo.md\ndata/bar.json\nsrc/app.ts')")"
assert_contains "multi-pattern: content file included" "content/foo.md" "$RESULT"
assert_contains "multi-pattern: data file included" "data/bar.json" "$RESULT"
assert_not_contains "multi-pattern: src file excluded" "src/app.ts" "$RESULT"

# Dot filter (default — match everything)
FILTER="."
RESULT="$(filter_files "$(printf 'content/foo.md\ndata/bar.json')")"
# When FILTER is ".", filter_files would try to match file == "." which is false
# and file starts with "./" which is also false for most paths → no matches.
# This is consistent with the script's behaviour: it only applies filtering when FILTER != "."
# The test demonstrates the known behaviour.
assert_not_contains "dot filter does not match arbitrary paths" "content/foo.md" "$RESULT"

# No match returns empty
FILTER="nonexistent"
RESULT="$(filter_files "content/foo.md")"
assert_eq "no matching pattern returns empty string" "" "$(echo "$RESULT" | tr -s ' ' | sed 's/^ //;s/ $//')"

# ---------------------------------------------------------------------------
# Tests: filter_renames
# ---------------------------------------------------------------------------

echo ""
echo "=== filter_renames ==="

FILTER="content"
NEW="$(printf 'content/new-name.md\ndata/other.json')"
OLD="$(printf 'content/old-name.md\ndata/old-other.json')"
RESULT="$(filter_renames "$NEW" "$OLD")"

assert_contains \
  "rename in matching dir: old=>new pair included" \
  "content/old-name.md=>content/new-name.md" \
  "$RESULT"

assert_not_contains \
  "rename in non-matching dir: pair excluded" \
  "data/old-other.json" \
  "$RESULT"

# Filter by new file, not old file
FILTER="dest"
NEW="$(printf 'dest/file.md')"
OLD="$(printf 'src/file.md')"
RESULT="$(filter_renames "$NEW" "$OLD")"

assert_contains \
  "rename filtered by new path (not old path)" \
  "src/file.md=>dest/file.md" \
  "$RESULT"

# Old file does NOT match, new file also doesn't match — should be excluded
FILTER="other"
NEW="$(printf 'dest/file.md')"
OLD="$(printf 'src/file.md')"
RESULT="$(filter_renames "$NEW" "$OLD")"
TRIMMED="$(echo "$RESULT" | tr -s ' ' | sed 's/^ //;s/ $//')"
assert_eq \
  "rename not matching filter is excluded entirely" \
  "" \
  "$TRIMMED"

# ---------------------------------------------------------------------------
# Tests: set_outputs
# ---------------------------------------------------------------------------

echo ""
echo "=== set_outputs ==="

TMP_FILE="$(mktemp)"

# HAS_CHANGES=false → all outputs empty
HAS_CHANGES=false
ALL_FORMATTED=""
FORMATTED_DIFF=""
FORMATTED_DELETED=""
FORMATTED_RENAMED=""
set_outputs "$TMP_FILE"
CONTENT="$(cat "$TMP_FILE")"

assert_contains "no-changes: all_changed_files empty assignment" "all_changed_files=" "$CONTENT"
assert_contains "no-changes: filtered_changed_files empty assignment" "filtered_changed_files=" "$CONTENT"
assert_contains "no-changes: filtered_deleted_files empty assignment" "filtered_deleted_files=" "$CONTENT"
assert_contains "no-changes: filtered_renamed_files empty assignment" "filtered_renamed_files=" "$CONTENT"
assert_not_contains "no-changes: no heredoc EOF markers written" "<<EOF" "$CONTENT"

# HAS_CHANGES=true → heredoc format
rm "$TMP_FILE"
TMP_FILE="$(mktemp)"
HAS_CHANGES=true
ALL_FORMATTED="content/a.md content/b.md"
FORMATTED_DIFF="content/a.md"
FORMATTED_DELETED="content/b.md"
FORMATTED_RENAMED="old.md=>new.md"
set_outputs "$TMP_FILE"
CONTENT="$(cat "$TMP_FILE")"

assert_contains "has-changes: all_changed_files heredoc opener" "all_changed_files<<EOF" "$CONTENT"
assert_contains "has-changes: ALL_FORMATTED value written" "content/a.md content/b.md" "$CONTENT"
assert_contains "has-changes: filtered_changed_files heredoc opener" "filtered_changed_files<<EOF" "$CONTENT"
assert_contains "has-changes: FORMATTED_DIFF value written" "content/a.md" "$CONTENT"
assert_contains "has-changes: filtered_deleted_files heredoc opener" "filtered_deleted_files<<EOF" "$CONTENT"
assert_contains "has-changes: FORMATTED_DELETED value written" "content/b.md" "$CONTENT"
assert_contains "has-changes: filtered_renamed_files heredoc opener" "filtered_renamed_files<<EOF" "$CONTENT"
assert_contains "has-changes: FORMATTED_RENAMED value written" "old.md=>new.md" "$CONTENT"
assert_contains "has-changes: EOF closing markers present" "EOF" "$CONTENT"

rm -f "$TMP_FILE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0