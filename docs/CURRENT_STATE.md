# Current State — openclaw-factory-builder

**As of:** 2026-09-04  
**Coordinator session:** `openclaw-factory-builder-factory` (legacy `*-factory` id; workspace `.../factory`)  
**Status:** planning only — no code published, GitHub repo empty

## What this project is trying to be

A **maker / manager for OpenClaw software factories**: scripts + process to create and operate multi-agent project teams (foreman + specialized workers), and to improve that machinery over time.

Owner starting idea (paraphrase):

- Manage the software factory roles: foreman, triage, spec, verify, implement, ship
- Iterate requirements/tweaks as the factory is used
- Fix startup UX (“seeding factory” feels hung; TUI interaction confusion)
- Take `~/.openclaw/.factory-start-code/` as the source baseline
- README + comments + keep GitHub (`rpgrimm/openclaw-factory-builder`) updated **when approved**

## Inventory

### GitHub

| Item | State |
|------|--------|
| Repo | `rpgrimm/openclaw-factory-builder` |
| URL | https://github.com/rpgrimm/openclaw-factory-builder |
| Contents | **Empty** (no default branch content yet) |
| Access | Token at `~/.config/openclaw/github_token` works for `rpgrimm` via `GH_TOKEN` |

### Starter / source pack (primary product input)

Path: `~/.openclaw/.factory-start-code/`

| File | Role |
|------|------|
| `README.md` | Product-facing docs for factory maker (foreman naming, env vars, UX) |
| `run-factory-setup.sh` | Full bootstrap pipeline; **defaults `FACTORY_OPEN_TUI=0`** |
| `make-factory.sh` | Create foreman + spec/implement/verify/ship agents & workspaces |
| `set-identities.sh` | Display names / emoji |
| `set-factory-agent-md.sh` | Append SOFTWARE FACTORY block to foreman `AGENTS.md` |
| `configure_delegation.sh` | `subagents.allowAgents` on foreman |
| `start-factory.sh` | GitHub bind into `TOOLS.md`, one-time seed, optional TUI |
| `pause-all-factories.sh` | Freeze message to all project foremen (legacy `*-factory` too) |
| `migrate-coordinator-to-foreman.sh` | Rename `*-factory` → `*-foreman` + workspace move |
| `FM-0100-seed-hang-usability.md` | Issue write-up for seed/TUI hang |
| `FM-0101-rename-factory-to-foreman.md` | Foreman rename decision |

Notable behaviors already in starter pack:

- Naming: **factory = system**, **foreman = coordinator agent**
- Seed step messaging clarifies long model run ≠ waiting for TUI
- Seed marker only written on success (`.foreman-seeded`)
- `run-factory-setup.sh` does not open TUI by default
- Triage **not** provisioned by skeleton yet; test folded into verify

### This factory instance (openclaw-factory-builder)

| Role | Agent id | Workspace | Notes |
|------|----------|-----------|-------|
| Coordinator | `openclaw-factory-builder-factory` | `.../factory` | **Still legacy name** (`*-factory`, dir `factory`) |
| Spec | `openclaw-factory-builder-spec` | `.../spec` | Exists |
| Implement | `openclaw-factory-builder-implement` | `.../implement` | Exists |
| Verify | `openclaw-factory-builder-verify` | `.../verify` | Exists |
| Ship | `openclaw-factory-builder-ship` | `.../ship` | Exists |
| Triage | — | — | **Not created** for this project |

- Coordinator workspace has default OpenClaw bootstrap files + `STARTING_IDEA.md` + GitHub access block in `TOOLS.md`
- Seed marker present: `.factory-coordinator-seeded` (legacy marker name)
- Local git in coordinator workspace: **no commits yet** (untracked bootstrap files only)
- Worker workspaces look like fresh defaults (not heavily customized)

### Related / parallel systems on this host

1. **`~/.openclaw/factory/`** — older “Software Factory Starter Pack”  
   - Oriented at **west-boca-pc-build-lab** as product  
   - Global agents: `main`, `triage`, `spec`, `implement`  
   - Templates + `bootstrap-agent.sh`  
   - Planned roles historically: review, test, docs, release  

2. **Per-project factories** under `~/.openclaw/workspaces/` (all still **`factory/` + `*-factory` coordinator** except maker attempt):  
   - `mention-scout`  
   - `west-boca-pc-build-lab`  
   - `browser-plugin-ai-img-filter`  
   - `kalshi-multiplex-orderbook`  
   - `openclaw-factory-builder` (this one)

3. **`openclaw-factory-maker-*` agents** in config  
   - Foreman + workers registered with **foreman** naming  
   - Workspaces under `.../workspaces/openclaw-factory-maker/{foreman,...}` → **directories missing**  
   - Looks like a partial migration / incomplete setup (config orphans)

4. Global `triage` / `spec` / `implement` agents still exist alongside per-project role agents → **two factory generations** on one host.

## Known pain points (from owner + evidence)

1. **Seed hang UX (FM-0100)** — “Seeding the factory…” feels stuck; Ctrl+C; then TUI.  
   - Root causes: long silent `openclaw agent` seed + optional blocking TUI  
   - Mitigations already in starter scripts/docs; optional polish remains (progress, split binaries, Ctrl+C trap)

2. **Naming drift (FM-0101)** — factory vs foreman  
   - Starter scripts use foreman  
   - This project and older projects still on `*-factory` / `factory/` workspace  
   - Maker project half-migrated (agents without workspaces)

3. **Role gap: triage** — desired in starting idea; not in `make-factory.sh` skeleton

4. **Dual packs** — `.factory-start-code` vs `~/.openclaw/factory` templates; risk of divergent truth

5. **Empty GitHub** — starter code lives only on host until first approved publish

6. **No autonomous cron** for this factory unless owner explicitly enables (coordinator instruction)

## Constraints (observed / instructed)

- Do not invent repo location; configured repo is `rpgrimm/openclaw-factory-builder`
- No push/publish/release/settings changes without explicit approval
- No spend / customer contact / production changes without approval
- No unsolicited agent cron or background acting
- Never print or commit GitHub token
- Prefer inspect → plan → small slices over big rewrites
- Until repo attached with content, focus planning/requirements/architecture/backlog (repo exists but empty)

## Open questions (for owner interview)

See interview in session; tracked in `docs/PRODUCT_PLAN.md` and backlog assumptions.
