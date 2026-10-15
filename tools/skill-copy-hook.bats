#!/usr/bin/env bats
# shellcheck disable=SC2154 # $stderr is set by bats run --separate-stderr, unknown to shellcheck
# Contract of tools/skill-copy-hook.sh, the hook that scm-skill's
# tools/skill-copy.sh sources from each copy of this skill (#3).
#
# The hook refuses a copy that contains .claude or .worktrees, as a directory,
# a file or a link, dangling or not: tools that follow links (find -L,
# grep -R, diff -r) would loop. A non-zero status makes scm-skill's use exit 1
# with the links unmoved; that part is scm-skill's, tested in scm-skill
# tools/skill-copy.bats.
#
# Each test makes a throwaway skill repository with one copy (a detached
# worktree, as scm-skill makes them) and a throwaway project, and sources the
# hook as scm-skill does: in a subshell, from the project root, with the copy's
# and the project's directories as $1 and $2.

bats_require_minimum_version 1.5.0

setup() {
  HOOK="$BATS_TEST_DIRNAME/skill-copy-hook.sh"
  TMP="$(realpath "$(mktemp -d)")"
  SKILL="$TMP/work/demo-skill"
  PROJ="$TMP/work/proj"
  mkdir -p "$PROJ"
  git init -q -b main "$SKILL"
  git -C "$SKILL" config user.email test@example.invalid
  git -C "$SKILL" config user.name test
  printf '/.worktrees/\n' > "$SKILL/.gitignore"
  printf -- '---\nname: demo-skill\ndescription: test skill\n---\n' > "$SKILL/SKILL.md"
  git -C "$SKILL" add .gitignore SKILL.md
  git -C "$SKILL" commit -qm A
  COPY="$SKILL/.worktrees/skill-$(git -C "$SKILL" rev-parse HEAD | cut -c1-12)-0123abcd"
  git -C "$SKILL" worktree add -q --detach "$COPY" HEAD
  # USER_PROJECT, as scm-skill writes it and excludes it.
  printf '%s\n' "$PROJ" > "$COPY/USER_PROJECT"
  echo /USER_PROJECT >> "$SKILL/.git/info/exclude"

  DRIVER="$TMP/driver.sh"
  cat > "$DRIVER" << 'EOF'
#!/usr/bin/env bash
# driver.sh <hook> <copy> <project>: sources the hook as scm-skill's
# tools/skill-copy.sh does.
set -uo pipefail
hook=$1 copy=$2 project=$3
(
  set +u
  cd "$project" || exit 1
  # shellcheck source=/dev/null
  . "$hook" "$copy" "$project"
)
EOF
  chmod +x "$DRIVER"
}

teardown() {
  rm -rf "$TMP"
}

source_hook() {
  "$DRIVER" "$HOOK" "$COPY" "$PROJ"
}

# Everything the hook must leave unchanged: the files of the copy and of the
# project, and the copy's git status.
snapshot() {
  (cd "$TMP/work" && find . -path ./demo-skill/.git -prune -o -print | sort)
  git -C "$COPY" status --porcelain
}

@test "the hook is shipped as tools/skill-copy-hook.sh" {
  [ -f "$HOOK" ]
}

@test "a clean copy passes silently, twice, and the hook changes nothing" {
  before=$(snapshot)
  for _ in 1 2; do
    run --separate-stderr source_hook
    [ "$status" -eq 0 ]
    [[ -z "$stderr" ]]
    [[ -z "$output" ]]
    [ "$(snapshot)" = "$before" ]
  done
}

@test "a .claude or .worktrees directory in the copy makes the hook fail with a message naming it" {
  for p in .claude .worktrees docs/.claude; do
    mkdir -p "$COPY/$p"
    run --separate-stderr source_hook
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"skill-copy-hook: refused: $COPY/$p is in the copy; tools that follow links would loop"* ]]
    [[ -z "$output" ]]
    [ -d "$COPY/$p" ]
    rm -rf "${COPY:?}/${p%%/*}"
  done
}

@test "a .claude or .worktrees link in the copy, dangling or not, makes the hook fail with a message naming it" {
  for p in .claude .worktrees; do
    for target in .. "$TMP/gone"; do
      ln -sfn "$target" "$COPY/$p"
      run --separate-stderr source_hook
      [ "$status" -ne 0 ]
      [[ "$stderr" == *"skill-copy-hook: refused: $COPY/$p is in the copy; tools that follow links would loop"* ]]
      [[ -z "$output" ]]
      [ "$(readlink "$COPY/$p")" = "$target" ]
      rm "$COPY/$p"
    done
  done
}

# --- edge cases ------------------------------------------------------------

@test "a regular file named .claude in the copy is refused" {
  echo x > "$COPY/.claude"
  run --separate-stderr source_hook
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"skill-copy-hook: refused: $COPY/.claude is in the copy; tools that follow links would loop"* ]]
  [[ -z "$output" ]]
}

@test "every offending path is reported once, and nothing below a refused one" {
  mkdir -p "$COPY/.claude/x/.claude" "$COPY/a/.worktrees"
  run --separate-stderr source_hook
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"refused: $COPY/.claude is in the copy"* ]]
  [[ "$stderr" == *"refused: $COPY/a/.worktrees is in the copy"* ]]
  [[ "$stderr" != *"$COPY/.claude/x/.claude"* ]]
  [ "$(printf '%s\n' "$stderr" | wc -l)" -eq 2 ]
  [[ -z "$output" ]]
}

@test "the hook does not follow a link out of the copy" {
  mkdir -p "$TMP/outside/.claude"
  ln -s "$TMP/outside" "$COPY/lib"
  run --separate-stderr source_hook
  [ "$status" -eq 0 ]
  [[ -z "$stderr" ]]
  [[ -z "$output" ]]
}

@test "with no copy directory, the hook fails" {
  COPY="$TMP/no-such-copy"
  run --separate-stderr source_hook
  [ "$status" -eq 1 ]
  [ "$stderr" = "skill-copy-hook: no copy at $TMP/no-such-copy" ]
  [[ -z "$output" ]]
}

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #5     | refuses .claude and .worktrees in the copy (#3)               |
