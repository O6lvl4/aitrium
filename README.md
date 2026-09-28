<p align="center">A world for coding agents to work in: the agent runs its tools in a sandbox the kernel enforces,<br>and the keys stay outside it.</p>
<p align="center"><a href="README_ja.md">日本語</a></p>

> In a Roman house you came in through the door, the *porta*, and stood in the atrium: the
> open hall just inside, where guests were received and the household's work went on under
> the owner's eye. The strongbox stood there too, and it was the owner who held its key.

aitrium is that hall for a coding agent. It comes in through porta, and the one who keeps
the house decides what it may do there: what may be written, what may be read, which
hosts may be reached. The agent works in the hall. The keys stay with the owner.

**Status: phase 2 of [the plan](docs/design.md).** Every command comide runs goes through
porta, and no key goes in with any of them: golemide, which calls the model itself, is
handed placeholders that porta's proxy swaps for the real key on the model's host alone
(almide/porta#37). This rests on porta from develop and Almide v0.65.1-rc2 or later (see
`aitrium --help`); `AITRIUM_CREDENTIALS=by-name` hands golemide the keys themselves instead.

```sh
curl -fsSL https://raw.githubusercontent.com/O6lvl4/aitrium/main/install.sh | sh
```

A release carries everything aitrium runs, built together at the commits
[dist/PARTS](dist/PARTS) names: comide, golemide, porta, gramide, hew and ctxgate. It
unpacks into `~/.local/share/aitrium` and links `~/.local/bin/aitrium`, so a comide or
porta you already have stays as it is. For macOS on Apple silicon, and Linux on x86_64 and
aarch64 with glibc 2.31 or newer. Keys go where comide and golemide read them
(`~/.config/golemide/.env`, or the environment).

```sh
aitrium                       # comide's conversation, every tool's command confined
aitrium -p "fix the tests"    # one request; any of comide's arguments work
```

aitrium runs the comide and porta beside it; from a clone, put comide (0.5.0 with
`--runner`, O6lvl4/comide#2) and porta on `PATH`, or point `AITRIUM_COMIDE` /
`AITRIUM_PORTA` at them. `AITRIUM_NET=none` closes the network
to commands; `aitrium --help` says the rest.

| What comide runs | Writes | Network | Keys |
|---|---|---|---|
| `read` (hew, git status) | a scratch dir | none | none |
| `shell` (what the model wrote) | the project, the scratch dir | open (`AITRIUM_NET`) | none |
| `solve` (golemide) | the project, the scratch dir | open | placeholders, which porta swaps for the key on the model's host alone (`AITRIUM_CREDENTIALS=by-name`: the keys) |

Every call also has the files the keys live in (`~/.config/golemide/.env`, …) closed to
reads, `TMPDIR` set to the scratch dir, and credential stores closed by porta's preset.

What that comes to, checked on each release by [scripts/host-check.sh](scripts/host-check.sh)
on bare Ubuntu 22.04 and 24.04 (x86_64 and arm64), with a fake key and no model:

1. A command can write the project.
2. A command cannot write your home directory.
3. A command cannot read the file the keys live in.
4. A command gets no key in its environment.
5. golemide (`solve`) gets a placeholder (`porta-cred-…`), not the key.
6. The key is in no variable inside `solve`.
7. golemide cannot read the file the keys live in either.

These are about keys and writes. What aitrium contains when a model or a task tries to take
the key or send data out is not measured yet (#2).

**On your Claude login.** `aitrium --model claude/sonnet` (or `claude`, `claude/opus`)
runs comide on Claude Code's `claude -p`. golemide, inside, cannot use that login:
porta closes the Keychain it lives in. So aitrium starts a bridge on 127.0.0.1
(`bridge/claude_bridge.py`, needs `python3`) with a token for the session, and `solve`
is given only the bridge's URL and that token. The bridge stops when comide does.

## What it is

aitrium puts two existing tools together. Both stay products of their own:

- [comide](https://github.com/O6lvl4/comide), a coding agent in the terminal, with
  [golemide](https://github.com/O6lvl4/golemide) for its code changes
- [porta](https://github.com/almide/porta), which confines a command with the kernel:
  Landlock and seccomp on Linux, Seatbelt on macOS

```
┌─ outside: the supervisor ──────────────────────────────────────┐
│  comide's loop and screen · model calls (almai)                 │
│  the real keys · a proxy that puts them on requests by host     │
│  the policy · the audit log · asking the person                 │
└──────────────┬─────────────────────────────────────────────────┘
               │ one tool call at a time
┌──────────────▼── inside: confined by porta ────────────────────┐
│  shell · edits · golemide's solve and its verify command        │
│  empty environment · only the project writable                  │
│  network only through the supervisor's proxy · placeholder keys │
└────────────────────────────────────────────────────────────────┘
```

Running a whole agent inside a sandbox means handing it the model's API key, and then
every command the model asks for can read that key. aitrium draws the line at the tool
call instead. The agent's loop stays outside with the keys. What the model asks to run
goes inside, one call at a time, and sees a placeholder where the key would be.

## Why another one

Cloudflare OS, OpenShell and nono already keep keys away from agents. aitrium's
differences:

- **It runs where the code is.** One static binary on a laptop, in CI, or inside a
  container, with no daemon and no cloud account.
- **The kernel enforces it.** The limits don't depend on the agent choosing to follow them.
- **Refusals are answers.** When porta refuses something, the refusal goes back to the model
  as the tool's result, with the grant that would allow it. The model can take another path,
  or ask the person.
- **Both costs are measured.** Every release reports tasks solved on Terminal-Bench 2.0
  and attacks contained, on the same runs.

## License

MIT or Apache-2.0, at your option.
