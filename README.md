<p align="center">A world for coding agents to work in: the agent runs its tools in a sandbox the kernel enforces,<br>and the keys stay outside it.</p>
<p align="center"><a href="README_ja.md">日本語</a></p>

> Izanagi and Izanami stood on the Floating Bridge of Heaven and stirred the formless sea
> with a jewelled spear. The brine that dripped from its tip hardened into the first island,
> Onogoro. They stepped down onto it, raised a pillar, and began the work of making a country.

onogoro makes that first island for an agent. The one who makes it decides where the land
ends and the sea begins: what may be written, what may be read, which hosts may be reached.
The agent works on the island. The keys never land there.

**Status: design.** Nothing here runs yet. [docs/design.md](docs/design.md) is the plan.

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
