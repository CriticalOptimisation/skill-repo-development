#!/usr/bin/env bats
# Structural tests for SKILL.md and README.md content (#1, #3).

bats_require_minimum_version 1.5.0

setup() {
  SKILL_MD="$BATS_TEST_DIRNAME/../SKILL.md"
  README="$BATS_TEST_DIRNAME/../README.md"
}

# Prints the frontmatter of SKILL.md: the lines between the first two "---".
frontmatter() {
  awk '/^---[[:space:]]*$/ { n++; next } n == 1' "$SKILL_MD"
}

# Prints the body of the "## Paths" section.
paths_section() {
  awk '/^## / { p = ($0 == "## Paths") ; next } p' "$SKILL_MD"
}

@test "frontmatter names the skill skill-repo-development" {
  run --separate-stderr frontmatter
  [[ -z "$stderr" ]]
  [[ "$output" == *"name: skill-repo-development"* ]]
}

@test "frontmatter has a description that triggers on skill-repository work" {
  run --separate-stderr frontmatter
  [[ -z "$stderr" ]]
  [[ "$output" == *"description: "*"whose source is a git repository"* ]]
}

@test "Paths tells sessions to resolve the base directory with readlink -f" {
  run --separate-stderr paths_section
  [[ -z "$stderr" ]]
  [[ "$output" == *"readlink -f"* ]]
}

# REVIEW PLACEHOLDER: SKILL.md calls the command through the skill's own directory -> SKILL.md calls scm-skill's command, with the edited skill's repository as <skill repo>
# @test "SKILL.md calls the command through the skill's own directory" {
#   run --separate-stderr grep -cF '<skill>/tools/skill-copy.sh' "$SKILL_MD"
#   [[ -z "$stderr" ]]
#   [[ "$output" -ge 1 ]]
# }
@test "SKILL.md calls scm-skill's command, with the edited skill's repository as <skill repo>" {
  run --separate-stderr grep -cF '<scm-skill>/tools/skill-copy.sh use . ' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -ge 1 ]]
}

@test "SKILL.md refuses to run without scm-skill" {
  run --separate-stderr grep -ciF 'refuse to run without scm-skill' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -ge 1 ]]
}

@test "SKILL.md finds scm-skill for its refusal with <skill>/tools/find-scm-skill.sh" {
  run --separate-stderr grep -cF '<skill>/tools/find-scm-skill.sh' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -ge 1 ]]
}

@test "SKILL.md and README.md say that using this skill's skill-copy.sh is optional" {
  for f in "$SKILL_MD" "$README"; do
    run --separate-stderr grep -ciE 'skill-copy\.sh.*optional|optional.*skill-copy\.sh' "$f"
    [[ -z "$stderr" ]]
    [[ "$output" -ge 1 ]]
  done
}

@test "README.md installs the skill with skill-copy.sh use, never with ln -s" {
  run --separate-stderr grep -cF 'skill-copy.sh use ' "$README"
  [[ -z "$stderr" ]]
  [[ "$output" -ge 1 ]]
  run --separate-stderr grep -cF 'ln -s' "$README"
  [[ -z "$stderr" ]]
  [ "$output" -eq 0 ]
}

@test "the skill ships with its companions" {
  # The new-library checklist: command, its tests, reference documentation,
  # change history.
  for f in tools/skill-copy.sh tools/skill-copy.bats README.md history.md; do
    [ -f "$BATS_TEST_DIRNAME/../$f" ]
  done
  [ -x "$BATS_TEST_DIRNAME/skill-copy.sh" ]
}

@test "README.md installs from a local path, never from a URL" {
  run --separate-stderr grep -cE 'skill-copy\.sh use [^ ]*(://|@)' "$README"
  [[ -z "$stderr" ]]
  [ "$output" -eq 0 ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #2     | name, description, Paths, command path, companions (#1)       |
# | #3     | scm-skill's command, dependency, finder, wrapper, local paths |
