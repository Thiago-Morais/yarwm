# Thin wrappers around the dev container. Every Go command runs inside the
# pinned toolchain, so results match on every machine. Only `docker`, `make`
# and `git` are needed on the host.
RUN := docker compose run --rm dev

# Version string comes from git on the host, e.g.
#   v0.1.0                    exactly on a tag
#   v0.1.0-3-g257be6f         3 commits after v0.1.0, at commit 257be6f
#   v0.1.0-3-g257be6f-dirty   ...with uncommitted changes
#   257be6f                   no tags yet
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null)
LDFLAGS := -X main.injectedVersion=$(VERSION)

.PHONY: shell build run test vet fmt fmt-check check clean clean-cache image

shell:
	$(RUN) bash

build:
	$(RUN) go build -ldflags "$(LDFLAGS)" -o build/yarwm .

# Pass arguments with ARGS, e.g. `make run ARGS="version"`.
run:
	$(RUN) go run -ldflags "$(LDFLAGS)" . $(ARGS)

test:
	$(RUN) go test ./...

vet:
	$(RUN) go vet ./...

# ./... skips directories starting with "." — so .cache/ is never touched.
fmt:
	$(RUN) go fmt ./...

# Fails if any file needs formatting (gofmt -l lists them).
fmt-check:
	$(RUN) sh -c 'unformatted="$$(gofmt -l $$(go list -f "{{.Dir}}" ./...))"; if [ -n "$$unformatted" ]; then echo "needs gofmt:"; echo "$$unformatted"; exit 1; fi'

check: fmt-check vet test

# Build output only — cheap to recreate.
clean:
	rm -rf build

# Go makes the module cache read-only on purpose, so a plain rm fails;
# restore write permission first. Runs on the host, no container needed.
clean-cache:
	if [ -d .cache ]; then chmod -R u+w .cache && rm -rf .cache; fi

image:
	docker compose build
