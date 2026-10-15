# skill-repo-development

A Claude Code skill for developing other skills that are packaged as git repositories. Sessions that use such a skill while it is being edited get a **fixed copy** of it: a detached worktree at one commit, reached through a link that only moves on request. A checkout, a commit or a branch switch in the skill's repository never changes the skill under a running session, and a branch of the skill can be tested in a new session.

`SKILL.md` is the entry point. `tools/skill-copy.sh` is the command it describes.

## Installation

The skill is linked, not copied, and not installed in claude.ai: an installed copy has no version and goes stale. Clone this repository, then, from the root of the repository of the skill you edit:

```sh
mkdir -p .claude/skills
ln -s ../../../skill-repo-development .claude/skills/skill-repo-development   # adjust to where you cloned it
echo "/.claude/skills/skill-repo-development" >> .git/info/exclude
```

The link stays local (`.git/info/exclude`). It follows this repository's main worktree, which stays on `main`.

## Requirements

On the skill you edit:

- **A `name:` field** in the frontmatter of its `SKILL.md`. `skill-copy.sh` names the link after it, and refuses a commit without one.
- **Its base directory resolved with `readlink -f`.** Its `SKILL.md` tells sessions to resolve the base directory once, when the skill loads, and to use only the resolved path. Claude Code announces the link path, not its target; without this, a running session follows the link when it moves.
- **`/.worktrees/` in its `.gitignore`.** The copies live there.

On the machine: Linux with bash, git, `flock`, GNU coreutils (`mv -T`), `pgrep` and `ps` (procps). The tests need [bats](https://github.com/bats-core/bats-core) 1.5 or later.

## Usage

From the main worktree of the skill you edit:

```sh
S=.claude/skills/skill-repo-development
$S/tools/skill-copy.sh use origin/main            # setup, and after each merge
$S/tools/skill-copy.sh use origin/feature/7-xyz   # before starting a session that tests a branch
$S/tools/skill-copy.sh status                     # what is current, and which copies exist
$S/tools/skill-copy.sh prune                      # remove the copies no running session may use
```

Copies left by a session are removed once it ends, at the next `use` or `prune`. See `SKILL.md` for the procedures, the pruning rule and the exit codes.

## Tests

```sh
bats tools/
```

## Changing the skill

Open an issue in this repository. Changes follow the [scm-skill](https://github.com/CriticalOptimisation/scm-skill) process. `history.md` records them.
