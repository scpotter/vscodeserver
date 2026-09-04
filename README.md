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
calling `launch.sh`. Either way, `launch.sh` only ever sees the two bare
variables in `.env.example`:

- `INFISICAL_API_URL` — your self-hosted (or cloud) Infisical instance.
- `CORE_INFRA_PROJECT_ID` — the project ID (UUID) holding
  `/vscode/code-server/TOKEN_SECRET`.

## Network exposure

Compose publishes `8080` on all of the host's interfaces, protected only by
the code-server password — plain HTTP, no TLS. That's a workable posture on
a trusted, segmented network; front it with your own reverse proxy and TLS
termination if you're exposing it more broadly. This repo doesn't do that
for you.
