# shellcheck shell=bash
# The skill-copy hook of this skill (#3), sourced by scm-skill's
# tools/skill-copy.sh on every use, in a subshell, from the project root:
# $1 is the copy's directory, $2 the project's.
#
# Refuses a copy that contains .claude or .worktrees, anywhere, as a
# directory, a file or a link, dangling or not: tools that follow links
# (find -L, grep -R, diff -r) would loop. A non-zero status makes use exit 1
# with the links unmoved. Silent and changes nothing otherwise.
# Contract: README.md, "The skill-copy hook".

skill_repo_development_hook() {
  local copy=$1 path rc=0
  if [[ ! -d $copy ]]; then
    printf 'skill-copy-hook: no copy at %s\n' "$copy" >&2
    return 1
  fi
  while IFS= read -r -d '' path; do
    printf 'skill-copy-hook: refused: %s is in the copy; tools that follow links would loop\n' "$path" >&2
    rc=1
  done < <(find "$copy" \( -name .claude -o -name .worktrees \) -print0 -prune)
  return "$rc"
}

skill_repo_development_hook "$@"

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #5     | refuses .claude and .worktrees in the copy (#3)               |
