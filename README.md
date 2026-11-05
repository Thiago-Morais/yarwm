# YARWM

**Yet Another Random Wallpaper Manager** — pronounced "YARM".

A lightweight wallpaper rotation daemon and CLI for Linux (built around
Hyprland + awww, but backend-agnostic). It picks wallpapers with a
weighted-random algorithm: a `quality` tag filters the pool, a `frequency`
tag weights it, and screen-time history keeps recently seen images from
coming back too soon.

The full design lives in [`docs/spec.md`](docs/spec.md).

> **Status:** pre-alpha — repository scaffolding only, nothing usable yet.

## Getting started

### 1. Install the prerequisites

You need Docker (with the Compose and Buildx plugins), `make` and `git`.
No Go install is needed. For example, on Arch-based distros:

```sh
sudo pacman -S --needed docker docker-compose docker-buildx make git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"    # then log out and back in
```

Check it with `docker compose version`.

### 2. Clone and run the checks

```sh
git clone https://github.com/Thiago-Morais/yarwm
cd yarwm
make check
```

The first run builds the dev container, which takes a few minutes; later
runs reuse it. A passing run ends with `0 issues.` from golangci-lint and
`ok  github.com/Thiago-Morais/yarwm` from the tests.

### 3. Build and run the binary

```sh
make build
./build/yarwm version    # e.g. "yarwm v0.1.0", or a commit hash before the first tag
./build/yarwm help
```

`build/` and `.cache/` should be owned by your user (`ls -l build .cache`).

### 4. (Optional) Look around inside the container

On the host:

```sh
make shell
```

Then, inside the container's shell:

```sh
go version               # the pinned Go toolchain
golangci-lint version    # the pinned linter
exit
```

### Testing someone's branch

```sh
git fetch origin
git switch feature/<name>
make check
make build && ./build/yarwm version
```

CI runs the same checks on every push — see the repo's **Actions** tab.

## Development environment

Every Go command runs inside a pinned Docker container, so every
contributor uses the exact same Go and golangci-lint versions (pinned in
[`docker/dev/Dockerfile`](docker/dev/Dockerfile), kept current by
Dependabot). On the host you only need Docker (with the Compose plugin),
`make` and `git` — no local Go install.

```sh
# setup
make dev-image            # build the dev image (the toolchain), runs automatically
make shell                # interactive shell inside the dev container

# write
make fmt                  # go fmt ./...
make run ARGS="version"   # compile and run from source
make debug ARGS="version" # Delve debugger in this terminal (see "Debugging")
make debug-server         # Delve for your editor to attach to (see "Debugging")

# verify
make test                 # go test ./...
make vet                  # go vet ./... (lint already includes it)
make lint                 # golangci-lint (config: .golangci.yml)
make fmt-check            # fail if anything needs formatting
make check                # fmt-check + lint + test — what CI runs

# ship
make build                # compile ./build/yarwm

# tidy
make clean                # remove build/
make clean-cache          # remove .cache/ (re-downloaded on next run)
```

Each target is a thin wrapper around `docker compose run --rm dev ...`, so
anything not covered works directly, e.g.:

```sh
docker compose run --rm dev go list ./...
```

Every `make` target first brings the image up to date, silently
(`docker compose build --quiet`, about a second when nothing changed).
When calling `docker compose run` directly, run `make dev-image` first if
`docker/dev/Dockerfile` has changed. Go's module and build caches are
written to `.cache/` inside the repo (gitignored), so they're ordinary
files you can see and delete.

**Version:** the git tag is the version. `make build` injects
`git describe --tags --always --dirty` from the host; the container never
calls git itself. See [`CONTRIBUTING.md`](CONTRIBUTING.md#versioning).

**File ownership:** the container runs as your host user (the Makefile
passes `id -u`/`id -g`), so everything it writes into the repo belongs to
you. When calling `docker compose` directly without `make`, it falls back
to UID/GID 1000 unless `DEV_UID`/`DEV_GID` are set.

**CI:** `.github/workflows/check.yml` runs `make check` and a build smoke
test in the same container on every push and pull request.

## Editor setup

Editors stay on the host; the repo ships settings that override your
global ones while you work here:

- **`.editorconfig`** — indentation, line endings, final newline, trailing
  whitespace for every file type. Neovim reads it natively; VS Code needs
  the EditorConfig extension.
- **`.nvim.lua`** — project-local Neovim settings: gopls is configured to
  match the project's checks, files are formatted on save with the same
  formatters as `make fmt` (through conform.nvim if you have it, otherwise
  gopls for Go), and an nvim-dap entry attaches to the containerized
  debugger (see "Debugging"). Neovim only loads it if your config sets
  `vim.o.exrc = true`, and asks you to `:trust` it first. `make` targets
  are meant for a regular terminal.

`gopls` and other Go editor tooling are optional and need a Go toolchain
on the host; building, testing, linting and debugging never do.

## Debugging

The debugger is [Delve](https://github.com/go-delve/delve), run inside the
dev container as `go tool dlv` — its version is pinned in `go.mod` and kept
current by Dependabot, so there's nothing to install.

### In the terminal

```sh
make debug ARGS="version"
```

This builds yarwm with debug info and stops before `main` runs, at a
`(dlv)` prompt:

```
(dlv) break main.main      # breakpoint at the start of main()
(dlv) continue             # run until a breakpoint
(dlv) next                 # step over
(dlv) step                 # step into
(dlv) print subcommand     # inspect a variable
(dlv) quit
```

### From Neovim (nvim-dap)

Needs [nvim-dap](https://github.com/mfussenegger/nvim-dap) and the
`.nvim.lua` above. Delve itself runs in the container, so no host `dlv`
(e.g. from Mason) is used.

1. In a terminal, start the debug server (it waits for the editor):

   ```sh
   make debug-server ARGS="version"
   ```

2. In Neovim, set breakpoints, start debugging (`:DapContinue`) and pick
   **yarwm: attach to make debug-server**. The program runs until it hits a
   breakpoint; stop the session to end both.

The server listens on `127.0.0.1:2345` only. To use another port, set
`DEBUG_PORT` in your environment — the Makefile and `.nvim.lua` both read
it.

Stepping into the Go standard library or a dependency shows the frame but
can't open the file: those sources exist only inside the container.

## Branching

This repo uses **gitflow** — see [`CONTRIBUTING.md`](CONTRIBUTING.md).
In short: work happens on `feature/*` branches merged into `dev` through
pull requests; releases are cut on `release/*` branches and merged into
`main`, which only ever holds released versions.
