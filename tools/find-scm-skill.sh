#!/usr/bin/env bash
# Where is scm-skill on this machine? (#3)
#
# Run from a project, prints the resolved directory of the first skill named
# scm-skill (the name: field of its SKILL.md, whatever its link is called):
#   1. linked under .claude/skills/ of the project's main worktree;
#   2. linked under .claude/skills/ of the main worktree of this skill's own
#      repository;
#   3. a clone ../scm-skill next to the project.
# Contract: README.md, "Finding scm-skill".
#
# Exit codes: 0 found; 1 not found, with the installation instructions on
# stderr; 2 usage. Changes nothing.
set -uo pipefail

say() { printf 'find-scm-skill: %s\n' "$*" >&2; }

(( $# == 0 )) || { say "usage: find-scm-skill.sh"; exit 2; }

# main_of <dir>: the main worktree of the repository at <dir>.
main_of() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$(realpath "$common")"
}

# True if <dir> is scm-skill: its SKILL.md is named scm-skill, and it has its
# tool.
is_scm_skill() {
  [[ -x $1/tools/skill-copy.sh ]] &&
    awk '/^---[[:space:]]*$/ { n++; next }
         n == 1 && /^name:/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); found = ($0 == "scm-skill"); exit }
         END { exit !found }' "$1/SKILL.md" 2>/dev/null
}

project=$(main_of .) || project=$(pwd -P)
here=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
this=$(main_of "$here") || this=$here

for dir in "$project" "$this"; do
  for link in "$dir"/.claude/skills/*; do
    target=$(realpath -e -- "$link" 2>/dev/null) || continue
    is_scm_skill "$target" && { echo "$target"; exit 0; }
  done
done
target=$(realpath -m -- "$project/../scm-skill")
is_scm_skill "$target" && { echo "$target"; exit 0; }

say "scm-skill not found: no skill named scm-skill linked in $project/.claude/skills or $this/.claude/skills, and no clone at $target"
say "install it, from the main worktree of the project:"
say "  git clone https://github.com/CriticalOptimisation/scm-skill.git ../scm-skill"
say "  ../scm-skill/tools/skill-copy.sh use ../scm-skill origin/main"
exit 1

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #?     | project, this skill's repository, clone next to the project (#3) |
