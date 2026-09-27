# onogoro on ConoHa

AI staff who work around the clock need somewhere to live. ConoHa VPS is a good place for
them. This document covers what onogoro adds there, what was run on 2026-09-27, and what
is still open.

## Why ConoHa

An agent that works 24 hours a day is a process that never stops. That favours flat
prices over metered ones:

- **Flat monthly prices in yen.** Hourly billing stops at the monthly price. There is no
  charge for data transfer.
- **The agent tools are already there.** Startup scripts install Claude Code, n8n and Dify
  when a server is made.
- **An official MCP server** ([gmo-internet/conoha_vps_mcp](https://github.com/gmo-internet/conoha_vps_mcp)
  and the remote `https://api.conoha.jp/vps/mcp`). Through it, an agent can operate ConoHa
  itself.

What ConoHa does not have:

- no model API of its own
- no protection against the flip side of that MCP server: **an agent that can make a
  server can make a hundred**

The local MCP server gives the agent `conoha_post` and `conoha_delete_by_param` on any path
of the API. It also needs the API user's password in its environment. The remote server
uses OAuth, so it keeps the password out of the agent's hands, but the agent's reach is
still the whole account.

A stopped VPS is still billed, so the only way to stop paying is to delete. An agent that
makes servers therefore spends money until someone deletes them.

## What others do about the keys

| | Where the credentials live | What limits the agent |
|---|---|---|
| Cloudflare OS: Gatekeepers | in the Gatekeeper, one per service | narrow, resource-scoped APIs; asynchronous human approval of an action |
| Cloudflare Sandbox: Outbound Workers | at the egress, put on requests by host | allow and deny lists per instance |
| NVIDIA OpenShell: providers | in the gateway; the agent holds placeholders | approved endpoints |
| nono: phantom tokens | a supervisor; the agent holds a per-session token for a localhost proxy | domain allow-lists |
| **onogoro's harbor** | the `harbor` user on the same VPS | plans, server count and a monthly budget in yen, checked on every ask; porta keeps the agent from reaching ConoHa any other way |

The harbor is a Gatekeeper for ConoHa that runs where the agents run. The limits it
checks are the ones a person thinks in: yen a month, how many servers, which plans.

## One VPS

```
┌─ ConoHa VPS (Ubuntu 24.04) ────────────────────────────────────────────────────────────┐
│                                                                                         │
│  user harbor                        user staff                                          │
│  ┌──────────────────────────┐       ┌───────────────────────────────────────────────┐  │
│  │ onogoro harbor  :7707    │◀──────│ supervisor: onogoro → comide                  │  │
│  │ ConoHa API user (0600)   │ token │ model keys (0600) · one shift per role (timer)│  │
│  │ limits · audit.jsonl     │       │                                               │  │
│  └────────────┬─────────────┘       │   ┌─ worker, per tool call (porta) ─────────┐ │  │
│               │                     │   │ the role's workdir writable, nothing else│ │  │
│               ▼                     │   │ empty environment: no key                │ │  │
│  ConoHa API (compute, volumes)      │   │ network: open, or only the harbor's port │ │  │
│                                     │   └──────────────────────────────────────────┘ │  │
│                                     └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Three kinds of secret, three places:**
  - The ConoHa API user is readable only by `harbor`.
  - The model keys are readable only by `staff`, and only the supervisor uses them.
  - The harbor's token goes into workers. It buys what the limits allow and nothing more.
- **The harbor's API:** `GET /` says what the agent may do and what it has. It also has
  `GET/POST /servers`, `POST /servers/ID/stop|start` and `DELETE /servers/ID`, which
  deletes the boot volume too.
  - A refusal is a 403 whose body says why, and names the setting that would allow it
    (`ONOGORO_HARBOR_YEN_MONTH=5033`). The model reads it like any other tool result.
  - The harbor answers one request at a time, so two asks cannot both fit the same budget.
- **What the harbor refuses:**
  - a plan the person did not list
  - a server past the count
  - a month over the budget; stopped servers count against it, as ConoHa bills them
  - a name without the prefix
  - touching any server the harbor did not make
- **With `ONOGORO_NET=none`,** porta opens exactly one port to a command: the harbor's
  (`--allow-net 127.0.0.1:7707`).

## The staff

`deploy/conoha/staff/` holds the four roles from the proposal. Each role is two files:

- `ROLE.md`: its instructions, in Japanese.
- `ROLE.env`: its schedule, its network, whether it may use the harbor, and whose reports
  it reads.

A shift is `onogoro -p "$(cat ROLE.md)" --root /srv/staff/ROLE/work --yes`, run by a systemd
timer. `--yes` is safe here only because porta is there: nobody is around to answer the
permission prompt, so the kernel answers it.

| Role | When | Network | Harbor | Reads |
|---|---|---|---|---|
| research (リサーチ) | weekdays 07:00 | open | no | |
| sales (営業サポート) | weekdays, hourly 09–18 | none | no | |
| dev (開発支援) | weekdays 10:00, 15:00 | open | yes | |
| lead (まとめ役) | weekdays 18:30 | none | no | research, sales, dev |

The lead gets copies of the other roles' outboxes. It can read what they wrote, but it
cannot change their files.

## Setting it up

1. Make a ConoHa VPS (Ubuntu 24.04). Paste `deploy/conoha/startup.sh` as its startup
   script. The script installs the pieces below, closes every port but SSH, and creates the
   two users:
   - Almide and porta, from release binaries with checksums checked
   - golemide, comide, hew and onogoro, built from source
2. Over SSH, fill in two files:
   - `sudoedit /etc/onogoro/keys.env`: the model keys
   - `sudoedit /etc/onogoro/harbor.env`: the ConoHa API user, image, volume type, key pair,
     plans with their prices, and the limits
3. Run `sudo onogoro-staff enable`. It starts the harbor and one timer per role.

Keys never go in the startup script. ConoHa keeps the script, and anything on the server
that can reach the metadata service can read it back.

## What was run (2026-09-27)

These runs used the harbor's dry mode (`ONOGORO_HARBOR_DRY=1`). It keeps servers in its
state file and makes no calls to ConoHa. porta 0.6.16 and comide 0.5.0 were built from
their `main` branches.

- **`almide test`:** 11 tests in 4 files pass. They cover the policy, the request bodies
  ConoHa receives, and the worker's grants.
- **The harbor, driven with curl:**
  - A request without the token got 401.
  - A 4 GB server was made.
  - A second 4 GB server was refused as over budget, with the setting that would allow it.
  - A GPU plan was refused as not listed.
  - Deleting a server the harbor did not make was refused.
  - Stopping a server was allowed, and the answer said it is still billed.
  - Every ask was written to `audit.jsonl`.
- **The whole chain.** A stand-in model asked comide's `shell` tool for one command. comide
  ran it with the network closed, through onogoro and porta, with the harbor on:
  - The first server was made.
  - The second was refused, and the refusal reached the model as the tool's result.
  - `env` inside the worker showed no key: neither the model key nor the ConoHa password.
    Both were set in the supervisor's and the harbor's environments.
  - `https://example.com` could not be reached.

None of this has touched a real ConoHa account. The requests follow the paths and bodies in
GMO's MCP server.

## Open

- **A live run on ConoHa.** Four things are unverified:
  - the flavor names
  - the boot volume type
  - whether a deleted server's boot volume stays (and is billed)
  - whether `adminPass` can be random when a key pair is given
- **The harbor listens on every interface.** Almide's `http.serve` binds `0.0.0.0`. ufw and
  the token keep it closed, but a `serve` that binds `127.0.0.1` is what it should be. That
  needs an Almide issue.
- **golemide's key.** `solve` still gets the model key by name. almide/porta#37 (a
  credential broker in porta's proxy) is the fix, as in [the design](design.md).
- **The model call leaves the country.** The workers and the data stay on the VPS. What the
  model reads goes to the model's provider. "Nothing leaves Japan" needs a model hosted in
  Japan; see *Asks* below.
- **Staff that are not coding agents.** porta's WASM agent teams
  (`porta agent team.toml`) could run the research, sales and lead roles instead of comide:
  - Credentials stay on the host.
  - One budget covers the whole team.
  - Journals let a run resume.
  - Remote MCP tools take a host-only token, so the ConoHa remote MCP could be granted with
    a `before_tool_checks` policy in front of it.

  This is worth measuring against comide on the same roles.

## Asks of ConoHa

Things only ConoHa can do. Each makes the harbor smaller:

1. **API tokens with scope and quota:** limits on plans, server count and monthly spend,
   enforced by ConoHa itself. That is a harbor for everyone, and it covers the MCP server
   too.
2. **Stopped servers billed for disk only.** That would give a reason to stop an idle agent
   rather than delete it. It is also the answer to Cloudflare's scale-to-zero for staff who
   work only during the day.
3. **Approval by a person** for actions over a threshold, on the remote MCP server, as
   Cloudflare's Gatekeepers do.
4. **A model endpoint hosted in Japan** (GMO GPU Cloud). Then "the servers, the model and
   the invoice all in Japan, in yen" is true.
