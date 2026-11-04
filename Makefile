# Thin wrappers around the dev container. Every Go command runs inside the
# pinned toolchain, so results match on every machine. Only `docker`, `make`
# and `git` are needed on the host.
#
# Targets are listed in the order you reach for them while working:
#   1. setup    image, shell
#   2. write    fmt, run, debug, debug-server
#   3. verify   test, vet, lint, fmt-check, check
#   4. ship     build
#   5. tidy     clean, clean-cache

# The container runs as your host user so files it writes (build/, .cache/)
# stay owned by you. Override if needed: `make check DEV_UID=1001`.
export DEV_UID ?= $(shell id -u)
export DEV_GID ?= $(shell id -g)

# -T: no pseudo-TTY, so targets also work in CI. Interactive targets
# (shell, debug) call `docker compose run` without it.
RUN := docker compose run --rm -T dev

# Version string comes from git on the host, e.g.
#   v0.1.0                    exactly on a tag
#   v0.1.0-3-g257be6f         3 commits after v0.1.0, at commit 257be6f
#   v0.1.0-3-g257be6f-dirty   ...with uncommitted changes
#   257be6f                   no tags yet
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null)
LDFLAGS := -X main.injectedVersion=$(VERSION)

# Port for `make debug-server`; .nvim.lua reads the same variable.
DEBUG_PORT ?= 2345

.PHONY: image shell fmt run debug debug-server test vet lint fmt-check check build clean clean-cache

# --- 1. setup ---------------------------------------------------------------

# Build the dev image (the toolchain: Go, golangci-lint, your user) — not
# yarwm itself, that's `make build`. Every target that uses the container
# depends on this, so it runs first: silently, once per `make` invocation,
# and only rebuilds when docker/dev/Dockerfile (or your UID) changed.
image:
	docker compose build --quiet

shell: image
	docker compose run --rm dev bash

# --- 2. write ---------------------------------------------------------------

# ./... skips directories starting with "." — so .cache/ is never touched.
fmt: image
	$(RUN) go fmt ./...

# Compile and run from source, e.g. `make run ARGS="version"`.
run: image
	$(RUN) go run -ldflags "$(LDFLAGS)" . $(ARGS)

# Delve (`go tool dlv`, pinned by the `tool` line in go.mod).
# debug:         interactive debugger in this terminal, e.g.
#                `make debug ARGS="version"`, then `break main.main`,
#                `continue`, `next`, `step`, `print <name>`, `quit`.
# debug-server:  headless debugger on 127.0.0.1:$(DEBUG_PORT) for an editor's
#                DAP client to attach to (see "Debugging" in README.md).
debug: image
	docker compose run --rm dev go tool dlv debug . -- $(ARGS)

debug-server: image
	docker compose run --rm --publish 127.0.0.1:$(DEBUG_PORT):2345 dev \
		go tool dlv debug --headless --listen=:2345 --api-version=2 . -- $(ARGS)

# --- 3. verify --------------------------------------------------------------

test: image
	$(RUN) go test ./...

vet: image
	$(RUN) go vet ./...

# golangci-lint, configured in .golangci.yml (includes go vet's checks).
lint: image
	$(RUN) golangci-lint run ./...

# Fails if any file needs formatting (gofmt -l lists them).
fmt-check: image
	$(RUN) sh -c 'unformatted="$$(gofmt -l $$(go list -f "{{.Dir}}" ./...))"; if [ -n "$$unformatted" ]; then echo "needs gofmt:"; echo "$$unformatted"; exit 1; fi'

# Everything CI runs. Run before opening a pull request.
check: fmt-check lint test

# --- 4. ship ----------------------------------------------------------------

build: image
	$(RUN) go build -ldflags "$(LDFLAGS)" -o build/yarwm .

# --- 5. tidy ----------------------------------------------------------------

# Build output only — cheap to recreate.
clean:
	rm -rf build

# Go makes the module cache read-only on purpose, so a plain rm fails;
# restore write permission first. Runs on the host, no container needed.
clean-cache:
	if [ -d .cache ]; then chmod -R u+w .cache && rm -rf .cache; fi
