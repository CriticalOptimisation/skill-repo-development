#!/usr/bin/env bash
# Fixed copies of a skill repository (#1).
#
# Run from the main worktree of the edited skill's repository. A copy is a
# detached worktree .worktrees/skill-<sha12>, fixed when it is created; only
# the links .claude/skills/<name> and .claude/agents move. Contract: the
# skill's SKILL.md, section "The command".
#
# Exit codes: 0 success; 1 git error, unknown ref, or a copy not removed;
# 2 usage; 3 refused for safety.
set -uo pipefail

readonly E_FAIL=1 E_USAGE=2 E_REFUSED=3
readonly LOG=.worktrees/skill-copies.log LOCK=.worktrees/skill-copies.lock
readonly MARGIN=${SKILL_COPY_MARGIN:-120}

say() { printf 'skill-copy: %s\n' "$*" >&2; }
die() { local code=$1; shift; say "$@"; exit "$code"; }
usage() { die "$E_USAGE" "usage: skill-copy.sh use <ref> | prune | status"; }

now() { echo "${SKILL_COPY_NOW:-$(date +%s)}"; }

# Goes to the root of the main worktree, or refuses. Two tests internal to
# git, never a path, as in scm-skill's worktree.sh: symbolic links make paths
# lie.
enter_main_worktree() {
  local top gitdir common
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "$E_FAIL" "not in a git repository"
  cd "$top" || die "$E_FAIL" "cannot enter $top"
  gitdir=$(realpath "$(git rev-parse --git-dir)") || die "$E_FAIL" "git rev-parse failed"
  common=$(realpath "$(git rev-parse --git-common-dir)") || die "$E_FAIL" "git rev-parse failed"
  [[ $gitdir == "$common" && -d .git ]] || die "$E_REFUSED" "run from the main worktree"
  git check-ignore -q .worktrees/skill-copies.log ||
    die "$E_REFUSED" "/.worktrees/ is not ignored by git"
}

lock() {
  mkdir -p .worktrees || die "$E_FAIL" "cannot create .worktrees"
  exec 9> "$LOCK" && flock 9 || die "$E_FAIL" "cannot lock $LOCK"
}

current() { tail -n 1 "$LOG" 2>/dev/null | cut -d' ' -f2; }

# Prints "<copy> <end time>" for each copy that stopped being current: the time
# of the log line after its last time as current.
end_times() {
  [[ -f $LOG ]] || return 0
  awk '{ t[NR] = $1; c[NR] = $2 }
       END { for (i = 1; i < NR; i++) end[c[i]] = t[i + 1]
             for (k in end) if (k != c[NR]) print k, end[k] }' "$LOG"
}

# Start times (epoch seconds) of the running sessions, one per line.
session_starts() {
  if [[ -v SKILL_COPY_STARTS ]]; then
    printf '%s\n' $SKILL_COPY_STARTS
    return
  fi
  local t pid et
  t=$(now)
  for pid in $(pgrep -x claude); do
    et=$(ps -o etimes= -p "$pid" 2>/dev/null) && echo $((t - et))
  done
}

# The name: field of SKILL.md at a commit.
skill_name() {
  git show "$1:SKILL.md" 2>/dev/null |
    awk '/^---[[:space:]]*$/ { n++; next }
         n == 1 && /^name:/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }'
}

exclude() {
  local file
  file=$(git rev-parse --git-common-dir)/info/exclude
  mkdir -p "${file%/*}"
  grep -qxF -- "$1" "$file" 2>/dev/null || echo "$1" >> "$file"
}

# relink <link> <target>: replaces a symbolic link atomically.
relink() {
  [[ -L $1 && $(readlink -- "$1") == "$2" ]] && return 0
  ln -s -- "$2" "$1.new.$$" && mv -T -- "$1.new.$$" "$1" || die "$E_FAIL" "cannot link $1"
}

# True if a link points to a copy.
links_to_copy() { [[ -L $1 && $(readlink -- "$1") == *.worktrees/skill-* ]]; }

cmd_use() {
  local ref=$1 full sha copy name agents=0 l
  enter_main_worktree
  git fetch -q origin 2>/dev/null || say "warning: fetch from origin failed; using local refs"
  full=$(git rev-parse -q --verify "$ref^{commit}") || die "$E_FAIL" "unknown ref: $ref"
  sha=${full:0:12}
  copy=skill-$sha
  name=$(skill_name "$full")
  [[ -n $name ]] || die "$E_REFUSED" "SKILL.md at $ref has no name: field"
  [[ $(git cat-file -t "$full:agents" 2>/dev/null) == tree ]] && agents=1
  [[ -e .claude/skills/$name && ! -L .claude/skills/$name ]] &&
    die "$E_REFUSED" ".claude/skills/$name exists and is not a link"
  (( agents )) && [[ -e .claude/agents && ! -L .claude/agents ]] &&
    die "$E_REFUSED" ".claude/agents exists and is not a link"

  lock
  if [[ ! -d .worktrees/$copy ]]; then
    git worktree add -q --detach ".worktrees/$copy" "$full" || die "$E_FAIL" "git worktree add failed"
  fi
  mkdir -p .claude/skills
  exclude "/.claude/skills/$name"
  relink ".claude/skills/$name" "../../.worktrees/$copy"
  for l in .claude/skills/*; do
    [[ $l != ".claude/skills/$name" ]] && links_to_copy "$l" && rm -- "$l" && say "removed link: $l"
  done
  if (( agents )); then
    exclude /.claude/agents
    relink .claude/agents "../.worktrees/$copy/agents"
  elif links_to_copy .claude/agents; then
    rm -- .claude/agents && say "removed link: .claude/agents"
  fi
  [[ $(current) == "$copy" ]] || echo "$(now) $copy" >> "$LOG"
  say "$name -> $copy ($ref)"
  prune_copies
}

# Removes each copy that is not current and stopped being current earlier than
# the oldest session start minus the margin; with no session, all of them.
prune_copies() {
  local cur starts oldest dir copy end rc=0
  local -A ends=()
  cur=$(current)
  starts=$(session_starts | grep -E '^[0-9]+$' | sort -n)
  oldest=${starts%%$'\n'*}
  while read -r copy end; do [[ -n $copy ]] && ends[$copy]=$end; done < <(end_times)
  for dir in .worktrees/skill-*/; do
    [[ -d $dir ]] || continue
    copy=$(basename "$dir")
    [[ $copy == "$cur" ]] && continue
    end=${ends[$copy]:-0}
    [[ -n $oldest ]] && (( end >= oldest - MARGIN )) && continue
    if git worktree remove "$dir" 2>/dev/null; then
      say "removed $copy"
    else
      say "warning: $copy could not be removed (changes in it?); kept"
      rc=$E_FAIL
    fi
  done
  git worktree prune
  return "$rc"
}

cmd_prune() {
  enter_main_worktree
  lock
  prune_copies
}

cmd_status() {
  local cur l dir copy end
  local -A ends=()
  enter_main_worktree
  cur=$(current)
  echo "current: ${cur:-none}"
  for l in .claude/skills/* .claude/agents; do
    links_to_copy "$l" && echo "link: $l -> $(readlink -- "$l")"
  done
  while read -r copy end; do [[ -n $copy ]] && ends[$copy]=$end; done < <(end_times)
  for dir in .worktrees/skill-*/; do
    [[ -d $dir ]] || continue
    copy=$(basename "$dir")
    if [[ $copy == "$cur" ]]; then
      echo "copy: $copy current"
    else
      end=${ends[$copy]:-0}
      echo "copy: $copy ended $end ($(date -d "@$end" '+%F %T'))"
    fi
  done
}

dispatch() {
  (( $# >= 1 )) || usage
  local cmd=$1
  shift
  case $cmd in
    use)    (( $# == 1 )) || usage; cmd_use "$1" ;;
    prune)  (( $# == 0 )) || usage; cmd_prune ;;
    status) (( $# == 0 )) || usage; cmd_status ;;
    *)      usage ;;
  esac
}

dispatch "$@"

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
