# YARWM

**Yet Another Random Wallpaper Manager** — pronounced "YARM".

A lightweight wallpaper rotation daemon and CLI for Linux (built around
Hyprland + awww, but backend-agnostic). It picks wallpapers with a
weighted-random algorithm: a `quality` tag filters the pool, a `frequency`
tag weights it, and screen-time history keeps recently seen images from
coming back too soon.

The full design lives in [`docs/spec.md`](docs/spec.md).

> **Status:** pre-alpha — repository scaffolding only, nothing usable yet.

## Development environment

Every Go command runs inside a pinned Docker container, so every
contributor uses the exact same Go and golangci-lint versions (pinned in
[`docker/dev/Dockerfile`](docker/dev/Dockerfile), kept current by
Dependabot). On the host you only need Docker (with the Compose plugin),
`make` and `git` — no local Go install.

```sh
make shell                # interactive shell inside the dev container
make build                # compile ./build/yarwm
make run ARGS="version"   # go run with arguments
make test                 # go test ./...
make lint                 # golangci-lint (config: .golangci.yml)
make vet                  # go vet ./... (lint already includes it)
make fmt                  # go fmt ./...
make check                # fmt check + lint + test — run before merging
make clean                # remove build/
make clean-cache          # remove .cache/ (re-downloaded on next run)
```

Each target is a thin wrapper around `docker compose run --rm dev ...`, so
anything not covered works directly, e.g.:

```sh
docker compose run --rm dev go list ./...
```

The image is (re)built automatically before each run; unchanged layers
are cached, so after the first run this takes about a second. Go's module
and build caches are written to `.cache/` inside the repo (gitignored), so
they're ordinary files you can see and delete.

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
- **`.nvim.lua`** — project-local Neovim settings: `:make <target>` runs
  the Makefile, gopls is configured to match the project's checks, and Go
  files are formatted with gopls on save. Neovim only loads it if your
  config sets `vim.o.exrc = true`, and asks you to `:trust` it first.

`gopls` and other Go editor tooling are optional and need a Go toolchain
on the host; building, testing and linting never do.

## Branching

This repo uses **gitflow** — see [`CONTRIBUTING.md`](CONTRIBUTING.md).
In short: work happens on `feature/*` branches merged into `dev`; releases
are cut on `release/*` branches and merged into `main`, which only ever
holds released versions.
