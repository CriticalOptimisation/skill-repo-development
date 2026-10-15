# Change History

This file tracks the PRs that changed the skill's files. It is never referenced from skill content.

| PR  | Closes | Summary |
|-----|--------|---------|
| #2  | #1     | initial version: SKILL.md, tools/skill-copy.sh (use, prune, status) and its tests, README.md, .gitignore |
| #5  | #3     | tools/ shellcheck-clean (tools/shellcheck.bats); tools/skill-copy.sh reduced to a wrapper of scm-skill's tool; tools/find-scm-skill.sh; tools/skill-copy-hook.sh; SKILL.md and README.md: add-on to scm-skill, installation from a local path |
| #6  | #4     | CI workflow .github/workflows/ci.yml (check bats: bats tools/, shellcheck required, no skips); tools/ci.bats; README.md: CI and the check to require |
