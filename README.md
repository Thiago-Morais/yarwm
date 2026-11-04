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
contributor uses the exact same toolchain (**Go 1.27.3**). On the host you
only need Docker (with the Compose plugin), `make` and `git` — no local Go
install. Editor tooling (e.g. `gopls`) stays on the host, set up however
you like.

```sh
make shell                # interactive shell inside the dev container
make build                # compile ./build/yarwm
make run ARGS="version"   # go run with arguments
make test                 # go test ./...
make vet                  # go vet ./...
make fmt                  # go fmt ./...
make check                # fmt check + vet + test (run before merging)
make clean                # remove build/
make clean-cache          # remove .cache/ (Go caches; re-downloaded on next run)
```

Each target is a thin wrapper around `docker compose run --rm dev ...`, so
anything not covered works directly, e.g.:

```sh
docker compose run --rm dev go list ./...
```

The first run builds the image. Go's module and build caches are written
to `.cache/` inside the repo (gitignored), so later runs are fast and the
caches are ordinary files you can see and delete.

**Version:** the git tag is the version. `make build` injects
`git describe --tags --always --dirty` from the host; the container never
calls git itself. See [`CONTRIBUTING.md`](CONTRIBUTING.md#versioning).

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
