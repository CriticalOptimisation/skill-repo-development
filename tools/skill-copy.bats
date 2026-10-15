#!/usr/bin/env bats
# shellcheck disable=SC2154 # $stderr is set by bats run --separate-stderr, unknown to shellcheck
# Contract of tools/skill-copy.sh, the optional wrapper of scm-skill's
# tools/skill-copy.sh (#3, after scm-skill#23).
#
# The wrapper installs this skill in a project: it runs scm-skill's tool with
# this repository, a local path, as <skill repo>. It finds scm-skill's tool in
# $SKILL_COPY_TOOL, or else in the scm-skill that tools/find-scm-skill.sh finds.
#
# Every test uses stubs of scm-skill's tool that record what they were given,
# so no test depends on scm-skill. The wrapper and tools/find-scm-skill.sh are
# run from a copy (a detached worktree, as scm-skill makes them) of a throwaway
# repository of this skill, with a throwaway project in $WORK: nothing touches
# the real repositories or sees their links.
#
# The copy, link and pruning contract is scm-skill's; its tests are in
# scm-skill tools/skill-copy.bats. The tests of that contract that were here
# are kept as comments at the end of this file, under REVIEW PLACEHOLDER lines
# naming the scm-skill test that covers each one.

bats_require_minimum_version 1.5.0

USAGE="usage: skill-copy.sh use <ref> [options] | prune | status"

setup() {
  TMP="$(realpath "$(mktemp -d)")"
  WORK="$TMP/work"
  PROJ="$WORK/proj"
  CALLS="$TMP/calls"
  THIS="$TMP/elsewhere/skill-repo-development"
  repo "$THIS"
  printf '/.worktrees/\n' > "$THIS/.gitignore"
  printf -- '---\nname: skill-repo-development\ndescription: test skill\n---\n' > "$THIS/SKILL.md"
  mkdir -p "$THIS/tools"
  for f in skill-copy.sh find-scm-skill.sh; do
    if [ -f "$BATS_TEST_DIRNAME/$f" ]; then cp -p "$BATS_TEST_DIRNAME/$f" "$THIS/tools/"; fi
  done
  git -C "$THIS" add -A
  git -C "$THIS" commit -qm init
  REPO="$THIS/.worktrees/skill-$(git -C "$THIS" rev-parse HEAD | cut -c1-12)-proj"
  git -C "$THIS" worktree add -q --detach "$REPO" HEAD
  SCRIPT="$REPO/tools/skill-copy.sh"

  repo "$PROJ"
  printf '/.worktrees/\n' > .gitignore
  git add .gitignore
  git commit -qm init
  unset SKILL_COPY_TOOL STUB_STATUS
}

teardown() {
  rm -rf "$TMP"
}

# repo <dir>: a new repository with a test identity; leaves the shell in it.
repo() {
  git init -q -b main "$1"
  cd "$1" || return
  git config user.email test@example.invalid
  git config user.name test
}

# stub <path> <label>: a fake scm-skill tool. It writes its label, its working
# directory and its arguments, one per line, to $CALLS; prints "stub <label>
# out" on stdout and "stub <label> err" on stderr; and exits with $STUB_STATUS
# (0 by default).
stub() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" << EOF
#!/usr/bin/env bash
{ echo "$2"; pwd; printf '%s\n' "\$@"; } > "$CALLS"
echo "stub $2 out"
echo "stub $2 err" >&2
exit "\${STUB_STATUS:-0}"
EOF
  chmod +x "$1"
}

# stub_scm_skill <dir> <label>: a fake scm-skill: a SKILL.md named scm-skill
# and a stub tools/skill-copy.sh.
stub_scm_skill() {
  mkdir -p "$1"
  printf -- '---\nname: scm-skill\ndescription: test\n---\n' > "$1/SKILL.md"
  stub "$1/tools/skill-copy.sh" "$2"
}

# The default tool of a test: a stub named by SKILL_COPY_TOOL.
default_stub() {
  stub "$TMP/tool/skill-copy.sh" env
  export SKILL_COPY_TOOL="$TMP/tool/skill-copy.sh"
}

# Everything a failed or refused run must leave unchanged.
snapshot() {
  (cd "$TMP" && find . -name .git -prune -o -print | sort)
  cat "$PROJ/.git/info/exclude" 2>/dev/null
}

# --- general contract ------------------------------------------------------
#
# Exit codes: those of scm-skill's tool, unchanged; and, from the wrapper
# itself, 1 when scm-skill's tool cannot be found and 2 for a usage error.

# REVIEW PLACEHOLDER: the script exists and is executable -> the wrapper exists and is executable
# (converted in place.)
@test "the wrapper exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/skill-copy.sh" ]
}

# --- delegation ------------------------------------------------------------

@test "use <ref> [options] runs scm-skill's tool with use, this repository as a local path, the ref and the options, from the current directory" {
  default_stub
  run --separate-stderr "$SCRIPT" use origin/feature/7-x --frozen --skills-dir ext/skills
  [ "$status" -eq 0 ]
  [ "$stderr" = "stub env err" ]
  [ "$output" = "stub env out" ]
  [ "$(cat "$CALLS")" = "$(printf '%s\n' env "$PROJ" use "$REPO" origin/feature/7-x --frozen --skills-dir ext/skills)" ]
}

@test "prune and status run scm-skill's tool with this repository" {
  default_stub
  for cmd in prune status; do
    rm -f "$CALLS"
    run --separate-stderr "$SCRIPT" "$cmd"
    [ "$status" -eq 0 ]
    [ "$stderr" = "stub env err" ]
    [ "$output" = "stub env out" ]
    [ "$(cat "$CALLS")" = "$(printf '%s\n' env "$PROJ" "$cmd" "$REPO")" ]
  done
}

@test "the tool's exit code, stdout and stderr pass through unchanged" {
  default_stub
  for code in 0 1 3; do
    STUB_STATUS=$code run --separate-stderr "$SCRIPT" use origin/main
    [ "$status" -eq "$code" ]
    [ "$stderr" = "stub env err" ]
    [ "$output" = "stub env out" ]
  done
}

# --- finding scm-skill's tool ----------------------------------------------

@test "the tool is looked for in SKILL_COPY_TOOL, then in the scm-skill linked by the project, by this skill's repository, then next to the project, in that order" {
  stub "$TMP/tool/skill-copy.sh" env
  stub_scm_skill "$TMP/linked-by-project" project
  mkdir -p .claude/skills
  ln -s "$TMP/linked-by-project" .claude/skills/software-configuration-management
  stub_scm_skill "$TMP/linked-by-this" this
  mkdir -p "$THIS/.claude/skills"
  ln -s "$TMP/linked-by-this" "$THIS/.claude/skills/scm-skill"
  stub_scm_skill "$WORK/scm-skill" sibling

  SKILL_COPY_TOOL="$TMP/tool/skill-copy.sh" run --separate-stderr "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "$stderr" = "stub env err" ]
  [ "$(head -n 1 "$CALLS")" = env ]

  for next in project this sibling; do
    run --separate-stderr "$SCRIPT" status
    [ "$status" -eq 0 ]
    [ "$stderr" = "stub $next err" ]
    [ "$(head -n 1 "$CALLS")" = "$next" ]
    case $next in
      project) rm .claude/skills/software-configuration-management ;;
      this) rm "$THIS/.claude/skills/scm-skill" ;;
    esac
  done
}

@test "with no tool found, the wrapper exits 1 with the installation instructions and changes nothing" {
  before=$(snapshot)
  run --separate-stderr "$SCRIPT" use origin/main
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"skill-copy: scm-skill's tools/skill-copy.sh not found"* ]]
  [[ "$stderr" == *"git clone https://github.com/CriticalOptimisation/scm-skill.git ../scm-skill"* ]]
  [[ "$stderr" == *"../scm-skill/tools/skill-copy.sh use ../scm-skill origin/main"* ]]
  [ -z "$output" ]
  [ "$(snapshot)" = "$before" ]
}

# --- usage -----------------------------------------------------------------

# REVIEW PLACEHOLDER: an unknown subcommand, a missing ref or an extra argument exit with the usage code -> usage errors exit 2, before the tool is looked for; scm-skill tools/skill-copy.bats: an unknown subcommand, a missing argument or an extra argument exit with the usage code
# @test "an unknown subcommand, a missing ref or an extra argument exit with the usage code" {
#   for args in "" "unknown" "use" "use a b" "prune x" "status x"; do
#     run --separate-stderr "$SCRIPT" $args
#     [ "$status" -eq 2 ]
#     [[ "$stderr" == *"usage: skill-copy.sh use <ref> | prune | status"* ]]
#   done
# }
@test "usage errors exit 2, before the tool is looked for" {
  default_stub
  for args in "" "unknown" "use" "prune x" "status x"; do
    read -ra argv <<< "$args"
    run --separate-stderr "$SCRIPT" "${argv[@]}"
    [ "$status" -eq 2 ]
    [ "$stderr" = "skill-copy: $USAGE" ]
    [ -z "$output" ]
    [ ! -e "$CALLS" ]
  done
}

# --- edge cases ------------------------------------------------------------

@test "a SKILL_COPY_TOOL that is not executable exits 1 and runs nothing" {
  stub_scm_skill "$WORK/scm-skill" sibling
  run --separate-stderr env SKILL_COPY_TOOL="$TMP/no-such-tool" "$SCRIPT" status
  [ "$status" -eq 1 ]
  [ "$stderr" = "skill-copy: SKILL_COPY_TOOL is not an executable: $TMP/no-such-tool" ]
  [ -z "$output" ]
  [ ! -e "$CALLS" ]
}

@test "run through a link to this skill, the wrapper passes the real directory of the copy" {
  default_stub
  mkdir -p .claude/skills
  ln -s "$REPO" .claude/skills/skill-repo-development
  run --separate-stderr .claude/skills/skill-repo-development/tools/skill-copy.sh status
  [ "$status" -eq 0 ]
  [ "$stderr" = "stub env err" ]
  [ "$(cat "$CALLS")" = "$(printf '%s\n' env "$PROJ" status "$REPO")" ]
}

@test "run from a subdirectory, scm-skill's tool runs from that subdirectory" {
  default_stub
  mkdir sub
  cd sub
  run --separate-stderr "$SCRIPT" use origin/main
  [ "$status" -eq 0 ]
  [ "$stderr" = "stub env err" ]
  [ "$(cat "$CALLS")" = "$(printf '%s\n' env "$PROJ/sub" use "$REPO" origin/main)" ]
}

# --- tests of the old contract, moved to scm-skill ---------------------------
#
# The copy, link and pruning code of the old tools/skill-copy.sh (#1, PR #2)
# was ported to scm-skill tools/skill-copy.sh (scm-skill#23), and is removed
# here (#3). Each old test below names, after the arrow, the test of scm-skill
# tools/skill-copy.bats that covers it, or "none" with the reason. The helpers
# they call (snapshot, sha12, skill_md, use_a_b_c, fake_session) and their
# setup are those of tools/skill-copy.bats at 74caa22.

# REVIEW PLACEHOLDER: use creates the copy, links it relatively, excludes the link and logs the move -> scm-skill tools/skill-copy.bats: use creates the project's own detached copy in the skill repository, links it relatively, excludes the link and logs the move
# @test "use creates the copy, links it relatively, excludes the link and logs the move" {
#   run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
#   [ -d ".worktrees/skill-$A" ]
#   [ "$(git -C ".worktrees/skill-$A" rev-parse HEAD | cut -c1-12)" = "$A" ]
#   [ -z "$(git -C ".worktrees/skill-$A" branch --show-current)" ]
#   [ -L .claude/skills/demo-skill ]
#   [ "$(readlink .claude/skills/demo-skill)" = "../../.worktrees/skill-$A" ]
#   [ "$(readlink -f .claude/skills/demo-skill)" = "$(readlink -f ".worktrees/skill-$A")" ]
#   grep -qxF /.claude/skills/demo-skill .git/info/exclude
#   [ "$(cat .worktrees/skill-copies.log)" = "1000 skill-$A" ]
#   [ -z "$(git status --porcelain)" ]
# }
# REVIEW PLACEHOLDER: use accepts a remote branch name -> scm-skill tools/skill-copy.bats: use clones a missing skill repository next to the project
# @test "use accepts a remote branch name" {
#   run --separate-stderr "$SCRIPT" use origin/main
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$C (origin/main)"* ]]
#   [ "$(readlink -f .claude/skills/demo-skill)" = "$(readlink -f ".worktrees/skill-$C")" ]
# }
# REVIEW PLACEHOLDER: use run twice with the same ref changes nothing and logs nothing -> scm-skill tools/skill-copy.bats: use run twice changes nothing: files, excludes, worktrees and log
# @test "use run twice with the same ref changes nothing and logs nothing" {
#   "$SCRIPT" use "$A" 2>/dev/null
#   before=$(snapshot; cat .worktrees/skill-copies.log)
#   SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
#   [ "$(snapshot; cat .worktrees/skill-copies.log)" = "$before" ]
# }
# REVIEW PLACEHOLDER: use moves the link and keeps the previous copy fixed -> scm-skill tools/skill-copy.bats: a second use with another ref moves the links and leaves the first copy unchanged
# @test "use moves the link and keeps the previous copy fixed" {
#   "$SCRIPT" use "$A" 2>/dev/null
#   SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$B"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B ($B)"* ]]
#   [ "$(readlink .claude/skills/demo-skill)" = "../../.worktrees/skill-$B" ]
#   [ "$(tail -n 1 ".worktrees/skill-$A/SKILL.md")" = A ]
#   [ "$(printf '1000 skill-%s\n2000 skill-%s' "$A" "$B")" = "$(cat .worktrees/skill-copies.log)" ]
# }
# REVIEW PLACEHOLDER: use links .claude/agents when the copy has agents/ -> scm-skill tools/skill-copy.bats: use gives each agent of the copy its own relative link and leaves the project's own agents alone
# @test "use links .claude/agents when the copy has agents/" {
#   mkdir agents
#   echo agent > agents/a.md
#   git add agents
#   git commit -qm agents
#   D=$(sha12 HEAD)
#   run --separate-stderr "$SCRIPT" use "$D"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$D ($D)"* ]]
#   [ -L .claude/agents ]
#   [ "$(readlink .claude/agents)" = "../.worktrees/skill-$D/agents" ]
#   [ -f .claude/agents/a.md ]
#   grep -qxF /.claude/agents .git/info/exclude
# }
# REVIEW PLACEHOLDER: after use, find -L terminates -> scm-skill tools/skill-copy.bats: with the skill repository as the project, the copy and the links are in it, and find -L terminates
# @test "after use, find -L terminates" {
#   "$SCRIPT" use "$A" 2>/dev/null
#   run --separate-stderr timeout 10 find -L . -name SKILL.md
#   [ "$status" -eq 0 ]
#   [[ -z "$stderr" ]]
#   [[ "$output" == *"./.claude/skills/demo-skill/SKILL.md"* ]]
# }
# REVIEW PLACEHOLDER: prune removes the copies that ended before the oldest session, minus the margin -> scm-skill tools/skill-copy.bats: prune keeps a copy that stopped being current within the margin before the oldest session
# @test "prune removes the copies that ended before the oldest session, minus the margin" {
#   use_a_b_c
#   SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3500 3050" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
#   [[ "$stderr" != *"removed skill-$B"* ]]
#   [ ! -e ".worktrees/skill-$A" ]
#   [ -d ".worktrees/skill-$B" ]
#   [ -d ".worktrees/skill-$C" ]
#   [[ "$(git worktree list)" != *"skill-$A"* ]]
# }
# REVIEW PLACEHOLDER: prune keeps a copy that ended less than the margin before the oldest session -> scm-skill tools/skill-copy.bats: prune keeps a copy that stopped being current within the margin before the oldest session; SKILL_COPY_MARGIN changes the margin
# @test "prune keeps a copy that ended less than the margin before the oldest session" {
#   use_a_b_c
#   SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="2100" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ -z "$stderr" ]]
#   [ -d ".worktrees/skill-$A" ]
#   [ -d ".worktrees/skill-$B" ]
#   [ -d ".worktrees/skill-$C" ]
# }
# REVIEW PLACEHOLDER: prune with no running session keeps only the current copy -> scm-skill tools/skill-copy.bats: with no session and no other project, only the current copy is kept
# @test "prune with no running session keeps only the current copy" {
#   use_a_b_c
#   SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
#   [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
#   [ ! -e ".worktrees/skill-$A" ]
#   [ ! -e ".worktrees/skill-$B" ]
#   [ -d ".worktrees/skill-$C" ]
#   [ "$(readlink -f .claude/skills/demo-skill)" = "$(readlink -f ".worktrees/skill-$C")" ]
# }
# REVIEW PLACEHOLDER: use prunes: the superseded copy goes when no session runs -> scm-skill tools/skill-copy.bats: when this project moves on, its old copy goes and the other project's copy of the same commit stays
# @test "use prunes: the superseded copy goes when no session runs" {
#   "$SCRIPT" use "$A" 2>/dev/null
#   SKILL_COPY_NOW=2000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" use "$B"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$B ($B)"* ]]
#   [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
#   [ ! -e ".worktrees/skill-$A" ]
# }
# REVIEW PLACEHOLDER: prune never touches branch worktrees under .worktrees -> scm-skill tools/skill-copy.bats: prune never touches branch worktrees under .worktrees
# @test "prune never touches branch worktrees under .worktrees" {
#   git worktree add -q -b feature/9-x .worktrees/9-x
#   use_a_b_c
#   SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" != *"9-x"* ]]
#   [ -d .worktrees/9-x ]
# }
# REVIEW PLACEHOLDER: use refuses to run outside the main worktree -> scm-skill tools/skill-copy.bats: use refuses to run outside the main worktree of the project
# @test "use refuses to run outside the main worktree" {
#   git worktree add -q -b feature/9-x .worktrees/9-x
#   before=$(snapshot)
#   cd .worktrees/9-x
#   run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *"skill-copy: run from the main worktree"* ]]
#   cd "$MAIN"
#   [ "$(snapshot)" = "$before" ]
# }
# REVIEW PLACEHOLDER: use refuses when /.worktrees/ is not ignored -> scm-skill tools/skill-copy.bats: use refuses when /.worktrees/ is not ignored in the skill repository
# @test "use refuses when /.worktrees/ is not ignored" {
#   : > .gitignore
#   git commit -qam "no .worktrees entry"
#   before=$(snapshot)
#   run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *"skill-copy: /.worktrees/ is not ignored by git"* ]]
#   [ "$(snapshot)" = "$before" ]
# }
# REVIEW PLACEHOLDER: use refuses a commit whose SKILL.md has no name: field -> scm-skill tools/skill-copy.bats: use refuses a commit whose SKILL.md has no name: field
# @test "use refuses a commit whose SKILL.md has no name: field" {
#   skill_md "" nameless
#   git commit -qam nameless
#   N=$(sha12 HEAD)
#   before=$(snapshot)
#   run --separate-stderr "$SCRIPT" use "$N"
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *"skill-copy: SKILL.md at $N has no name: field"* ]]
#   [ "$(snapshot)" = "$before" ]
# }
# REVIEW PLACEHOLDER: use refuses when a non-link is in the way of the skill link -> scm-skill tools/skill-copy.bats: use refuses a non-link at the skill link
# @test "use refuses when a non-link is in the way of the skill link" {
#   mkdir -p .claude/skills/demo-skill
#   before=$(snapshot)
#   run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *"skill-copy: .claude/skills/demo-skill exists and is not a link"* ]]
#   [ "$(snapshot)" = "$before" ]
# }
# REVIEW PLACEHOLDER: use refuses when a non-link is in the way of the agents link -> scm-skill tools/skill-copy.bats: use refuses a regular file with the name of an agent link
# @test "use refuses when a non-link is in the way of the agents link" {
#   mkdir agents
#   echo agent > agents/a.md
#   git add agents
#   git commit -qm agents
#   D=$(sha12 HEAD)
#   mkdir -p .claude/agents
#   before=$(snapshot)
#   run --separate-stderr "$SCRIPT" use "$D"
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *"skill-copy: .claude/agents exists and is not a link"* ]]
#   [ "$(snapshot)" = "$before" ]
# }
# REVIEW PLACEHOLDER: outside a git repository, the script exits 1 -> scm-skill tools/skill-copy.bats: outside a git repository, use exits 1
# @test "outside a git repository, the script exits 1" {
#   cd "$TMP"
#   run --separate-stderr "$SCRIPT" status
#   [ "$status" -eq 1 ]
#   [[ "$stderr" == *"skill-copy: not in a git repository"* ]]
# }
# REVIEW PLACEHOLDER: use with an unknown ref exits 1 and changes nothing -> scm-skill tools/skill-copy.bats: use with an unknown ref exits 1 and changes nothing
# @test "use with an unknown ref exits 1 and changes nothing" {
#   before=$(snapshot)
#   run --separate-stderr "$SCRIPT" use no-such-ref
#   [ "$status" -eq 1 ]
#   [[ "$stderr" == *"skill-copy: unknown ref: no-such-ref"* ]]
#   [ "$(snapshot)" = "$before" ]
# }
# REVIEW PLACEHOLDER: use warns when the fetch fails and uses the local refs -> scm-skill tools/skill-copy.bats: use warns when the fetch fails and uses the local refs
# @test "use warns when the fetch fails and uses the local refs" {
#   git remote set-url origin "$TMP/missing.git"
#   run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: warning: fetch from origin failed; using local refs"* ]]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
#   [ -d ".worktrees/skill-$A" ]
# }
# REVIEW PLACEHOLDER: use removes the link of the old name when the name: field changed -> scm-skill tools/skill-copy.bats: use removes the link of the old name when the name: field changed
# @test "use removes the link of the old name when the name: field changed" {
#   "$SCRIPT" use "$A" 2>/dev/null
#   skill_md renamed-skill R
#   git commit -qam renamed
#   R=$(sha12 HEAD)
#   SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$R"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed link: .claude/skills/demo-skill"* ]]
#   [[ "$stderr" == *"skill-copy: renamed-skill -> skill-$R ($R)"* ]]
#   [ ! -e .claude/skills/demo-skill ] && [ ! -L .claude/skills/demo-skill ]
#   [ "$(readlink .claude/skills/renamed-skill)" = "../../.worktrees/skill-$R" ]
# }
# REVIEW PLACEHOLDER: use leaves alone a link of another skill that does not point to a copy -> scm-skill tools/skill-copy.bats: use leaves alone the links of another skill, even into that skill's copies
# @test "use leaves alone a link of another skill that does not point to a copy" {
#   mkdir -p .claude/skills
#   ln -s ../../../other-skill .claude/skills/other-skill
#   run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" != *"removed link"* ]]
#   [ "$(readlink .claude/skills/other-skill)" = "../../../other-skill" ]
# }
# REVIEW PLACEHOLDER: use removes .claude/agents when the new copy has no agents/ -> scm-skill tools/skill-copy.bats: use removes the link of an agent dropped between copies; a skill with no agents/ and no hook gets only its skill link
# @test "use removes .claude/agents when the new copy has no agents/" {
#   mkdir agents
#   echo agent > agents/a.md
#   git add agents
#   git commit -qm agents
#   D=$(sha12 HEAD)
#   "$SCRIPT" use "$D" 2>/dev/null
#   SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed link: .claude/agents"* ]]
#   [ ! -L .claude/agents ]
# }
# REVIEW PLACEHOLDER: use moves .claude/agents to the new copy's agents/ -> scm-skill tools/skill-copy.bats: a second use with another ref moves the links and leaves the first copy unchanged
# @test "use moves .claude/agents to the new copy's agents/" {
#   mkdir agents
#   echo one > agents/a.md
#   git add agents
#   git commit -qm agents1
#   D=$(sha12 HEAD)
#   echo two > agents/a.md
#   git commit -qam agents2
#   E=$(sha12 HEAD)
#   "$SCRIPT" use "$D" 2>/dev/null
#   SKILL_COPY_NOW=2000 run --separate-stderr "$SCRIPT" use "$E"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$E ($E)"* ]]
#   [ "$(readlink .claude/agents)" = "../.worktrees/skill-$E/agents" ]
#   [ "$(cat .claude/agents/a.md)" = two ]
# }
# REVIEW PLACEHOLDER: prune keeps a copy with changes in it, warns and exits 1 -> scm-skill tools/skill-copy.bats: prune keeps a copy with changes in it, warns and exits 1
# @test "prune keeps a copy with changes in it, warns and exits 1" {
#   use_a_b_c
#   echo edit >> ".worktrees/skill-$A/SKILL.md"
#   SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 1 ]
#   [[ "$stderr" == *"skill-copy: warning: skill-$A could not be removed (changes in it?); kept"* ]]
#   [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
#   [ -d ".worktrees/skill-$A" ]
# }
# REVIEW PLACEHOLDER: SKILL_COPY_MARGIN changes the margin -> scm-skill tools/skill-copy.bats: SKILL_COPY_MARGIN changes the margin
# @test "SKILL_COPY_MARGIN changes the margin" {
#   use_a_b_c
#   # B ended at 3000; the oldest session started at 3100: kept with 120 s, removed with 50 s.
#   SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3100" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
#   [[ "$stderr" != *"removed skill-$B"* ]]
#   [ -d ".worktrees/skill-$B" ]
#   SKILL_COPY_MARGIN=50 SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="3100" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
#   [ ! -e ".worktrees/skill-$B" ]
# }
# REVIEW PLACEHOLDER: a copy missing from the log counts as ended at 0 -> scm-skill tools/skill-copy.bats: a copy missing from the log and from the links counts as ended at 0
# @test "a copy missing from the log counts as ended at 0" {
#   "$SCRIPT" use "$A" 2>/dev/null
#   git worktree add -q --detach ".worktrees/skill-$B" "$B"
#   SKILL_COPY_NOW=4000 SKILL_COPY_STARTS="1000" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
#   [ -d ".worktrees/skill-$A" ]
# }
# REVIEW PLACEHOLDER: a copy current twice ends at the end of its last time as current -> none: scm-skill tools/skill-copy.bats has no test of a copy current twice
# @test "a copy current twice ends at the end of its last time as current" {
#   SKILL_COPY_NOW=1000 "$SCRIPT" use "$A" 2>/dev/null
#   SKILL_COPY_NOW=2000 "$SCRIPT" use "$B" 2>/dev/null
#   SKILL_COPY_NOW=3000 "$SCRIPT" use "$A" 2>/dev/null
#   SKILL_COPY_NOW=4000 "$SCRIPT" use "$C" 2>/dev/null
#   # A ended at 4000, B at 3000; the oldest session started at 3200.
#   SKILL_COPY_NOW=5000 SKILL_COPY_STARTS="3200" run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
#   [[ "$stderr" != *"removed skill-$A"* ]]
#   [ -d ".worktrees/skill-$A" ]
# }
# REVIEW PLACEHOLDER: use of a copy that still exists reuses it and logs the move -> none: scm-skill tools/skill-copy.bats has no test of a use that returns to an existing copy
# @test "use of a copy that still exists reuses it and logs the move" {
#   SKILL_COPY_NOW=1000 "$SCRIPT" use "$A" 2>/dev/null
#   SKILL_COPY_NOW=2000 "$SCRIPT" use "$B" 2>/dev/null
#   SKILL_COPY_NOW=3000 run --separate-stderr "$SCRIPT" use "$A"
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: demo-skill -> skill-$A ($A)"* ]]
#   [ "$(tail -n 1 .worktrees/skill-copies.log)" = "3000 skill-$A" ]
#   [ "$(readlink .claude/skills/demo-skill)" = "../../.worktrees/skill-$A" ]
# }
# REVIEW PLACEHOLDER: prune refuses outside the main worktree -> none: scm-skill's prune takes <skill repo> and runs from anywhere
# @test "prune refuses outside the main worktree" {
#   git worktree add -q -b feature/9-x .worktrees/9-x
#   cd .worktrees/9-x
#   run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 3 ]
#   [[ "$stderr" == *"skill-copy: run from the main worktree"* ]]
# }
# REVIEW PLACEHOLDER: prune with no copy and no log does nothing -> scm-skill tools/skill-copy.bats: prune with no copy and no log does nothing
# @test "prune with no copy and no log does nothing" {
#   run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ -z "$stderr" ]]
# }
# REVIEW PLACEHOLDER: status prints the current copy, the links and each copy's end time -> scm-skill tools/skill-copy.bats: status prints each copy with its project, linked or with its end time
# @test "status prints the current copy, the links and each copy's end time" {
#   mkdir agents
#   echo agent > agents/a.md
#   git add agents
#   git commit -qm agents
#   D=$(sha12 HEAD)
#   SKILL_COPY_NOW=1000 "$SCRIPT" use "$A" 2>/dev/null
#   SKILL_COPY_NOW=2000 "$SCRIPT" use "$D" 2>/dev/null
#   run --separate-stderr "$SCRIPT" status
#   [ "$status" -eq 0 ]
#   [[ -z "$stderr" ]]
#   [[ "$output" == *"current: skill-$D"* ]]
#   [[ "$output" == *"link: .claude/skills/demo-skill -> ../../.worktrees/skill-$D"* ]]
#   [[ "$output" == *"link: .claude/agents -> ../.worktrees/skill-$D/agents"* ]]
#   [[ "$output" == *"copy: skill-$D current"* ]]
#   [[ "$output" == *"copy: skill-$A ended 2000 ("* ]]
# }
# REVIEW PLACEHOLDER: status with no copy says none -> scm-skill tools/skill-copy.bats: status with no copy prints nothing
# @test "status with no copy says none" {
#   run --separate-stderr "$SCRIPT" status
#   [ "$status" -eq 0 ]
#   [[ -z "$stderr" ]]
#   [ "$output" = "current: none" ]
# }
# REVIEW PLACEHOLDER: without SKILL_COPY_STARTS, prune reads the sessions from pgrep and ps -> scm-skill tools/skill-copy.bats: without SKILL_COPY_STARTS, a real session keeps the copy it may use
# @test "without SKILL_COPY_STARTS, prune reads the sessions from pgrep and ps" {
#   use_a_b_c
#   fake_session 100
#   # Now 3300: the session started at 3200; A (2000) and B (3000) ended before 3080.
#   unset SKILL_COPY_STARTS
#   PATH="$TMP/bin:$PATH" SKILL_COPY_NOW=3300 run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
#   [[ "$stderr" == *"skill-copy: removed skill-$B"* ]]
#   [ -d ".worktrees/skill-$C" ]
# }
# REVIEW PLACEHOLDER: without SKILL_COPY_STARTS, a real session keeps the copy it may use -> scm-skill tools/skill-copy.bats: without SKILL_COPY_STARTS, a real session keeps the copy it may use
# @test "without SKILL_COPY_STARTS, a real session keeps the copy it may use" {
#   use_a_b_c
#   fake_session 400
#   # Now 3300: the session started at 2900; B ended at 3000, after 2780.
#   unset SKILL_COPY_STARTS
#   PATH="$TMP/bin:$PATH" SKILL_COPY_NOW=3300 run --separate-stderr "$SCRIPT" prune
#   [ "$status" -eq 0 ]
#   [[ "$stderr" == *"skill-copy: removed skill-$A"* ]]
#   [[ "$stderr" != *"removed skill-$B"* ]]
#   [ -d ".worktrees/skill-$B" ]
# }

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #2     | initial contract: use, pruning, refusals, edge cases (#1)     |
# | #3     | wrapper of scm-skill's tool, found by find-scm-skill.sh; old tests moved |
