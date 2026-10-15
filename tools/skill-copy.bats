#!/usr/bin/env bats
# Contract of tools/skill-copy.sh (#1).
#
# Each test sets up a throwaway skill repository with its bare remote: nothing
# touches the real repository. Session start times and the clock are faked with
# SKILL_COPY_STARTS and SKILL_COPY_NOW, so no test depends on the claude
# processes running on the machine.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/skill-copy.sh"
  TMP="$(mktemp -d)"
  ORIGIN="$TMP/origin.git"
  MAIN="$TMP/main"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$MAIN"
  cd "$MAIN"
  git config user.email test@example.invalid
  git config user.name test
  printf '/.worktrees/\n' > .gitignore
  skill_md demo-skill A
  git add .gitignore SKILL.md
  git commit -qm A
  A=$(sha12 HEAD)
  skill_md demo-skill B
  git commit -qam B
  B=$(sha12 HEAD)
  skill_md demo-skill C
  git commit -qam C
  C=$(sha12 HEAD)
  git remote add origin "$ORIGIN"
  git push -q -u origin main
  # A session started at 0 keeps every copy, unless a test says otherwise.
  export SKILL_COPY_STARTS=0
  export SKILL_COPY_NOW=1000
}

teardown() {
  rm -rf "$TMP"
}

# skill_md <name> <body>: writes a SKILL.md; an empty name means no name: field.
skill_md() {
  {
    echo ---
    [ -n "$1" ] && echo "name: $1"
    echo "description: test skill"
    echo ---
    echo "$2"
  } > SKILL.md
}

sha12() {
  git rev-parse "$1" | cut -c1-12
}

# Everything a refused command must leave unchanged.
snapshot() {
  find . -path ./.git -prune -o -print | sort
  cat .git/info/exclude 2>/dev/null
  git worktree list --porcelain
}

# --- general contract ------------------------------------------------------
#
# Exit codes: 0 success; 1 git error; 2 usage; 3 refused for safety.
# Refusals are tested on code 3, so that a missing script — which exits with
# 127 — can never pass them.

@test "the script exists and is executable" {
  [ -x "$SCRIPT" ]
}

# --- use -------------------------------------------------------------------

@test "use creates the copy, links it relatively, excludes the link and logs the move" {
  run --separate-stderr "$SCRIPT" use "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ -d ".worktrees/skill-$A" ]
  [ "$(git -C ".worktrees/skill-$A" rev-parse HEAD | cut -c1-12)" = "$A" ]
  [ -z "$(git -C ".worktrees/skill-$A" branch --show-current)" ]
  [ -L .claude/skills/demo-skill ]
  [ "$(readlink .claude/skills/demo-skill)" = "../../.worktrees/skill-$A" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$(readlink -f ".worktrees/skill-$A")" ]
  grep -qxF /.claude/skills/demo-skill .git/info/exclude
  [ "$(cat .worktrees/skill-copies.log)" = "1000 skill-$A" ]
  [ -z "$(git status --porcelain)" ]
}

@test "use accepts a remote branch name" {
  run --separate-stderr "$SCRIPT" use origin/main
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C (origin/main)"* ]]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$(readlink -f ".worktrees/skill-$C")" ]
}

@test "use run twice with the same ref changes nothing and logs nothing" {
  "$SCRIPT" use "$A" 2>/dev/null
  before=$(snapshot; cat .worktrees/skill-copies.log)
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$A"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
  [ "$(snapshot; cat .worktrees/skill-copies.log)" = "$before" ]
}

@test "use moves the link and keeps the previous copy fixed" {
  "$SCRIPT" use "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$B"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B ($B)"* ]]
  [ "$(readlink .claude/skills/demo-skill)" = "../../.worktrees/skill-$B" ]
  [ "$(tail -n 1 ".worktrees/skill-$A/SKILL.md")" = A ]
  [ "$(printf '1000 skill-%s\n2000 skill-%s' "$A" "$B")" = "$(cat .worktrees/skill-copies.log)" ]
}

@test "use links .claude/agents when the copy has agents/" {
  mkdir agents
  echo agent > agents/a.md
  git add agents
  git commit -qm agents
  D=$(sha12 HEAD)
  run --separate-stderr "$SCRIPT" use "$D"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$D ($D)"* ]]
  [ -L .claude/agents ]
  [ "$(readlink .claude/agents)" = "../.worktrees/skill-$D/agents" ]
  [ -f .claude/agents/a.md ]
  grep -qxF /.claude/agents .git/info/exclude
}

@test "after use, find -L terminates" {
  "$SCRIPT" use "$A" 2>/dev/null
  run --separate-stderr timeout 10 find -L . -name SKILL.md
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [[ "$output" == *"./.claude/skills/demo-skill/SKILL.md"* ]]
}

# --- pruning ---------------------------------------------------------------
#
# A copies: A current from 1000 to 2000, B from 2000 to 3000, C from 3000 on.
# A copy that is not current is removed if it stopped being current earlier
# than the oldest session start minus the margin (120 s by default).

use_a_b_c() {
  SKILL_COPY_NOW=1000 "$SCRIPT" use "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 "$SCRIPT" use "$B" 2>/dev/null
  SKILL_COPY_NOW=3000 "$SCRIPT" use "$C" 2>/dev/null
}

@test "prune removes the copies that ended before the oldest session, minus the margin" {
  use_a_b_c
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3500 3050" run --separate-stderr "$SCRIPT" prune
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
  [[ "$stderr" != *"removed skill-$B"* ]]
  [ ! -e ".worktrees/skill-$A" ]
  [ -d ".worktrees/skill-$B" ]
  [ -d ".worktrees/skill-$C" ]
  [[ "$(git worktree list)" != *"skill-$A"* ]]
}

@test "prune keeps a copy that ended less than the margin before the oldest session" {
  use_a_b_c
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="2100" run --separate-stderr "$SCRIPT" prune
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [ -d ".worktrees/skill-$A" ]
  [ -d ".worktrees/skill-$B" ]
  [ -d ".worktrees/skill-$C" ]
}

@test "prune with no running session keeps only the current copy" {
  use_a_b_c
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
  [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
  [ ! -e ".worktrees/skill-$A" ]
  [ ! -e ".worktrees/skill-$B" ]
  [ -d ".worktrees/skill-$C" ]
  [ "$(readlink -f .claude/skills/demo-skill)" = "$(readlink -f ".worktrees/skill-$C")" ]
}

@test "use prunes: the superseded copy goes when no session runs" {
  "$SCRIPT" use "$A" 2>/dev/null
  SKILL_COPY_NOW=2000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" use "$B"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B ($B)"* ]]
  [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
  [ ! -e ".worktrees/skill-$A" ]
}

@test "prune never touches branch worktrees under .worktrees" {
  git worktree add -q -b feature/9-x .worktrees/9-x
  use_a_b_c
  SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"9-x"* ]]
  [ -d .worktrees/9-x ]
}

# --- refusals --------------------------------------------------------------

@test "use refuses to run outside the main worktree" {
  git worktree add -q -b feature/9-x .worktrees/9-x
  before=$(snapshot)
  cd .worktrees/9-x
  run --separate-stderr "$SCRIPT" use "$A"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: run from the main worktree"* ]]
  cd "$MAIN"
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses when /.worktrees/ is not ignored" {
  : > .gitignore
  git commit -qam "no .worktrees entry"
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$A"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: /.worktrees/ is not ignored by git"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses a commit whose SKILL.md has no name: field" {
  skill_md "" nameless
  git commit -qam nameless
  N=$(sha12 HEAD)
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$N"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: SKILL.md at $N has no name: field"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses when a non-link is in the way of the skill link" {
  mkdir -p .claude/skills/demo-skill
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$A"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: .claude/skills/demo-skill exists and is not a link"* ]]
  [ "$(snapshot)" = "$before" ]
}

@test "use refuses when a non-link is in the way of the agents link" {
  mkdir agents
  echo agent > agents/a.md
  git add agents
  git commit -qm agents
  D=$(sha12 HEAD)
  mkdir -p .claude/agents
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use "$D"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"skill-copy: .claude/agents exists and is not a link"* ]]
  [ "$(snapshot)" = "$before" ]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
