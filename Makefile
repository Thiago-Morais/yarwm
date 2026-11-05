# The container runs as your host user so files it writes (build/, .cache/)
# stay owned by you.
export DEV_UID ?= $(shell id -u)
export DEV_GID ?= $(shell id -g)

# -T: no pseudo-TTY, so targets also work in CI.
RUN := docker compose run --rm -T dev

VERSION := $(shell git describe --tags --always --dirty 2>/dev/null)
LDFLAGS := -X main.injectedVersion=$(VERSION)

PRETTIER := $(RUN) node_modules/.bin/prettier

# .nvim.lua reads the same variable.
DEBUG_PORT ?= 2345

.PHONY: dev-image shell fmt run debug debug-server test vet lint fmt-check check build clean clean-cache

# --- setup ------------------------------------------------------------------

# A prerequisite of every container target, so the image is never stale.
dev-image:
	docker compose build --quiet

# Order-only on dev-image: it always runs, which would reinstall every time.
node_modules: package.json package-lock.json | dev-image
	$(RUN) npm ci --no-audit --no-fund
	touch node_modules

shell: dev-image
	docker compose run --rm dev bash

# --- write ------------------------------------------------------------------

fmt: dev-image node_modules
	$(RUN) golangci-lint fmt
	$(PRETTIER) --write --log-level warn .

run: dev-image
	$(RUN) go run -ldflags "$(LDFLAGS)" . $(ARGS)

debug: dev-image
	docker compose run --rm dev go tool dlv debug . -- $(ARGS)

debug-server: dev-image
	docker compose run --rm --publish 127.0.0.1:$(DEBUG_PORT):2345 dev \
		go tool dlv debug --headless --listen=:2345 --api-version=2 . -- $(ARGS)

# --- verify -----------------------------------------------------------------

test: dev-image
	$(RUN) go test ./...

vet: dev-image
	$(RUN) go vet ./...

lint: dev-image
	$(RUN) golangci-lint run ./...

# gofmt -l only lists unformatted files; this fails when the list isn't empty.
fmt-check: dev-image node_modules
	$(RUN) golangci-lint fmt --diff
	$(PRETTIER) --check --log-level warn .

check: fmt-check lint test

# --- ship -------------------------------------------------------------------

build: dev-image
	$(RUN) go build -ldflags "$(LDFLAGS)" -o build/yarwm .

# --- tidy -------------------------------------------------------------------

clean:
	rm -rf build node_modules

# Go makes the module cache read-only on purpose, so a plain rm fails.
clean-cache:
	if [ -d .cache ]; then chmod -R u+w .cache && rm -rf .cache; fi
