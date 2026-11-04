# Thin wrappers around the dev container. Every target runs inside the
# pinned Go toolchain, so results match on every machine.
RUN := docker compose run --rm dev

.PHONY: shell build test vet fmt fmt-check check image

shell:
	$(RUN) bash

build:
	$(RUN) go build -o bin/yarwm .

test:
	$(RUN) go test ./...

vet:
	$(RUN) go vet ./...

fmt:
	$(RUN) gofmt -w .

# Fails if any file needs formatting (gofmt -l lists them).
fmt-check:
	$(RUN) sh -c 'unformatted="$$(gofmt -l .)"; if [ -n "$$unformatted" ]; then echo "needs gofmt:"; echo "$$unformatted"; exit 1; fi'

check: fmt-check vet test

image:
	docker compose build
