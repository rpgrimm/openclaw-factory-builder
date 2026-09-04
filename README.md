# openclaw-factory-maker

Create and run **OpenClaw software factories**: multi-agent project teams.

- The **factory** is the whole system (all roles + process).
- The **foreman** is the floor boss agent that talks to you and delegates.

This repository holds the **factory start/bootstrap scripts** used on the OpenClaw host, product planning docs, and startup UX fixes.

Skeleton roles (v0):

| Role | Agent id pattern | Workspace | Responsibility |
|------|------------------|-----------|----------------|
| **Foreman** | `<project>-foreman` | `.../<project>/foreman` | Talks to you, sequences work, delegates |
| **Spec** | `<project>-spec` | `.../spec` | Requirements, acceptance criteria |
| **Implement** | `<project>-implement` | `.../implement` | Build in branches/worktrees |
| **Verify** (includes **test**) | `<project>-verify` | `.../verify` | Independent review + testing |
| **Ship** | `<project>-ship` | `.../ship` | Release only after explicit human approval |

**Triage** is planned but not created by these scripts yet. **Test** is part of **verify** for now.

> Naming note: older factories used `<project>-factory` as the coordinator id and `.../factory` as the workspace. New scripts use **foreman**. `pause-all-factories.sh` still understands the legacy names.

---

## Quick start

On a host with OpenClaw installed and the Gateway running:

```bash
cd /path/to/openclaw-factory-maker   # or your checkout of this repo

export FACTORY_PROJECT=my-project
export FACTORY_GITHUB=owner/my-project          # optional but recommended
export FACTORY_IDEA='One-paragraph product idea'  # optional on first run

# Full bootstrap (agents + identities + delegation + seed)
# Defaults to FACTORY_OPEN_TUI=0 so setup does not block on an interactive TUI.
./run-factory-setup.sh

# After delegation changes:
openclaw gateway restart

# Talk to the foreman (interactive):
cd ~/.openclaw/workspaces/$FACTORY_PROJECT/foreman
openclaw tui --session "agent:${FACTORY_PROJECT}-foreman:main"
```

Or step by step:

```bash
export FACTORY_PROJECT=my-project
./make-factory.sh
./set-identities.sh
./set-factory-agent-md.sh
./configure_delegation.sh
openclaw gateway restart

# Seed once; open TUI yourself when ready
FACTORY_OPEN_TUI=0 FACTORY_GITHUB=owner/repo FACTORY_IDEA='...' ./start-factory.sh
```

### Environment variables

| Variable | Required | Meaning |
|----------|----------|---------|
| `FACTORY_PROJECT` | yes | Project id (workspace + agent prefix) |
| `FACTORY_GITHUB` | no | `owner/repo` or GitHub URL; verified with `gh` |
| `FACTORY_IDEA` | no | Starting product idea (inline) |
| `FACTORY_IDEA_FILE` | no | Starting idea from a file (not both with `FACTORY_IDEA`) |
| `FACTORY_OPEN_TUI` | no | `1` open TUI after seed (default for `start-factory.sh`); `0` skip. **`run-factory-setup.sh` defaults this to `0`.** |
| `FACTORY_RESEED_COORDINATOR` | no | `1` force re-send init prompt (`FACTORY_RESEED_FOREMAN` also accepted) |
| `FACTORY_GITHUB_REQUIRE_WRITE` | no | `1` require WRITE/MAINTAIN/ADMIN |
| `FACTORY_SEED_TIMEOUT` | no | Seconds for seed `openclaw agent` call (default `1800`) |

### GitHub token

Scripts read:

```text
~/.config/openclaw/github_token
```

into `GH_TOKEN`. They never print or commit the token. Prefer `chmod 600` on that file.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `run-factory-setup.sh` | Orchestrates full setup pipeline |
| `make-factory.sh` | Create/reuse agents: foreman, spec, implement, verify, ship |
| `set-identities.sh` | Names, themes, emoji |
| `set-factory-agent-md.sh` | Append foreman role block to `AGENTS.md` (skips if present) |
| `configure_delegation.sh` | Allow foreman to spawn workers (`subagents.allowAgents`) |
| `start-factory.sh` | Bind GitHub into `TOOLS.md`, seed foreman once, optional TUI |
| `pause-all-factories.sh` | Emergency stand-down message to every project foreman (legacy `*-factory` too) |
| `migrate-coordinator-to-foreman.sh` | Rename an existing project's `*-factory` coordinator → `*-foreman` |

Source of the original pack on this host: `~/.openclaw/.factory-start-code/` (imported and commented here).

---

## Startup usability (seed vs TUI)

If startup looked stuck on seeding, that step is **`openclaw agent` running the model**, not the TUI. It can take a long time with little output.

Separately, when `FACTORY_OPEN_TUI=1`, **`openclaw tui` blocks** until you exit the TUI.

**Mitigations:**

1. `run-factory-setup.sh` defaults `FACTORY_OPEN_TUI=0`.
2. `start-factory.sh` prints clearer progress/timeout messaging during seed.
3. Seed marker is written only after a successful seed.
4. Issue write-up: [`docs/issues/FM-0100-seed-hang-usability.md`](docs/issues/FM-0100-seed-hang-usability.md)

---

## Layout on the OpenClaw host

After setup for `FACTORY_PROJECT=my-project`:

```text
~/.openclaw/workspaces/my-project/
  foreman/     foreman workspace (floor boss)
  spec/
  implement/
  verify/
  ship/

Agents:
  my-project-foreman
  my-project-spec
  my-project-implement
  my-project-verify
  my-project-ship
```

Product code still lives in **your product git repo** (often attached via `FACTORY_GITHUB`). This maker repo is about **factory tooling and process**.

---

## Safety defaults

- No cron / unsolicited background work unless you explicitly enable it.
- Foreman should ask (or be told) before spawning workers.
- No ship/publish without **explicit** human approval.
- Never commit secrets, tokens, or private credentials.
- Verify is independent of implement; testing lives under verify for v0.

---

## Docs in this repo

- [`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md) — inventory of what existed on first planning day
- [`docs/PRODUCT_PLAN.md`](docs/PRODUCT_PLAN.md) — draft product plan
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — prioritized backlog
- [`docs/issues/FM-0100-seed-hang-usability.md`](docs/issues/FM-0100-seed-hang-usability.md) — seed/TUI hang
- [`docs/issues/FM-0101-rename-factory-to-foreman.md`](docs/issues/FM-0101-rename-factory-to-foreman.md) — coordinator rename

---

## Status

Early. Scripts are real and used; richer factory templates (`.factory/` contracts, triage role, upgrade tooling) are on the backlog. We improve this maker the same way it will improve other factories: small slices, explicit approval to publish.
