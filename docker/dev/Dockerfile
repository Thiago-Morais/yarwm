# Development environment for yarwm. This image is only the shared
# toolchain; yarwm itself ships as a plain static binary.
#
# Build context is this directory (docker/dev/) and nothing is copied in:
# the repo is bind-mounted at runtime by compose.yaml.
#
# Pinned versions (see CONTRIBUTING.md, "Bumping tool versions"):
#   Go             here, go.mod, compose.yaml's image tag
#   golangci-lint  here — must be built with a Go at least as new as ours
FROM golangci/golangci-lint:v2.15.0 AS golangci-lint

FROM golang:1.27.3-trixie

COPY --from=golangci-lint /usr/bin/golangci-lint /usr/local/bin/golangci-lint

# Run as a non-root user whose UID/GID match the host user, so files the
# container writes into the mounted repo stay owned by you. The Makefile
# passes your `id -u`/`id -g`; an existing group with that GID is reused.
ARG DEV_UID=1000
ARG DEV_GID=1000

RUN if ! getent group "${DEV_GID}" >/dev/null; then groupadd --gid "${DEV_GID}" dev; fi \
 && useradd --non-unique --uid "${DEV_UID}" --gid "${DEV_GID}" --create-home --shell /bin/bash dev

USER dev

# GOTOOLCHAIN=local   never auto-download a different Go version, so the
#                     pinned image is the only toolchain anyone builds with.
# CGO_ENABLED=0       pure-Go static binary that runs on any Linux,
#                     independent of the container's libc.
# GOFLAGS=-buildvcs=false
#                     Go never shells out to git; the Makefile injects the
#                     version string from the host instead (see version.go).
# GOMODCACHE/GOCACHE/GOLANGCI_LINT_CACHE
#                     live in .cache/ inside the mounted repo (gitignored),
#                     so the caches are plain visible files, not hidden
#                     Docker volumes. Remove them with `make clean-cache`.
ENV GOTOOLCHAIN=local \
    CGO_ENABLED=0 \
    GOFLAGS=-buildvcs=false \
    GOMODCACHE=/workspace/.cache/go-mod \
    GOCACHE=/workspace/.cache/go-build \
    GOLANGCI_LINT_CACHE=/workspace/.cache/golangci-lint

WORKDIR /workspace

CMD ["bash"]
