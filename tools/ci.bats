#!/usr/bin/env bats
# shellcheck disable=SC2154 # $stderr is set by bats run --separate-stderr, unknown to shellcheck
# Structural tests of the CI workflow, .github/workflows/ci.yml, and of the
# README.md entry that names its check (#4).
#
# The workflow is read line by line with awk and grep: no YAML parser, so CI
# needs nothing beyond bats and shellcheck. ci.yml is therefore kept in block
# style, one key per line, indented by two spaces per level; top-level keys
# start in column 1.

bats_require_minimum_version 1.5.0

setup() {
  CI="$BATS_TEST_DIRNAME/../.github/workflows/ci.yml"
  README="$BATS_TEST_DIRNAME/../README.md"
}

# section <key>: prints the body of the top-level block <key>: of ci.yml,
# without blank lines and comment lines. Fails if ci.yml is missing.
section() {
  [ -f "$CI" ] || { echo "no $CI" >&2; return 1; }
  awk -v k="$1:" '
    /^[^ #]/ { p = ($1 == k); next }
    p && !/^[[:space:]]*(#|$)/' "$CI"
}

# keys <indent> <key>: prints the keys found at <indent> spaces in the
# top-level block <key>:, one per line, without the colon.
keys() {
  section "$2" | awk -v n="$1" '
    match($0, /^ */) && RLENGTH == n && /^ *[A-Za-z0-9_-]+:/ {
      sub(/^ */, ""); sub(/:.*/, ""); print }'
}

# unpinned <file>: prints how many uses: lines of <file> are not pinned to a
# full commit SHA followed by a "# v..." comment.
unpinned() {
  grep -E '^[ -]*uses:' "$1" |
    grep -vcE '^[ -]*uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v[0-9]'
}

# guard: prints the script of the step "No skipped test" of ci.yml, unindented.
guard() {
  awk '
    /^ *- name: No skipped test$/ { s = 1; next }
    s && /^ *run: \|$/ { r = 1; next }
    r && (/^ *- / || /^[^ ]/) { exit }
    r { sub(/^          /, ""); print }' "$CI"
}

# skip_guard <tap>: runs the guard of ci.yml, as the workflow does (bash -eo
# pipefail), on the TAP output <tap>.
skip_guard() {
  local dir
  dir="$(mktemp -d "$BATS_TEST_TMPDIR/runner.XXXXXX")"
  cp "$1" "$dir/bats.tap"
  RUNNER_TEMP="$dir" bash -eo pipefail -c "$(guard)"
}

# tap_of <file.bats>: runs bats on <file.bats>; its TAP output goes to
# $BATS_TEST_TMPDIR/out.tap.
tap_of() {
  bats --tap "$1" > "$BATS_TEST_TMPDIR/out.tap" || true
}

@test "the workflow file exists" {
  [ -f "$CI" ]
}

@test "it runs on pull requests, on pushes to main, and by hand" {
  run --separate-stderr keys 2 on
  [[ -z "$stderr" ]]
  [ "$output" = $'pull_request\npush\nworkflow_dispatch' ]
  run --separate-stderr section on
  [[ -z "$stderr" ]]
  [[ "$output" == *$'  push:\n    branches: [main]'* ]]
}

@test "its permissions are exactly contents: read, and no job overrides them" {
  run --separate-stderr section permissions
  [[ -z "$stderr" ]]
  [ "$output" = "  contents: read" ]
  run --separate-stderr section jobs
  [[ -z "$stderr" ]]
  [ -n "$output" ]
  [[ "$output" != *"permissions:"* ]]
}

@test "every action is pinned to a full commit SHA, with its version in a comment" {
  [ -f "$CI" ]
  run grep -cE '^[ -]*uses:' "$CI"
  [ "$output" -ge 1 ]
  grep -E '^[ -]*uses:' "$CI" # shown when the test fails
  run unpinned "$CI"
  [ "$output" -eq 0 ]
}

@test "it has one job, bats, named bats, on ubuntu-24.04" {
  run --separate-stderr keys 2 jobs
  [[ -z "$stderr" ]]
  [ "$output" = "bats" ]
  run --separate-stderr section jobs
  [[ -z "$stderr" ]]
  [[ "$output" == *$'\n    name: bats\n'* ]]
  [[ "$output" == *$'\n    runs-on: ubuntu-24.04\n'* ]]
}

@test "its run steps use bash, so that a pipe keeps the failure of bats" {
  run --separate-stderr section defaults
  [[ -z "$stderr" ]]
  [[ "$output" == *$'  run:\n    shell: bash'* ]]
}

@test "it installs bats and shellcheck and fails if either is missing" {
  run --separate-stderr section jobs
  [[ -z "$stderr" ]]
  [[ "$output" == *"apt-get install"*" bats shellcheck"* ]]
  [[ "$output" == *"bats --version && shellcheck --version"* ]]
}

@test "it runs bats tools/ with TAP output, and fails on a skipped test" {
  run --separate-stderr section jobs
  [[ -z "$stderr" ]]
  # shellcheck disable=SC2016 # $RUNNER_TEMP is literal text of ci.yml
  [[ "$output" == *'bats --tap tools/ | tee "$RUNNER_TEMP/bats.tap"'* ]]
  [[ "$output" == *"grep -E '^ok [0-9]+ .* # skip' \"\$RUNNER_TEMP/bats.tap\""* ]]
  [[ "$output" == *"exit 1"* ]]
}

# shellcheck disable=SC2016 # the backquotes are literal Markdown of README.md
@test "README.md names the workflow CI and its check bats, and how to require it" {
  run --separate-stderr grep -F 'The workflow `CI` (`.github/workflows/ci.yml`)' "$README"
  [[ -z "$stderr" ]]
  [ "$status" -eq 0 ]
  run --separate-stderr grep -F 'its check, is named **`bats`**' "$README"
  [[ -z "$stderr" ]]
  [ "$status" -eq 0 ]
  run --separate-stderr grep -F 'Require status checks to pass' "$README"
  [[ -z "$stderr" ]]
  [ "$status" -eq 0 ]
}

# --- Edge cases -----------------------------------------------------------

@test "the skip guard is read from ci.yml whole: three lines, starting with the grep" {
  run --separate-stderr guard
  [[ -z "$stderr" ]]
  [[ "${lines[0]}" == "if grep -E '^ok [0-9]+ .* # skip'"* ]]
  [ "${#lines[@]}" -eq 3 ]
}

@test "the skip guard fails on a test that bats skipped, with or without a reason" {
  printf '%s\n' '@test "runs" { true; }' \
    '@test "skipped with a reason" { skip "shellcheck is not installed"; }' \
    '@test "skipped without one" { skip; }' > "$BATS_TEST_TMPDIR/s.bats"
  tap_of "$BATS_TEST_TMPDIR/s.bats"
  run --separate-stderr skip_guard "$BATS_TEST_TMPDIR/out.tap"
  [[ -z "$stderr" ]]
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok 2 skipped with a reason # skip shellcheck is not installed"* ]]
  [[ "$output" == *"ok 3 skipped without one # skip"* ]]
  [[ "$output" == *"::error::a test was skipped in CI"* ]]
}

@test "the skip guard passes a run without skips, even when a test name says skipped" {
  printf '%s\n' '@test "a dangling link is skipped" { true; }' \
    '@test "runs" { true; }' > "$BATS_TEST_TMPDIR/n.bats"
  tap_of "$BATS_TEST_TMPDIR/n.bats"
  grep -q '^ok 1 a dangling link is skipped$' "$BATS_TEST_TMPDIR/out.tap"
  run --separate-stderr skip_guard "$BATS_TEST_TMPDIR/out.tap"
  [[ -z "$stderr" ]]
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the pinning check rejects a tag, a branch, a short SHA and a SHA without its version" {
  sample="$BATS_TEST_TMPDIR/pins.yml"
  printf '      - uses: actions/checkout@%s\n' 'v7.0.1' 'main' '3d3c42e # v7.0.1' \
    '3d3c42e5aac5ba805825da76410c181273ba90b1' > "$sample"
  run --separate-stderr unpinned "$sample"
  [[ -z "$stderr" ]]
  [ "$output" -eq 4 ]
  printf '      - uses: actions/checkout@%s\n' \
    '3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' > "$sample"
  run --separate-stderr unpinned "$sample"
  [[ -z "$stderr" ]]
  [ "$output" -eq 0 ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #6     | workflow structure, skip guard, pinning, README entry (#4)    |
