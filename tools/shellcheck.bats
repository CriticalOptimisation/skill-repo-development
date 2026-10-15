#!/usr/bin/env bats
# Structural test: the scripts and tests of tools/ are shellcheck-clean (#3).
#
# Skipped when shellcheck is not installed. No .shellcheckrc and no blanket
# disable: a directive in a script must carry its reason.

bats_require_minimum_version 1.5.0

setup() {
  command -v shellcheck > /dev/null || skip "shellcheck is not installed"
}

# check <file>...: runs shellcheck; its findings are the output of the test.
check() { shellcheck "$@"; }

@test "tools/*.sh and tools/*.bats are shellcheck-clean" {
  run check "$BATS_TEST_DIRNAME"/*.sh "$BATS_TEST_DIRNAME"/*.bats
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "a planted finding is reported" {
  planted="$BATS_TEST_TMPDIR/planted.sh"
  cat > "$planted" << 'EOF'
#!/usr/bin/env bash
[ $x = 1 ]
EOF
  run check "$planted"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2086* ]]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #5     | tools/ is shellcheck-clean, with a planted-finding check (#3) |
