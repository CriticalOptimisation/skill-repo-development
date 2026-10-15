#!/usr/bin/env bats
# shellcheck disable=SC2154 # $stderr is set by bats run --separate-stderr, unknown to shellcheck
# Contract of tools/find-scm-skill.sh (#3): where is scm-skill?
#
# Run from a project, it prints the directory of the first scm-skill it finds
# (a skill whose SKILL.md has "name: scm-skill"), resolved:
#   1. a skill linked in the project's main worktree, .claude/skills/*;
#   2. a skill linked in the main worktree of this skill's own repository,
#      .claude/skills/*: the project links this skill, and this skill's
#      repository links scm-skill;
#   3. a clone next to the project, ../scm-skill.
# Found: exit 0, the directory on stdout. Not found: exit 1, the installation
# instructions on stderr. It changes nothing, so it can be run again.
#
# Each test makes, under $TMP, a throwaway scm-skill repository, a throwaway
# repository of this skill with a copy (a detached worktree, as scm-skill makes
# them) holding the script under test, and a throwaway project. The script is
# run from that copy, so that it never sees the links of the real repository.

bats_require_minimum_version 1.5.0

setup() {
  TMP="$(realpath "$(mktemp -d)")"
  WORK="$TMP/work"
  PROJ="$WORK/proj"
  SCM="$TMP/elsewhere/scm-skill-repo"
  THIS="$TMP/elsewhere/skill-repo-development"
  skill_repo "$SCM" scm-skill
  skill_repo "$THIS" skill-repo-development
  if [ -f "$BATS_TEST_DIRNAME/find-scm-skill.sh" ]; then
    cp -p "$BATS_TEST_DIRNAME/find-scm-skill.sh" "$THIS/tools/"
    git -C "$THIS" add tools
    git -C "$THIS" commit -qm script
  fi
  THISCOPY=$(copy_of "$THIS" proj)
  SCRIPT="$THISCOPY/tools/find-scm-skill.sh"
  git init -q -b main "$PROJ"
  cd "$PROJ" || return
}

teardown() {
  rm -rf "$TMP"
}

# skill_repo <dir> <name>: a skill repository whose SKILL.md is named <name>,
# with an executable tools/skill-copy.sh, and /.worktrees/ ignored.
skill_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config user.name test
  mkdir -p "$1/tools"
  printf '/.worktrees/\n' > "$1/.gitignore"
  printf -- '---\nname: %s\ndescription: test skill\n---\n' "$2" > "$1/SKILL.md"
  printf '#!/bin/sh\n' > "$1/tools/skill-copy.sh"
  chmod +x "$1/tools/skill-copy.sh"
  git -C "$1" add .gitignore SKILL.md tools
  git -C "$1" commit -qm init
}

# copy_of <repo> <label>: makes a copy of the repository's HEAD and prints it.
copy_of() {
  local copy
  copy="$1/.worktrees/skill-$(git -C "$1" rev-parse HEAD | cut -c1-12)-$2"
  git -C "$1" worktree add -q --detach "$copy" HEAD
  echo "$copy"
}

# link <dir> <link name> <target>: links <dir>/.claude/skills/<link name>.
link() {
  mkdir -p "$1/.claude/skills"
  ln -s "$3" "$1/.claude/skills/$2"
}

# Everything the script must leave unchanged.
snapshot() {
  (cd "$TMP" && find . -name .git -prune -o -print | sort)
}

@test "the script is shipped and executable" {
  [ -x "$BATS_TEST_DIRNAME/find-scm-skill.sh" ]
}

@test "scm-skill linked in the project comes first, whatever the name of its link" {
  P=$(copy_of "$SCM" proj)
  T=$(copy_of "$SCM" this)
  link "$PROJ" software-configuration-management "$P"
  link "$THIS" scm-skill "$T"
  skill_repo "$WORK/scm-skill" scm-skill
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [ "$output" = "$P" ]
}

@test "without scm-skill in the project, the scm-skill linked by this skill's own repository is found, the same at every run, and nothing changes" {
  T=$(copy_of "$SCM" this)
  link "$THIS" scm-skill "$T"
  link "$PROJ" skill-repo-development "$THISCOPY"
  skill_repo "$WORK/scm-skill" scm-skill
  before=$(snapshot)
  for _ in 1 2; do
    run --separate-stderr "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ -z "$stderr" ]]
    [ "$output" = "$T" ]
    [ "$(snapshot)" = "$before" ]
  done
}

@test "with no scm-skill linked, a clone next to the project is found" {
  skill_repo "$WORK/scm-skill" scm-skill
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [ "$output" = "$WORK/scm-skill" ]
}

@test "a linked skill or a clone whose SKILL.md is not named scm-skill is skipped" {
  T=$(copy_of "$SCM" this)
  link "$PROJ" scm-skill "$THISCOPY"
  link "$THIS" scm-skill "$T"
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [ "$output" = "$T" ]
  rm "$THIS/.claude/skills/scm-skill"
  skill_repo "$WORK/scm-skill" not-scm-skill
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"find-scm-skill: scm-skill not found"* ]]
  [ -z "$output" ]
}

@test "with no scm-skill found, the script exits 1 with the installation instructions and nothing on stdout" {
  before=$(snapshot)
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"find-scm-skill: scm-skill not found"* ]]
  [[ "$stderr" == *"git clone https://github.com/CriticalOptimisation/scm-skill.git ../scm-skill"* ]]
  [[ "$stderr" == *"../scm-skill/tools/skill-copy.sh use ../scm-skill origin/main"* ]]
  [ -z "$output" ]
  [ "$(snapshot)" = "$before" ]
}

# --- edge cases ------------------------------------------------------------

@test "an argument is a usage error" {
  run --separate-stderr "$SCRIPT" extra
  [ "$status" -eq 2 ]
  [ "$stderr" = "find-scm-skill: usage: find-scm-skill.sh" ]
  [ -z "$output" ]
}

@test "run from a branch worktree or a subdirectory of the project, it looks in the project's main worktree" {
  git -C "$PROJ" config user.email test@example.invalid
  git -C "$PROJ" config user.name test
  printf '/.worktrees/\n' > .gitignore
  git add .gitignore
  git commit -qm init
  git worktree add -q -b feature/9-x .worktrees/9-x
  mkdir sub
  P=$(copy_of "$SCM" proj)
  link "$PROJ" scm-skill "$P"
  for dir in "$PROJ/.worktrees/9-x" "$PROJ/sub"; do
    cd "$dir"
    run --separate-stderr "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ -z "$stderr" ]]
    [ "$output" = "$P" ]
  done
}

@test "a dangling link, or a scm-skill without an executable tools/skill-copy.sh, is skipped" {
  link "$PROJ" broken "$TMP/gone"
  mkdir -p "$TMP/no-tool"
  printf -- '---\nname: scm-skill\n---\n' > "$TMP/no-tool/SKILL.md"
  link "$PROJ" scm-skill "$TMP/no-tool"
  T=$(copy_of "$SCM" this)
  link "$THIS" scm-skill "$T"
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [ "$output" = "$T" ]
}

@test "outside a git repository, the current directory is the project" {
  mkdir "$WORK/plain"
  cd "$WORK/plain"
  skill_repo "$WORK/scm-skill" scm-skill
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [ "$output" = "$WORK/scm-skill" ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #3     | project, this skill's repository, clone next to the project   |
