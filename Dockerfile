# syntax=docker/dockerfile:1

# Stage 1: build/check stage
# Use stable Swift toolchain for Linux CI checks.
FROM swift:6.2-noble AS build-check

WORKDIR /app

# Copy dependency manifests first to maximize Docker cache hit rate.
COPY Package.swift Package.resolved ./
RUN swift --version
RUN swift package resolve

# Copy sources after dependency resolution.
COPY . .

# Validate Linux build.
RUN swift build -c release

# Mark build success for minimal final image.
RUN echo "ok" > /tmp/build-check.ok

# Stage 2: minimal runtime image (for registry/storage efficiency)
FROM ubuntu:24.04

WORKDIR /app
COPY --from=build-check /tmp/build-check.ok /build-check.ok

CMD ["bash", "-lc", "echo 'linux build check: OK' && cat /build-check.ok"]
