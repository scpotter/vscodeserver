# vscodeserver

A self-hosted [code-server](https://github.com/coder/code-server) image with
[Claude Code](https://claude.com/claude-code) baked in — a browser-based VS
Code environment for driving Claude Code against your own repos, running as
one Docker container on a host you control.

This is the **host tier**: the Dockerfile and compose file that define the
machine, not any particular project you point it at. It carries no project
code and no secrets — what you actually work on lives in whatever you mount
or clone into the container separately.

## What's in the image

- `codercom/code-server` base image.
- Claude Code, installed via the native installer (sidesteps a Node/npm
  dependency).
- `infisical` and `shellcheck` CLIs, plus `uv`/`uvx` — all at system paths
  (`/usr/bin`, `/usr/local/bin`), not under `/home/coder`, so they survive
  even when `/home/coder` starts as a fresh, empty volume.
- Five VS Code extensions: `ms-azuretools.vscode-docker`,
  `ms-azuretools.vscode-containers`, `redhat.vscode-yaml`,
  `timonwong.shellcheck`, `mikestead.dotenv`.

## Why containerized, not a native install

Keeps the host itself disposable: Docker plus one container, with the actual
environment defined entirely in this Dockerfile. Rebuilding the host means
re-running this image, not remembering a list of manual steps. See
`Dockerfile` for the exact build.

## Persistence

Everything under `/home/coder` — Claude Code's auth and config, SSH keys,
your own repo clones, dotfiles — lives on a **named Docker volume** mounted
at `/home/coder`, not ephemeral container storage. Compose brings this up as
`vscode-claude` on port `8080`.

**A Dockerfile layer that writes under `/home/coder` only takes effect on an
empty volume.** Once the volume exists, it wins over anything the image
would place there on a later rebuild — worth knowing before assuming an
image change reaches a running deployment.

## Running it

1. Copy `.env.example` to `host_config.env` and fill in your own Infisical
   instance URL and project ID (see below). `host_config.env` is
   gitignored — never commit real values.
2. Create a secret named `TOKEN_SECRET` at path `/vscode/code-server/` in
   that Infisical project, holding your code-server password.
3. Create a Universal Auth machine identity in Infisical, read-only and
   scoped to that one path, and place its client ID/secret at
   `~/.secrets/infisical.env` (untracked, never in this repo) as
   `VSCODEHOST_CLIENT_ID` / `VSCODEHOST_CLIENT_SECRET`.
4. Run `./launch.sh`. It sources `host_config.env`, logs into Infisical,
   pulls the password, and brings the container up with
   `docker compose up -d --build`.

Run `launch.sh` on the **host**, not from inside the container it manages —
it recreates that container on every build.

## The `host_config.env` contract

This repo doesn't care where `host_config.env`'s values come from — hardcode
them by hand, or generate the file from your own private config store before
calling `launch.sh`. Either way, `launch.sh` only ever sees the bare
variables in `.env.example`:

- `INFISICAL_API_URL` — your self-hosted (or cloud) Infisical instance.
- `CORE_INFRA_PROJECT_ID` — the project ID (UUID) holding
  `/vscode/code-server/TOKEN_SECRET`.
- `HOST_SHARE_DIR` (optional) — a host directory to mount read-only in the
  container; see below.
- `CODER_HOME_DIR` (optional) — a host directory to hold the container's home
  instead of the `coder-home` named volume; see below.
- `COMPOSE_PROFILES`, `ESPDB_*` (optional) — the ESPHome Device Builder service;
  see below.

## Optional read-only host directory

Compose mounts a host directory into the container, read-only, at
`/mnt/host-share`. By default that is the empty `./host-share` directory in
this repo, which does nothing. Set `HOST_SHARE_DIR` in `host_config.env` to
point it at a directory of your own — for example a tmpfs directory under
`/run` that a host-side process renders files into — and the container can read
them but never change them. The directory must exist before the container
starts (otherwise Docker creates it owned by root), and the files in it must be
readable by the container's `coder` user (uid 1000). The mount takes effect
when `launch.sh` recreates the container.

## Optional host directory for the home

The container's home, `/home/coder` — Claude Code's login and settings, SSH
keys, your clones — persists across rebuilds. By default it lives in the
`coder-home` named volume. Set `CODER_HOME_DIR` in `host_config.env` to a host
directory to keep it there instead, for example so a host-side process can
write into your workspace; a named volume lives under `/var/lib/docker`, which
only root can traverse.

The directory must exist before the container starts and be owned by the
container's `coder` user (uid 1000). Unlike an empty named volume, a host
directory never receives the files the image puts under `/home/coder`, so on an
empty directory install Claude Code into the home yourself
(`curl -fsSL https://claude.ai/install.sh | bash` inside the container). To move
an existing home, stop the container and copy the volume's contents across with
owners, modes and links preserved before the first start.

## Optional ESPHome Device Builder

A second service, `espdb`, runs the ESPHome Device Builder dashboard beside the
editor. It is off unless the `espdb` compose profile is enabled
(`COMPOSE_PROFILES=espdb` in `host_config.env`). It builds from the working tree
the editor uses, mounted at the same path, so edits you have not pushed build. Like
code-server it uses host networking, because device discovery needs multicast; the
dashboard listens on 6052 and the remote-build peer link on 6055.

Settings, all in `host_config.env`:

- `ESPDB_VERSION` — the ESPHome release, used as the image tag. Pin it; the
  default is `latest`.
- `ESPDB_CONFIG_DIR` — the configuration directory, default
  `/home/coder/repos/esphome`.
- `ESPDB_DATA_DIR` — a host directory holding `cache` and `build` subdirectories
  (toolchains and build output), default `./espdb-data`. Create both before the
  first start, owned by uid 1000; otherwise Docker creates them owned by root and
  the service cannot write to them.
- `ESPDB_TRUSTED_DOMAINS` — comma-separated hostnames the dashboard accepts in the
  `Host` header. List names, not addresses, so a changed IP does not lock you out.
  A request addressed by a name or IP that is not listed is rejected.
- The dashboard login: set `ESPHOME_USERNAME` and `ESPHOME_PASSWORD` yourself, or
  let `launch.sh` fetch them from Infisical with `ESPDB_SECRET_PATH` (a folder in
  the project named by `SMARTHOME_SELFHOSTED_PROJECT_ID`) and the key names
  `ESPDB_USERNAME_KEY` / `ESPDB_PASSWORD_KEY` (default `TOKEN_NAME` /
  `TOKEN_SECRET`). `launch.sh` loads only those two keys and never prints them.

The Device Builder can commit to a git working tree it manages. If you edit the
same tree in the editor, turn its version history off in its settings before you
make any edit.

## Network exposure

Compose publishes `8080` on all of the host's interfaces, protected only by
the code-server password — plain HTTP, no TLS. That's a workable posture on
a trusted, segmented network; front it with your own reverse proxy and TLS
termination if you're exposing it more broadly. This repo doesn't do that
for you.
