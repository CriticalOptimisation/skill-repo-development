---
name: skill-repo-development
description: Use when editing, testing or releasing an Agent Skill whose source is a git repository (SKILL.md at the repository root, linked into projects rather than copied). Covers loading a fixed version of the skill while it is being edited, testing a branch of the skill in a new session, switching back to main after a merge, and pruning old copies. Triggers on work in a skill repository, "test this branch of the skill", "which version of the skill is loaded", a stale or duplicated skill, or a skill symlink.
---

# Developing a skill packaged as a repository

**This skill is an add-on to scm-skill. Refuse to run without scm-skill:** if the scm-skill skill is not available in this session, stop, tell the user to install it (`<skill>/README.md`, *Installation*), and do nothing else.

A skill under development is also the skill that sessions use. Any session that loads it must get **a fixed version**, so that a checkout, a commit or a branch switch never changes the skill under a running session. The rule is: **copies are fixed when they are created, and only the link moves.**

## Paths

When this skill loads, resolve its base directory once with `readlink -f` and use only the resolved path. In this skill, `<skill>/…` is a path under that resolved directory, and `<scm-skill>/…` a path under scm-skill's resolved base directory. Every other path is relative to the root of the **edited skill's repository**, the one you work on.

## How Claude Code loads a linked skill

These facts were observed with Claude Code 2.1 and drive everything below.

- The skill list is discovered while a session runs: a new link under `.claude/skills/` is listed after the session's next tool call, even part way through a turn.
- The skill name is the `name:` field of `SKILL.md`. Without one, the name is the name of the link's directory. **Every skill repository sets `name:`.**
- The `SKILL.md` body is read when the skill is **invoked**, not when the session starts. Reference files are read later, as the session works.
- The *Base directory for this skill* that Claude Code announces is the **link path, not its target**. So a session that reads a reference file after the link moved reads the new copy. **Every skill repository tells its sessions to resolve the base directory once (`readlink -f`) when the skill loads, and to use only the resolved path.** Until a skill does this, keep its link still while any session uses it.
- A link that points into its own repository makes tools that follow symlinks loop (`find -L`, `grep -R`, `diff -r`). Never link a repository to its own working tree.
- A resumed session (`--resume`) is a new process, but its transcript names the copy it resolved before. That copy may have been pruned since: **after a resume, invoke the skill again.**

## The command

Copies and links are made by scm-skill's command, `<scm-skill>/tools/skill-copy.sh use <skill repo> <ref>`, run from the main worktree of the project. Its options, the layout of the copies, the pruning rule, the refusals and the exit codes are documented in scm-skill's `README.md` (*Using it in a project*). Here the project is the edited skill's own repository, so `<skill repo>` is `.`.

Using this skill's own `<skill>/tools/skill-copy.sh` is optional: it only installs this skill in a project, by running scm-skill's command (see `<skill>/README.md`).

## Procedures

**Setup, once per repository.**
1. Check that the edited skill's `SKILL.md` has a `name:` field and tells sessions to resolve the base directory with `readlink -f`. If not, fix that in the skill first.
2. Check that its `.gitignore` ignores `/.worktrees/`.
3. Remove any older link of the repository to itself (for example `.claude/skills/<dir> -> <main worktree>`).
4. Run `<scm-skill>/tools/skill-copy.sh use . origin/main`.

**Testing a branch.**
1. Push the branch. Run `<scm-skill>/tools/skill-copy.sh use . origin/<branch>`.
2. Start a new session. Its first action is a tool call; then it invokes the skill and reports the base directory and its resolved path.
3. When the resolved path names the branch copy, run `<scm-skill>/tools/skill-copy.sh use . origin/main`. The test session keeps its copy while it runs; new sessions get `main` again.

If the edited skill does not resolve its base directory yet, leave the link on the branch until the test session ends.

**After a merge.** Run `<scm-skill>/tools/skill-copy.sh use . origin/main`. Running sessions keep their copies; old copies go at the next `use` or `prune` after the sessions that may use them end.

**Checking what is loaded.** `<scm-skill>/tools/skill-copy.sh status .`, and in the session, the resolved base directory.

## Rules

- Never edit a copy. Edits happen in a branch worktree and reach a copy only through a commit and `use`.
- Never check out a branch in a copy, and never point a link at a branch worktree: it changes as the branch is developed.
- Projects that only *use* a skill install it the same way, with `<scm-skill>/tools/skill-copy.sh use <skill repo> <ref>` from their own main worktree; this procedure is for the skill's own repository.
- A copy of the skill installed in claude.ai or elsewhere with the same description competes with the linked one: remove it or update it.
