# FM-0103 — Import an existing factory from another machine

**Status:** implemented in-repo (`import-factory.sh`), not published  
**Priority:** P2 fleet ops  
**Date:** 2026-11-20

## Problem

`new-factory.sh` creates a factory from a blank idea. There was no way to adopt a factory that already exists on another OpenClaw host.

Copying `openclaw.json` across machines is the wrong tool. It would mix gateway, auth, models, and plugins, and workspace paths from the other home would be wrong.

## Decision

Owner direction (2026-11-20):

- Source: another machine
- Payload: **workspaces only**

Import copies role workspaces and registers agents on this host. It does **not** copy chats, agent sqlite/session state, tokens, or the other host's `openclaw.json`.

## Behavior

`scripts/import-factory.sh` (+ root wrapper `import-factory.sh`).

1. Accept a local project workspace root (`FACTORY_IMPORT_SRC`) or pull one over SSH (`FACTORY_IMPORT_SSH`).
2. Require `foreman/` or legacy `factory/`. A single role directory is rejected. An OpenClaw home (`openclaw.json`, or `agents/` + `workspaces/`) is rejected.
3. Map legacy `factory/` → `foreman/` by default.
4. Refuse symlinks that point outside the source tree.
5. Skip `github_token`, `openclaw.json`, key files, `*.pem`, `openclaw-agent.sqlite*`, and role-level `sessions/` and `agents/` directories.
6. Abort if the destination already has role dirs, unless `FACTORY_IMPORT_FORCE=1` (rsync, no `--delete`).
7. Abort if an agent id already points at a different workspace. Import never retargets.
8. Register missing role agents with `openclaw agents add`.
9. Apply `IDENTITY.md` via `openclaw agents set-identity --from-identity` when present; otherwise use the skeleton defaults.
10. Set `subagents.allowAgents` to the worker roles that were actually present (including triage).
11. Append the foreman role block only when `AGENTS.md` has no `SOFTWARE FACTORY` section.
12. Rewrite `github_token_file`, `project`, and `agent` in seed markers to this host. Do not rewrite other workspace files. Do not reseed.

A dry run writes nothing to the destination and registers nothing. An SSH dry run still downloads the workspace into a temp dir so the layout can be checked, then deletes that temp dir.

## Out of scope

- Merging two hosts' `openclaw.json`
- Copying `~/.openclaw/agents/<id>` session history
- Copying or printing tokens
- Restarting the gateway
- Seeding or starting the interview
