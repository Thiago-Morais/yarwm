# Development environment for yarwm. This image is only the shared
# toolchain; yarwm itself ships as a plain static binary.
#
# The Go version is pinned here and in go.mod — bump both together.
FROM golang:1.27.3-trixie

# Run as a non-root user whose UID/GID match the host user, so files the
# container writes into the mounted repo stay owned by you.
ARG DEV_UID=1000
ARG DEV_GID=1000

RUN groupadd --gid "${DEV_GID}" dev \
 && useradd --uid "${DEV_UID}" --gid "${DEV_GID}" --create-home --shell /bin/bash dev

USER dev

# GOTOOLCHAIN=local   never auto-download a different Go version, so the
#                     pinned image is the only toolchain anyone builds with.
# GOFLAGS=-buildvcs=false
#                     Go never shells out to git; the Makefile injects the
#                     version string from the host instead (see version.go).
# GOMODCACHE/GOCACHE  live in .cache/ inside the mounted repo (gitignored),
#                     so the caches are plain visible files, not hidden
#                     Docker volumes. Remove them with `make clean-cache`.
ENV GOTOOLCHAIN=local \
    GOFLAGS=-buildvcs=false \
    GOMODCACHE=/workspace/.cache/go-mod \
    GOCACHE=/workspace/.cache/go-build

WORKDIR /workspace

CMD ["bash"]
