# Product Plan — openclaw-factory-builder

**Version:** 0.1 draft (2026-09-04)  
**Audience:** owner + factory coordinator  
**Status:** planning; pending owner interview answers

## 1. One-liner

**openclaw-factory-builder** is the product repo for **creating, migrating, and operating OpenClaw multi-agent software factories** — scripts, docs, role contracts, and operational fixes — starting from the host pack at `~/.openclaw/.factory-start-code/`.

## 2. Problem

Standing up a project factory today is possible but uneven:

- Startup can **look hung** (seed model call + optional TUI)
- **Naming** mixes “factory” (system) and coordinator agent ids (`*-factory` vs `*-foreman`)
- **Roles** the owner wants (especially **triage**) are not fully in the skeleton
- Host has **multiple generations** of factory tooling (global agents + per-project agents + partial maker migration)
- Useful scripts/docs are **not yet in GitHub**, so they are host-local and hard to version

## 3. Goals

### Primary (v1)

1. **Canonical repo** for factory maker scripts + README + issue docs  
2. **Reliable, non-spooky bootstrap** (seed/TUI UX fixed enough for daily use)  
3. **Clear role model**: foreman, triage, spec, implement, verify, ship  
4. **Safe defaults**: no publish without human approval; no surprise cron; token hygiene  
5. **Migration path** from legacy `*-factory` coordinators to `*-foreman`

### Secondary (v1.x)

6. Shared **playbooks / contracts** (how foreman delegates; handoff shape; verify gates)  
7. **Triage** role provisioned per project (or clearly shared global triage with policy)  
8. Host cleanup guidance for orphan maker agents / dual starter packs  
9. Smoke tests for setup scripts

### Non-goals (for now)

- Building the *product* apps of other factories (mention-scout, kalshi, etc.) inside this repo  
- Fully autonomous multi-factory orchestration without human prompts  
- Paid SaaS wrapper around OpenClaw  
- Replacing OpenClaw gateway/core

## 4. Users

| User | Need |
|------|------|
| Owner (you) | Create/manage factories, tweak process, trust safety rails |
| Foreman agent | Clear AGENTS/TOOLS contracts, delegation allow-list, seed prompt |
| Worker agents | Role-scoped playbooks, handoffs, no freelancing outside lane |
| Future operators | Documented env vars and recovery (pause, reseed, migrate) |

## 5. Product shape

```text
rpgrimm/openclaw-factory-builder          ← this product (maker tooling)
        │
        ├── scripts/   bootstrap, migrate, pause, seed
        ├── docs/      plan, backlog, issues, current state
        ├── templates/ optional AGENTS/SOUL/role blocks
        └── (later) tests/, examples/

On host after setup for project P:\n\n~/.openclaw/workspaces/P/{foreman,triage?,spec,implement,verify,ship}
agents: P-foreman, P-triage?, P-spec, ...
```

**Factory** = the multi-agent system for a project.  
**Foreman** = the human-facing coordinator agent.

## 6. Role model (target)

| Role | Responsibility | v0 status in starter scripts |
|------|----------------|------------------------------|
| **Foreman** | Talk to owner, plan, sequence, delegate | Yes (`*-foreman`) |
| **Triage** | Intake, labels, routing, readiness | Desired; **not** in make-factory yet |
| **Spec** | Requirements, AC, breakdown | Yes |
| **Implement** | Build in branches/worktrees | Yes |
| **Verify** | Independent review + test | Yes (includes test) |
| **Ship** | Release only after explicit approval | Yes |

Decision needed: triage **per-project** vs keep **global** `triage` agent (exists today for GitHub intake patterns).

## 7. Operating principles

1. Owner approval for any externally visible GitHub/publish action  
2. Small slices; scripts stay boring and greppable  
3. Prefer fixing UX and contracts over clever autonomy  
4. Verify stays independent of implement  
5. Existing factories are not mass-migrated without an explicit go  
6. This factory improves *itself* with the same discipline it teaches

## 8. Success metrics (lightweight)

- Cold bootstrap for a new project completes without “is it hung?” moments when following README  
- New factories use foreman naming end-to-end  
- Repo is the source of truth (host copy can be checkout or sync of repo)  
- Owner can pause all factories in one command  
- Documented path to add triage and to migrate one legacy factory

## 9. Phased delivery

### Phase 0 — Orient (this session)

- Inventory host + empty GitHub  
- Interview owner  
- Product plan + backlog  
- **No publish**

### Phase 1 — Land the baseline in git (local first, push on approval)

- Import `.factory-start-code` into repo layout  
- README as canonical  
- Issues FM-0100 / FM-0101 filed as docs  
- Comment pass for clarity where thin

### Phase 2 — Harden bootstrap UX

- Confirm seed/TUI defaults in all entrypoints  
- Optional: progress/heartbeat, Ctrl+C messaging, split seed vs tui helpers  
- Align *this* project to foreman naming if owner wants

### Phase 3 — Role completeness

- Triage provisioning + contracts  
- Handoff templates; verify/ship gates  
- Optional merge/rationalize `~/.openclaw/factory` templates into repo

### Phase 4 — Fleet ops

- Migrate chosen legacy factories  
- Orphan maker workspace repair  
- Pause/status/smoke tooling

## 10. Risks

| Risk | Mitigation |
|------|------------|
| Divergent copies (start-code vs repo vs `~/.openclaw/factory`) | Single canonical repo; document sync direction |
| Breaking live factories by renaming | Migrate script opt-in per project |
| Seed still feels slow | Messaging + optional progress; don’t pretend model is instant |
| Scope creep into every product factory’s domain | Keep this repo maker-focused |
| Config orphans (maker agents, no dirs) | Explicit cleanup task, owner-approved |

## 11. First implementation slice (proposed, not started)

After interview sign-off:

1. Local repo structure matching starter pack + `docs/`  
2. README polish if gaps vs lived reality  
3. Owner-approved initial commit/push to empty GitHub  
4. Decide whether to migrate **this** coordinator to `*-foreman` before or after push

## 12. Open decisions (interview)

1. Product name on GitHub: keep `openclaw-factory-builder` or prefer `openclaw-factory-maker`?  
2. Is the source of truth going forward **this GitHub repo**, with `.factory-start-code` as import only?  
3. Triage: per-project agent, global shared agent, or both?  
4. Migrate this builder factory to foreman naming now?  
5. Auto-migrate other live factories or leave until asked?  
6. Relationship to `~/.openclaw/factory` starter pack — absorb, deprecate, or leave?  
7. How polished must FM-0100 be before “done”?  
8. Identity: what to call this coordinator assistant day-to-day?
