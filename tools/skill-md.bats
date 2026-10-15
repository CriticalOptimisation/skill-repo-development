#!/usr/bin/env bats
# Structural tests for SKILL.md content (#1).

bats_require_minimum_version 1.5.0

setup() {
  SKILL_MD="$BATS_TEST_DIRNAME/../SKILL.md"
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

@test "SKILL.md calls the command through the skill's own directory" {
  run --separate-stderr grep -cF '<skill>/tools/skill-copy.sh' "$SKILL_MD"
  [[ -z "$stderr" ]]
  [[ "$output" -ge 1 ]]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
