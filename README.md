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

Everything builds and runs inside a pinned Docker container, so every
contributor uses the exact same toolchain (**Go 1.27.3**). You only need
Docker with the Compose plugin on the host — no local Go install.

```sh
make shell     # interactive shell inside the dev container
make build     # compile ./bin/yarwm
make test      # go test ./...
make vet       # go vet ./...
make fmt       # gofmt -w on the whole tree
make check     # fmt check + vet + test (run before merging)
```

Each target is a thin wrapper around `docker compose run --rm dev ...`, so
anything not covered works directly, e.g.:

```sh
docker compose run --rm dev go run . --help
```

The first run builds the image; Go's module and build caches live in named
Docker volumes, so later runs are fast.

**File ownership:** the container runs as UID/GID 1000 by default so files
it creates in the repo belong to you. If your host user isn't 1000, set
`DEV_UID`/`DEV_GID` before building, e.g. in a `.env` file next to
`compose.yaml`:

```sh
DEV_UID=1001
DEV_GID=1001
```

then rebuild with `docker compose build`.

## Branching

This repo uses **gitflow** — see [`CONTRIBUTING.md`](CONTRIBUTING.md).
In short: work happens on `feature/*` branches merged into `dev`; releases
are cut on `release/*` branches and merged into `main`, which only ever
holds released versions.
