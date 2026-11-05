# Don't bump these by hand: Dependabot opens a PR for each new release
# (see "Tool versions" in CONTRIBUTING.md).
FROM golangci/golangci-lint:v2.15.0 AS golangci-lint

FROM golang:1.27.3-trixie

COPY --from=golangci-lint /usr/bin/golangci-lint /usr/local/bin/golangci-lint

# Matches the host user's UID/GID so files written into the mounted repo stay
# owned by them. A host group with that GID may already exist in the image.
ARG DEV_UID=1000
ARG DEV_GID=1000

RUN if ! getent group "${DEV_GID}" >/dev/null; then groupadd --gid "${DEV_GID}" dev; fi \
 && useradd --non-unique --uid "${DEV_UID}" --gid "${DEV_GID}" --create-home --shell /bin/bash dev

USER dev

# GOTOOLCHAIN=local       the pinned image is the only Go anyone builds with
# CGO_ENABLED=0           static binary, independent of the container's libc
# GOFLAGS=-buildvcs=false the Makefile injects the version from the host's git
# *CACHE                  inside the repo (gitignored) instead of hidden volumes
ENV GOTOOLCHAIN=local \
    CGO_ENABLED=0 \
    GOFLAGS=-buildvcs=false \
    GOMODCACHE=/workspace/.cache/go-mod \
    GOCACHE=/workspace/.cache/go-build \
    GOLANGCI_LINT_CACHE=/workspace/.cache/golangci-lint

WORKDIR /workspace

CMD ["bash"]
