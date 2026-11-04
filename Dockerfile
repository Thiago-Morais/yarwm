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
 && useradd --uid "${DEV_UID}" --gid "${DEV_GID}" --create-home --shell /bin/bash dev \
 && mkdir -p /home/dev/go/pkg/mod /home/dev/.cache/go-build \
 && chown -R dev:dev /home/dev

USER dev

# GOTOOLCHAIN=local: never auto-download a different Go version, so the
# pinned image is the only toolchain anyone builds with.
ENV GOTOOLCHAIN=local \
    GOPATH=/home/dev/go \
    GOCACHE=/home/dev/.cache/go-build \
    PATH=/home/dev/go/bin:/usr/local/go/bin:${PATH}

WORKDIR /workspace

CMD ["bash"]
