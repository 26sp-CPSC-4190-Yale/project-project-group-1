# syntax=docker/dockerfile:1.7

FROM swift:6.0
WORKDIR /app

# Copy manifests first so dependency resolution and dependency compilation stay
# cached unless package files change.
COPY UnpluggedShared/Package.swift ./UnpluggedShared/
COPY UnpluggedServer/Package.swift UnpluggedServer/Package.resolved ./UnpluggedServer/
WORKDIR /app/UnpluggedServer
RUN swift package resolve

# Precompile package dependencies with tiny placeholder targets. The placeholder
# sources are removed before real sources are copied in, but the compiled
# dependency artifacts remain available to the final build layer.
RUN mkdir -p ../UnpluggedShared/Sources/UnpluggedShared ../UnpluggedShared/Tests/UnpluggedSharedTests Sources/UnpluggedServer Tests/UnpluggedServerTests \
    && printf 'public enum DockerBuildCacheSeed {}\n' > ../UnpluggedShared/Sources/UnpluggedShared/DockerBuildCacheSeed.swift \
    && printf '// Docker build cache seed.\n' > ../UnpluggedShared/Tests/UnpluggedSharedTests/DockerBuildCacheSeedTests.swift \
    && printf '@main struct DockerBuildCacheSeed { static func main() {} }\n' > Sources/UnpluggedServer/DockerBuildCacheSeed.swift \
    && printf '// Docker build cache seed.\n' > Tests/UnpluggedServerTests/DockerBuildCacheSeedTests.swift \
    && swift build -c release --product UnpluggedServer \
    && rm -rf ../UnpluggedShared/Sources ../UnpluggedShared/Tests Sources Tests

# Now copy only runtime sources and build the server. Tests are intentionally not
# copied for the production image.
COPY UnpluggedShared/Sources/ ../UnpluggedShared/Sources/
COPY UnpluggedServer/Sources/ ./Sources/
RUN mkdir -p ../UnpluggedShared/Tests/UnpluggedSharedTests Tests/UnpluggedServerTests \
    && printf '// Docker build cache seed.\n' > ../UnpluggedShared/Tests/UnpluggedSharedTests/DockerBuildCacheSeedTests.swift \
    && printf '// Docker build cache seed.\n' > Tests/UnpluggedServerTests/DockerBuildCacheSeedTests.swift \
    && swift build -c release --product UnpluggedServer \
    && rm -rf ../UnpluggedShared/Tests Tests

CMD [".build/release/UnpluggedServer", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
