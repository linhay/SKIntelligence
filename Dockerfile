# 1
FROM swiftlang/swift:nightly-6.2-jammy

WORKDIR /app
COPY . .

# Build the Swift package (is a library product).
RUN swift --version
RUN swift package resolve
RUN swift build -c release

# No runtime entrypoint is required; this image is primarily for validating builds.
CMD ["bash", "-lc", "echo 'docker build image: OK' && swift --version"]