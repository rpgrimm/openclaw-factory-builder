# Backlog — openclaw-factory-builder

**Priorities:** P0 = do first / unblock, P1 = near-term value, P2 = important later, P3 = park  
**Rule:** no implementation or GitHub publish until owner approves a slice

## P0 — Orientation & baseline

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-000 | Owner interview (state, goals, constraints, first slice) | This session | In progress |
| B-001 | Write `docs/CURRENT_STATE.md` | Inventory host + GitHub + packs | Done (draft) |
| B-002 | Write `docs/PRODUCT_PLAN.md` | Goals, non-goals, phases | Done (draft) |
| B-003 | Write prioritized backlog | This file | Done (draft) |
| B-004 | Confirm canonical product name & repo role | builder vs maker naming | Waiting owner |
| B-005 | Confirm first publish slice | Import start-code → repo; push approval | Waiting owner |

## P0 — After plan approval (first build slice)

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-010 | Import `~/.openclaw/.factory-start-code/` into workspace/repo layout | Scripts + README + issue md | Not started |
| B-011 | Normalize repo tree (`scripts/`, `docs/issues/`, README root) | Match README links in start-code | Not started |
| B-012 | Comment/clarity pass on scripts | Especially `start-factory.sh`, migrate, make-factory | Not started |
| B-013 | Local commit of baseline (no push until approval) | Coordinator workspace or attached clone | Not started |
| B-014 | Owner-approved push to `rpgrimm/openclaw-factory-builder` | Empty repo today | Blocked on approval |

## P1 — Startup UX (FM-0100)

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-020 | Verify mitigations vs lived hang | Defaults, messages, marker rules | Partial in start-code |
| B-021 | Progress/heartbeat during seed | If CLI allows status | Optional |
| B-022 | Trap Ctrl+C → “seed incomplete” message | | Optional |
| B-023 | Split `seed-factory` vs `open-factory-tui` entrypoints | | Optional |
| B-024 | Smoke: `FACTORY_OPEN_TUI=0` returns after mocked seed | | Not started |
| B-025 | Shorter default seed prompt option | Faster first token | Optional |

## P1 — Naming & this factory (FM-0101)

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-030 | Decision: migrate `openclaw-factory-builder` to foreman | Still `*-factory` + `factory/` dir | Waiting owner |
| B-031 | Run/adapt `migrate-coordinator-to-foreman.sh` for this project | Only if B-030 = yes | Not started |
| B-032 | Fix README paths that still say `.../factory` in places | FM-0100 recommended workflow snippet | Not started |
| B-033 | Document legacy vs modern layout | pause-all already dual-aware | Not started |

## P1 — Roles

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-040 | Decide triage model (per-project / global / hybrid) | Global `triage` exists | Waiting owner |
| B-041 | Add triage to `make-factory.sh` + identities + delegation | If per-project | Not started |
| B-042 | Foreman AGENTS.md block lists triage when present | | Not started |
| B-043 | Handoff template (goal, links, decided, blocked, DoD) | From `~/.openclaw/factory/ROLES.md` | Not started |
| B-044 | Verify playbook: independent of implement; includes test | | Not started |
| B-045 | Ship playbook: human gate checklist | | Not started |

## P2 — Consolidate host factory knowledge

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-050 | Absorb useful bits of `~/.openclaw/factory/` into repo | Templates, FACTORY.md patterns | Not started |
| B-051 | Deprecation note for host-only packs | Avoid two truths | Not started |
| B-052 | Repair or remove orphan `openclaw-factory-maker-*` agents | Workspaces missing | Waiting owner |
| B-053 | Policy: `.factory-start-code` symlink or copy-from-repo | | Waiting owner |

## P2 — Fleet operations

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-060 | Per-project migrate runbook for legacy factories | mention-scout, west-boca, etc. | Not started |
| B-061 | `pause-all-factories.sh` verify on mixed legacy/modern | | Not started |
| B-062 | Status command: list factories, coordinator id, seed marker | Nice-to-have | Not started |
| B-063 | Gateway restart reminder automation? | Print-only vs prompt | Careful |

## P3 — Later

| ID | Item | Notes | Status |
|----|------|-------|--------|
| B-070 | Rich `.factory/` contracts inside product repos | project.yaml etc. | Parked |
| B-071 | Multi-factory dashboard | | Parked |
| B-072 | Automatic worker spawning policies | Default remains ask-first | Parked |
| B-073 | Separate test agent (split from verify) | | Parked |

## Suggested order of attack (once you green-light build)

1. B-004/B-005 decisions  
2. B-010 → B-013 (local baseline)  
3. B-014 push if you want GitHub as SoT  
4. B-030/B-031 this factory naming  
5. B-020–B-023 UX polish as needed  
6. B-040–B-045 roles  
7. B-050–B-052 host cleanup  

## Explicitly out of backlog scope

- Implementing features for mention-scout / kalshi / west-boca / browser-plugin products  
- Publishing releases without owner approval  
- Enabling cron/autonomous loops unless you ask
