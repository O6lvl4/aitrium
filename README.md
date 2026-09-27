<p align="center">A world for coding agents to work in: the agent runs its tools in a sandbox the kernel enforces,<br>and the keys stay outside it.</p>
<p align="center"><a href="README_ja.md">日本語</a></p>

> Izanagi and Izanami stood on the Floating Bridge of Heaven and stirred the formless sea
> with a jewelled spear. The brine that dripped from its tip hardened into the first island,
> Onogoro. They stepped down onto it, raised a pillar, and began the work of making a country.

onogoro makes that first island for an agent. The one who makes it decides where the land
ends and the sea begins: what may be written, what may be read, which hosts may be reached.
The agent works on the island. The keys never land there.

**Status: phase 1 of [the plan](docs/design.md).** The line is drawn with the binaries
that exist: every command comide runs goes through porta, and no key goes in with it
except to golemide, which still calls the model itself (almide/porta#37 closes that).

```sh
onogoro                       # comide's conversation, every tool's command confined
onogoro -p "fix the tests"    # one request; any of comide's arguments work
```

It needs comide (0.5.0 with `--runner`, O6lvl4/comide#2) and porta on `PATH`, or
`ONOGORO_COMIDE` / `ONOGORO_PORTA` pointing at them. `ONOGORO_NET=none` closes the network
to commands; `onogoro --help` says the rest.

| What comide runs | Writes | Network | Keys |
|---|---|---|---|
| `read` (hew, git status) | a scratch dir | none | none |
| `shell` (what the model wrote) | the project, the scratch dir | open (`ONOGORO_NET`) | none |
| `solve` (golemide) | the project, the scratch dir | open | the model keys, by name |

Every call also has the files the keys live in (`~/.config/golemide/.env`, …) closed to
reads, `TMPDIR` set to the scratch dir, and credential stores closed by porta's preset.

## What it is

onogoro puts two existing tools together. Both stay products of their own:

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
every command the model asks for can read that key. onogoro draws the line at the tool
call instead. The agent's loop stays outside with the keys. What the model asks to run
goes inside, one call at a time, and sees a placeholder where the key would be.

## Why another one

Cloudflare OS, OpenShell and nono already keep keys away from agents. onogoro's
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
