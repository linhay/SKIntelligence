# 1
FROM swiftlang/swift:nightly-6.2-jammy

WORKDIR /app

# 先复制依赖描述文件，利用 Docker 缓存
COPY Package.swift Package.resolved ./

# 解析依赖（只有依赖变化时这层才会失效）
RUN swift --version
RUN swift package resolve

# 再复制源代码（源代码改动不会影响依赖缓存）
COPY . .

# Build the Swift package (is a library product).
RUN swift build -c release

# No runtime entrypoint is required; this image is primarily for validating builds.
CMD ["bash", "-lc", "echo 'docker build image: OK' && swift --version"]