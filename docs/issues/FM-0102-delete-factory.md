# FM-0102 — Delete / retire a software factory

**Status:** implemented in-repo (`delete-factory.sh`)  
**Priority:** P1 fleet ops  
**Date:** 2026-09-13

## Problem

Operators naturally try to disable a factory by renaming its workspace:

```bash
mv ~/.openclaw/workspaces/kalshi-multiplex-orderbook \
   ~/.openclaw/workspaces/kalshi-multiplex-orderbook.fail0
```

That is incomplete:

1. **`openclaw.json` still lists every role agent** (`*-foreman` / `*-factory`, `*-spec`, …) with the **old** workspace paths.
2. **`~/.openclaw/agents/<id>/`** session and agent state remain.
3. Other agents may still list the deleted ids in **`subagents.allowAgents`**.
4. Using `openclaw agents delete` alone is also wrong for this workflow: it **prunes config and tries to trash the workspace**, which fights “keep the tree; I’ll `rm` by hand later.”

## Desired behavior

One command that:

- Moves the project workspace aside (never `rm -rf` the factory tree).
- Removes all project role agents from OpenClaw config.
- Moves agent state dirs aside by default (inspect later).
- Scrubs residual allow-list references.
- Prints `openclaw gateway restart` as a required follow-up.
- Leaves permanent deletion of aside directories to the human.

## Solution

`scripts/delete-factory.sh` (+ root wrapper `delete-factory.sh`).

Sequence:

1. Resolve workspace (active path, or already-aside names like `.fail0` / `.deleted-*`).
2. Discover agents: standard role suffixes + any agent whose workspace sits under the project tree.
3. `mv` project workspace to `<project><suffix>` when still at the live name.
4. For each agent: retarget `workspace` to an empty temp dir → move `~/.openclaw/agents/<id>` aside → `openclaw agents delete <id> --force`.
5. Scrub other agents’ `subagents.allowAgents`.
6. `openclaw config validate`.
7. Optionally aside `~/.openclaw/factory-worktrees/<project>`.

## Usage

```bash
FACTORY_PROJECT=kalshi-multiplex-orderbook FACTORY_DELETE_DRY_RUN=1 ./delete-factory.sh
FACTORY_PROJECT=kalshi-multiplex-orderbook FACTORY_DELETE_SUFFIX=.fail0 ./delete-factory.sh
openclaw gateway restart
```

## Non-goals

- Deleting the product git repository.
- Automatic gateway restart (print only; operator chooses when).
- Mass-delete of every factory on the host.
- Replacing OpenClaw’s core `agents delete` semantics globally.

## Acceptance

- [x] Script + root wrapper in repo
- [x] README section + env table
- [x] Dry-run discovers already-moved `kalshi-multiplex-orderbook.fail0` and six agents
- [ ] Live run on a retired factory after PR merge / local checkout (owner)
- [ ] Gateway restart + `agents list` shows no project prefix
