---
name: skill-repo-development
description: Use when editing, testing or releasing an Agent Skill whose source is a git repository (SKILL.md at the repository root, linked into projects rather than copied). Covers loading a fixed version of the skill while it is being edited, testing a branch of the skill in a new session, switching back to main after a merge, and pruning old copies. Triggers on work in a skill repository, "test this branch of the skill", "which version of the skill is loaded", a stale or duplicated skill, or a skill symlink.
---

# Developing a skill packaged as a repository

A skill under development is also the skill that sessions use. Any session that loads it must get **a fixed version**, so that a checkout, a commit or a branch switch never changes the skill under a running session. The rule is: **copies are fixed when they are created, and only the link moves.**

## Paths

When this skill loads, resolve its base directory once with `readlink -f` and use only the resolved path. In this skill, `<skill>/…` is a path under that resolved directory. Every other path is relative to the root of the **edited skill's repository**, the one you work on.

## How Claude Code loads a linked skill

These facts were observed with Claude Code 2.1 and drive everything below.

- The skill list is discovered while a session runs: a new link under `.claude/skills/` is listed after the session's next tool call, even part way through a turn.
- The skill name is the `name:` field of `SKILL.md`. Without one, the name is the name of the link's directory. **Every skill repository sets `name:`.**
- The `SKILL.md` body is read when the skill is **invoked**, not when the session starts. Reference files are read later, as the session works.
- The *Base directory for this skill* that Claude Code announces is the **link path, not its target**. So a session that reads a reference file after the link moved reads the new copy. **Every skill repository tells its sessions to resolve the base directory once (`readlink -f`) when the skill loads, and to use only the resolved path.** Until a skill does this, keep its link still while any session uses it.
- A link that points into its own repository makes tools that follow symlinks loop (`find -L`, `grep -R`, `diff -r`). Never link a repository to its own working tree.
- A resumed session (`--resume`) is a new process, but its transcript names the copy it resolved before. That copy may have been pruned since: **after a resume, invoke the skill again.**

## Layout in the skill's repository

All of it is untracked and lives in the **main worktree** of the edited skill's repository.

| Path | What it is |
|---|---|
| `.worktrees/skill-<sha12>` | A copy: a detached worktree at one commit (`<sha12>` = 12 hex digits). Never checked out again, never edited. Detached, so it never conflicts with a branch checked out elsewhere. |
| `.claude/skills/<name>` | The relative link to the current copy. `<name>` is the copy's `name:` field. |
| `.claude/agents` | The relative link to the current copy's `agents/`, only if the copy has one. |
| `.worktrees/skill-copies.log` | One line per link move: `<epoch seconds> skill-<sha12>`. |

`/.worktrees/` must be ignored by the repository's `.gitignore`. The links are added to `.git/info/exclude`. Branch worktrees (`.worktrees/{number}-{description}`) live next to the copies; the command never touches them.

## The command: `<skill>/tools/skill-copy.sh`

Run it from the main worktree of the edited skill's repository. Messages go to stderr, prefixed `skill-copy:`.

| Command | Effect |
|---|---|
| `use <ref>` | Fetches `origin` (a failed fetch only warns), resolves `<ref>` to a commit, creates `.worktrees/skill-<sha12>` if it is missing, moves the links to it, logs the move, then prunes. **Idempotent**: run again with the same ref, it changes nothing and logs nothing. |
| `prune` | Removes the copies the pruning rule allows. Changes nothing else. |
| `status` | Prints the current copy, the links and their targets, and each copy with the time it stopped being current. |

- **Exit status**: `0` success; `1` git error, unknown ref, or a copy that could not be removed; `2` usage error; `3` refused for safety.
- **Refusals** (exit `3`, nothing changed): not run from the main worktree; `/.worktrees/` not ignored; `SKILL.md` at `<ref>` has no `name:` field; something other than a link at `.claude/skills/<name>`, or at `.claude/agents` when the copy has `agents/`. These checks run before any change: the `name:` field is read with `git show`, before the copy exists.
- **Links** are relative, so the clone can move, and they are replaced atomically. A link that would point to a copy no longer current is removed: an old `.claude/skills/<other name>` into `.worktrees/skill-*` (the `name:` changed), and `.claude/agents` when the new copy has no `agents/`.
- **Pruning rule.** A copy's *end time* is the time of the log line that follows its last time as current; a copy missing from the log ended at `0`. A copy that is not current is removed if its end time is earlier than **the start of the oldest running `claude` process, minus a margin**. The margin is 120 s, or `SKILL_COPY_MARGIN` seconds. It covers the delay between a `use` and the start of the session that tests it. With no running session, only the current copy stays. A copy that `git worktree remove` refuses (it has changes) is kept, with a warning, and the command exits `1`.
- **Sessions** are the processes named `claude` on the machine, including those working on other projects: they only keep copies longer. Start times come from `ps -o etimes=`.
- **Concurrency**: `use` and `prune` hold a lock on `.worktrees/skill-copies.lock`.
- **Test seams**, read only when set: `SKILL_COPY_STARTS` (start times in epoch seconds, space-separated; empty means no running session) and `SKILL_COPY_NOW` (the current time).

## Procedures

**Setup, once per repository.**
1. Check that the edited skill's `SKILL.md` has a `name:` field and tells sessions to resolve the base directory with `readlink -f`. If not, fix that in the skill first.
2. Check that its `.gitignore` ignores `/.worktrees/`.
3. Remove any older link of the repository to itself (for example `.claude/skills/<dir> -> <main worktree>`).
4. Run `<skill>/tools/skill-copy.sh use origin/main`.

**Testing a branch.**
1. Push the branch. Run `<skill>/tools/skill-copy.sh use origin/<branch>`.
2. Start a new session. Its first action is a tool call; then it invokes the skill and reports the base directory and its resolved path.
3. When the resolved path names the branch copy, run `<skill>/tools/skill-copy.sh use origin/main`. The test session keeps its copy while it runs; new sessions get `main` again.

If the edited skill does not resolve its base directory yet, leave the link on the branch until the test session ends.

**After a merge.** Run `<skill>/tools/skill-copy.sh use origin/main`. Running sessions keep their copies; old copies go at the next `use` or `prune` after the sessions that may use them end.

**Checking what is loaded.** `<skill>/tools/skill-copy.sh status`, and in the session, the resolved base directory.

## Rules

- Never edit a copy. Edits happen in a branch worktree and reach a copy only through a commit and `use`.
- Never check out a branch in a copy, and never point a link at a branch worktree: it changes as the branch is developed.
- Projects that only *use* a skill link its main worktree or a clone; this procedure is for the skill's own repository.
- A copy of the skill installed in claude.ai or elsewhere with the same description competes with the linked one: remove it or update it.
