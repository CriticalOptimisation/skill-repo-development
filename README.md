# skill-repo-development

A Claude Code skill for developing other skills that are packaged as git repositories. Sessions that use such a skill while it is being edited get a **fixed copy** of it: a detached worktree at one commit, reached through a link that only moves on request. A checkout, a commit or a branch switch in the skill's repository never changes the skill under a running session, and a branch of the skill can be tested in a new session.

It is an add-on to [scm-skill](https://github.com/CriticalOptimisation/scm-skill), which makes the copies and the links (`tools/skill-copy.sh` of scm-skill). `SKILL.md` is the entry point, and refuses to run without scm-skill.

## Installation

The skill is installed with scm-skill's `skill-copy.sh use`, as a fixed copy, and not in claude.ai: an installed copy has no version and goes stale. **`<skill repo>` is a local path**: the one clone of this repository on the machine, which every project shares. Each project then gets its own copy in that clone's `.worktrees/`, and nothing is downloaded again. Clone this repository only if the machine has no clone yet (`git clone https://github.com/CriticalOptimisation/skill-repo-development.git`); never pass its URL to `use`, which would clone it once more next to each project that is not next to the first one.

From the main worktree of the project, with scm-skill found as below:

```sh
<scm-skill>/tools/skill-copy.sh use /path/to/skill-repo-development origin/main
```

This links `.claude/skills/skill-repo-development` to the project's copy. Run it again, with another ref, to update. scm-skill's `README.md` documents the command, its options, pruning and exit codes.

### Finding scm-skill

`tools/find-scm-skill.sh`, run from a project, prints the directory of scm-skill on this machine, so that scm-skill is not cloned again either. Most repositories already link scm-skill, so it looks for the first skill named `scm-skill` (by the `name:` field of its `SKILL.md`, whatever the link is called), in this order:

1. linked under `.claude/skills/` of the project's main worktree;
2. linked under `.claude/skills/` of the main worktree of this skill's own repository: a project that links this skill but not scm-skill finds scm-skill through this skill's own link;
3. a clone `../scm-skill` next to the project.

Found, it prints the resolved directory and exits `0`; `<dir>/tools/skill-copy.sh use <dir> origin/main`, from the main worktree of the project, then installs scm-skill there. Not found, it exits `1`, prints nothing on stdout, and prints the installation instructions of scm-skill on stderr (`git clone https://github.com/CriticalOptimisation/scm-skill.git ../scm-skill`, then `../scm-skill/tools/skill-copy.sh use ../scm-skill origin/main`). It changes nothing, so every run gives the same answer. `SKILL.md` uses it when it refuses to run without scm-skill.

### The optional wrapper

**This repository's `tools/skill-copy.sh` is optional.** It does the same thing as scm-skill's command, without naming this repository:

```sh
/path/to/skill-repo-development/tools/skill-copy.sh use origin/main [options]   # runs: <scm-skill tool> use <this repository> origin/main [options]
/path/to/skill-repo-development/tools/skill-copy.sh prune                       # runs: <scm-skill tool> prune <this repository>
/path/to/skill-repo-development/tools/skill-copy.sh status                      # runs: <scm-skill tool> status <this repository>
```

- It runs scm-skill's `tools/skill-copy.sh` from the current directory, with this repository, as a local path, as `<skill repo>`, and passes the rest of the arguments on. Its exit code, stdout and stderr are those of scm-skill's tool.
- It runs `$SKILL_COPY_TOOL` if it is set, and otherwise the `tools/skill-copy.sh` of the scm-skill that `tools/find-scm-skill.sh` finds.
- When none is found, it exits `1` with the installation instructions of scm-skill; it changes nothing. A usage error exits `2`, before scm-skill's tool is looked for.

## The skill-copy hook

`tools/skill-copy-hook.sh` is the hook that scm-skill's `use` sources from each copy of this skill (see scm-skill's `README.md`, *The skill-copy hook*). It refuses a copy that contains `.claude` or `.worktrees`, anywhere in it, as a directory, a file or a link, dangling or not: tools that follow links (`find -L`, `grep -R`, `diff -r`) would loop. It then prints `skill-copy-hook: refused: <path> is in the copy; tools that follow links would loop` on stderr and fails, so `use` exits `1` and the links do not move. Otherwise it is silent and changes nothing.

## Requirements

On the skill you edit:

- **A `name:` field** in the frontmatter of its `SKILL.md`. scm-skill's `skill-copy.sh` names the link after it, and refuses a commit without one.
- **Its base directory resolved with `readlink -f`.** Its `SKILL.md` tells sessions to resolve the base directory once, when the skill loads, and to use only the resolved path. Claude Code announces the link path, not its target; without this, a running session follows the link when it moves.
- **`/.worktrees/` in its `.gitignore`.** The copies live there.

On the machine: [scm-skill](https://github.com/CriticalOptimisation/scm-skill) and its requirements, and bash. The tests need [bats](https://github.com/bats-core/bats-core) 1.5 or later. [`shellcheck`](https://www.shellcheck.net/) is optional: `tools/shellcheck.bats` checks that `tools/*.sh` and `tools/*.bats` are shellcheck-clean, and is skipped without it.

## Usage

From the main worktree of the skill you edit, with scm-skill's command (`S=$(/path/to/skill-repo-development/tools/find-scm-skill.sh)`):

```sh
$S/tools/skill-copy.sh use . origin/main            # setup, and after each merge
$S/tools/skill-copy.sh use . origin/feature/7-xyz   # before starting a session that tests a branch
$S/tools/skill-copy.sh status .                     # which copies exist
$S/tools/skill-copy.sh prune .                      # remove the copies no running session may use
```

See `SKILL.md` for the procedures.

## Tests

```sh
bats tools/
```

## Changing the skill

Open an issue in this repository. Changes follow the [scm-skill](https://github.com/CriticalOptimisation/scm-skill) process. `history.md` records them.
