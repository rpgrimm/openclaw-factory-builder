# FM-0101 — Rename coordinator `<project>-factory` → `<project>-foreman`

**Status:** implemented in maker scripts + this project migrated  
**Reported:** 2026-09-04  
**Reporter:** owner  

## Decision

The **whole multi-agent system is the factory**.  
The **floor-boss agent is the foreman**.

So the coordinator should not be named `*-factory`.

| Kind | Old | New |
|------|-----|-----|
| Agent id | `<project>-factory` | `<project>-foreman` |
| Workspace dir | `.../workspaces/<project>/factory` | `.../workspaces/<project>/foreman` |
| Display name | `...: Factory Coordinator` | `...: Foreman` |
| Seed marker | `.factory-coordinator-seeded` | `.foreman-seeded` |

Worker roles unchanged: `spec`, `implement`, `verify`, `ship`.

## Scope

- Maker scripts in this repo
- `~/.openclaw/.factory-start-code` mirror
- Live migration for `openclaw-factory-maker` itself
- Other existing factories (`mention-scout`, etc.) **not** auto-migrated unless owner runs the migrate script

## Follow-ups

- [ ] Optionally migrate other live factories
- [ ] Update product repos that hard-code coordinator agent ids in `.factory/project.yaml`
