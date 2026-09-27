# onogoro design

## The problem

A coding agent needs the model's API key, and it runs whatever the model asks it to run.
If you confine the whole agent (`porta run comide ...`, a container, a VM), the key goes
inside with it. Then every command the model asks for can read the key from the
environment, a config file, or the agent's own memory. Confinement does limit what those
commands can write. But the most valuable secret on the machine sits on the wrong side of
the line.

This was measured on 2026-09-27, running comide inside porta on Terminal-Bench 2.0
(comide `bench/tb2`):

- The write limits held: no task tried to write outside its grants.
- The key could be read, because `--env-pass CLOUDFLARE_API_TOKEN` put it in the confined
  process's environment.

## The line

```
supervisor (outside)                         worker (inside porta, one per tool call)
─────────────────────                        ─────────────────────────────────────────
comide's loop, screen, conversation          the command the model asked for
model calls through almai                    golemide solve / verify, shell, edits
the real keys                                placeholder keys only
the egress proxy (keys put on by host)       network only through that proxy
the policy, the audit log                    an empty environment
asking the person                            writes only to the project and a scratch dir
```

The supervisor never runs model-chosen code. A worker never holds a real key.

## What is protected, and what is not

Protected:
- The keys. A worker sees a placeholder. The proxy replaces it with the real key only on
  a request to the host the key is bound to (OpenShell's broker, nono's phantom token).
  A placeholder sent anywhere else is refused, not forwarded.
- The machine outside the project. Writes are confined to the project and a scratch dir.
  Credential stores (`~/.ssh`, `~/.aws`, …) cannot be read; porta's preset closes them.
- Other processes and the network, as far as porta enforces it on the host. Inside a
  Docker container there is no user namespace, so Landlock is all there is, and porta
  says so.

Not protected:
- **Using a key without stealing it.** A worker can send the placeholder to the key's own
  bound host, and the proxy will put the key on the request. Binding a key to a binary
  (the proxy looks up the connecting process through `/proc` on Linux, as OpenShell does)
  narrows this. It does not remove it.
- The project itself. The agent is there to change it. `git` and porta's `--snapshot`
  are the ways back.
- Bugs in the supervisor. It is ordinary code with the keys in it.

## The parts, and the seam in each

| Part | What onogoro needs from it | Seam |
|---|---|---|
| comide | the loop, the tools, the permission prompt | every command comide runs goes through `toolkit.run_program` (`src/toolkit.almd`). A `runner` in `toolkit.Setup` would let onogoro wrap each call with no fork of comide. |
| golemide | edits, solve, verify | `solve` calls the model itself, and it runs the verify command. Phase 1 runs all of golemide as a worker. The broker (phase 2) gives it a placeholder key. |
| porta | the confinement, the proxy | phase 1: the `porta` binary, run once per call. Later: imported as an Almide library, so there is one binary and no exec per call. |
| almai | model calls | used only by the supervisor |

## Phases

Each phase ends on a measurement: Terminal-Bench 2.0 tasks solved (comide `bench/tb2`),
and, from phase 3, porta's containment suite.

1. **The line, with the binaries that exist.**
   - onogoro starts comide with a runner that wraps each tool call:
     `porta run <cmd> -v <project> -v <scratch> --allow-net … -- <args>`.
   - Workers get an empty environment, with no keys.
   - golemide runs as a worker. It needs a model key for `solve`, so in this phase
     `solve` gets the real key by name. That is the known gap phase 2 closes.
   - Measure: tasks solved against comide under whole-process porta (the 2026-09-27
     baseline). Check that `env` inside a worker shows no key.
2. **Keys by placeholder.**
   - porta's proxy learns credential bindings: `KEY → host[:port][/path], header`.
   - It terminates TLS only for bound hosts, with a per-run CA trusted through
     `SSL_CERT_FILE` and its kin, and forwards everything else as plain CONNECT.
   - Workers get placeholders, including golemide.
   - Measure: no real key reaches any worker's environment, files or memory. A placeholder
     sent to an unbound host is refused. Tasks solved stays unchanged.
3. **Refusals as answers.**
   - When a call is refused, the tool result carries porta's explanation: what was refused,
     and the grant that would allow it.
   - The model can take another path, or ask for the grant. The request goes to comide's
     permission prompt, and a grant the person approves applies to the next call.
   - Every decision is written to a JSONL audit log.
4. **One binary.**
   - A static musl build of the supervisor with porta inside, as a library, not an exec.
     Blocked on almide/almide#2772 and almide/porta#35.
   - It runs on any Linux, including inside containers and on Alpine, and on macOS.
5. **Policy per tool.**
   - Grants differ by tool: reads wide and the verify command narrow, and network only for
     the tools that need it.
   - Borrowed from Cloudflare OS's Gatekeepers: what a worker has read can close what later
     calls may send out.

## What this depends on

- almide/almide#2772: a static musl build (phase 4)
- almide/porta#35: Linux release binaries run on older glibc (phase 4; phase 1 builds porta
  from source until then)
- almide/porta#36: porta says so when a mount cannot be written under Landlock (Docker
  Desktop shares)
- almide/porta#37: a credential broker in the proxy (phase 2)
- O6lvl4/comide#2: a `runner` seam in `toolkit.Setup` (phase 1)
- O6lvl4/comide#1: a reply cut off before any text ends the turn. This is not onogoro's
  bug, but it caps what the measurements can show.

## Open questions

- **How onogoro drives comide.** Import comide's modules as an Almide dependency and pass
  a runner, or run comide as a process with a flag that points its commands at a runner
  program. The dependency is cleaner. The process form keeps comide's release independent.
- **golemide's own model calls.** Should golemide ask the supervisor to make them for it
  (so golemide never needs a key, not even a placeholder), or keep calling almai itself
  through the broker?
- **macOS.** Seatbelt has no per-call cost worth noticing. porta's macOS mode still
  permits broad reads and inherited variables (porta `docs/competitive-direction.md`).
  How much of the line holds there?
