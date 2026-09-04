# FM-0100 — start-factory appears to hang at “Seeding the factory coordinator…”

**Status:** mitigated in-repo (docs + defaults); further polish optional  
**Reported:** 2026-09-04  
**Reporter:** owner  
**Component:** `start-factory.sh`, `run-factory-setup.sh`

## Symptom

During factory startup, the process sat on:

```text
Seeding the factory coordinator...
```

It felt hung. Owner Ctrl+C’d; afterward things “seemed to work.” Suspicion: it may have been waiting for the TUI to connect.

## Actual behavior (two different blocking steps)

### 1) Seed step (the message above)

`start-factory.sh` runs:

```bash
openclaw agent \
  --agent "$factory_agent" \
  --session-key main \
  --message "$initial_message" \
  --timeout 1800
```

This invokes the model for the coordinator’s first turn. That can take **minutes** with little or no streaming output. It is **not** waiting for a TUI connection.

If you Ctrl+C here:

- seeding is aborted
- the seed marker (`.factory-coordinator-seeded`) is **not** written (success path only)
- a later run may seed again (good) or you may have a partial first session (depends on OpenClaw)

### 2) TUI step (after seed, when `FACTORY_OPEN_TUI=1`)

```bash
openclaw tui --session "agent:${factory_agent}:main"
```

This is **interactive and blocks** until the TUI exits. In a setup script, that feels like a hang if you expected the shell to return.

So the usability bug is mostly **unclear UX + wrong default for non-interactive setup**, not necessarily a deadlock on TUI connect during seed.

## Mitigations shipped

1. **`run-factory-setup.sh` defaults `FACTORY_OPEN_TUI=0`**  
   Full bootstrap finishes without opening an interactive TUI. Print next-step commands instead.

2. **Clearer seed messaging in `start-factory.sh`**  
   Explains: long model run, not waiting for TUI; Ctrl+C aborts seed; how to run with TUI disabled.

3. **`FACTORY_SEED_TIMEOUT`**  
   Configurable timeout (default still 1800s); failure path does not write the seed marker and prints retry hints.

4. **`exec` TUI only when enabled**  
   Makes it obvious the process *becomes* the TUI when opened.

## Recommended operator workflow

```bash
# Non-interactive bootstrap
FACTORY_PROJECT=my-project \
FACTORY_GITHUB=owner/repo \
FACTORY_IDEA='...' \
./run-factory-setup.sh

openclaw gateway restart   # after configure_delegation.sh

# Interactive session when you want it
cd ~/.openclaw/workspaces/my-project/foreman
openclaw tui --session agent:my-project-foreman:main
```

Or seed + TUI intentionally:

```bash
FACTORY_PROJECT=my-project FACTORY_OPEN_TUI=1 ./start-factory.sh
```

## Possible follow-ups (not done yet)

- [ ] Stream/heartbeat dots while `openclaw agent` runs (if CLI supports status)
- [ ] Shorter default seed prompt for faster first token
- [ ] Separate `seed-factory.sh` from `open-factory-tui.sh` binaries
- [ ] Trap Ctrl+C and print “seed incomplete; marker not written”
- [ ] Unit/smoke test: `FACTORY_OPEN_TUI=0` returns promptly after mocked seed

## Acceptance for “fixed enough”

- [x] Setup pipeline does not block on TUI by default  
- [x] README documents seed vs TUI  
- [x] Seed step says it can take a long time and is not waiting for TUI  
- [ ] (optional) Visible progress during seed  
