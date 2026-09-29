# aitrium on ConoHa VPS

A bare Ubuntu server on [ConoHa VPS](https://vps.conoha.jp/) with aitrium installed, for an
agent to work on. There is no container around it, so porta's Landlock, seccomp and user
namespaces meet the kernel directly, as in [host.yml](../../.github/workflows/host.yml).

| | |
| --- | --- |
| Server | `g2l-t-c3m2` (3 cores, 2 GB, hourly billing, 2,033 yen a month at most), Ubuntu 24.04, 2 GB swap |
| Users | `agent` for the work (key login, no sudo); `root` for administration |
| Network | The `IPv4v6-SSH` security group: SSH in, everything out |
| aitrium | The release `install.sh` installs, in `~agent/.local`, and the repository in `~agent/aitrium` |

## Checked on 2026-09-29

Ubuntu 24.04.3, kernel 6.8.0-90, LSMs `lockdown,capability,landlock,yama,apparmor`,
`kernel.apparmor_restrict_unprivileged_userns = 1`, aitrium v0.2.0:

| Check | Result |
| --- | --- |
| `scripts/host-check.sh` | 7 of 7 promises pass |
| `bench/containment/run.py --direct` | 6/6 contained |
| `bench/containment/run.py --direct --net-none` | 6/6 contained |
| `bench/containment/run.py --direct --control` (no aitrium) | 0/6 contained, as it should be |

## Use

The `conohavps` provider is the Aid-On fork, which is not on the Registry: build it and point
`dev_overrides` at it ([its README](https://github.com/Aid-On/terraform-provider-conohavps#セットアップ)).
The credentials of a ConoHa API user go in `env.sh`, which git ignores:

```sh
cat > env.sh <<'X'
export CONOHAVPS_TENANT_ID='...'
export CONOHAVPS_USER_ID='...'
export CONOHAVPS_PASSWORD='...'
X
chmod 600 env.sh
set -a; . ./env.sh; set +a

terraform init
terraform apply                  # -var flavor=g2l-t-c4m4 for 4 GB, -var aitrium_version=v0.2.0 to pin
ssh root@$(terraform output -raw ipv4) cloud-init status --wait
ssh agent@$(terraform output -raw ipv4)
```

On the server, as `agent`:

```sh
cd ~/aitrium && bash scripts/host-check.sh        # the seven promises, with a fake key
python3 bench/containment/run.py --direct         # the containment bench, no model
```

To work with a model, put its key where comide and golemide read it, `~/.config/golemide/.env`
(for example `CLOUDFLARE_ACCOUNT_ID=` and `CLOUDFLARE_API_TOKEN=`), then run `aitrium` in a
project. The file is outside what any confined command can read.

`terraform destroy` removes the server. ConoHa bills a server until it is deleted, stopped or not.
A new ConoHa account can hold one server; a second is refused until the limit is raised.
