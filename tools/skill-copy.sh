#!/usr/bin/env bash
# Optional wrapper of scm-skill's tools/skill-copy.sh (#3, after scm-skill#23).
#
# Installs this skill in the project of the current directory: runs
# scm-skill's tool with this repository, as a local path, as <skill repo>.
# scm-skill's tool is $SKILL_COPY_TOOL, or else the tools/skill-copy.sh of the
# scm-skill that tools/find-scm-skill.sh finds. Contract: README.md, "The
# optional wrapper".
#
# Exit codes: those of scm-skill's tool; 1 when it cannot be found; 2 usage.
set -uo pipefail

say() { printf 'skill-copy: %s\n' "$*" >&2; }
usage() { say "usage: skill-copy.sh use <ref> [options] | prune | status"; exit 2; }

(( $# >= 1 )) || usage
case $1 in
  use)          (( $# >= 2 )) || usage ;;
  prune|status) (( $# == 1 )) || usage ;;
  *)            usage ;;
esac

here=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
repo=$(realpath "$here/..")

if [[ -n ${SKILL_COPY_TOOL:-} ]]; then
  tool=$SKILL_COPY_TOOL
  [[ -x $tool ]] || { say "SKILL_COPY_TOOL is not an executable: $tool"; exit 1; }
elif scm=$("$here/find-scm-skill.sh"); then
  tool=$scm/tools/skill-copy.sh
else
  say "scm-skill's tools/skill-copy.sh not found"
  exit 1
fi

cmd=$1
shift
exec "$tool" "$cmd" "$repo" "$@"

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #2     | initial version: use, prune, status (#1)                      |
# | #5     | reduced to a wrapper of scm-skill's tool (#3)                 |
