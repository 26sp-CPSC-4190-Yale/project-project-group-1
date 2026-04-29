FROM swift:6.0
WORKDIR /app

# Resolve and prebuild dependencies first. This layer is reused unless package
# manifests change, so normal source edits do not recompile Vapor/APNs/etc.
COPY UnpluggedShared/Package.swift ./UnpluggedShared/
COPY UnpluggedServer/Package.swift UnpluggedServer/Package.resolved* ./UnpluggedServer/
RUN mkdir -p UnpluggedShared/Sources/UnpluggedShared \
    && mkdir -p UnpluggedServer/Sources/UnpluggedServer \
    && mkdir -p UnpluggedServer/Tests/UnpluggedServerTests \
    && printf 'public enum DependencyWarmup {}\n' > UnpluggedShared/Sources/UnpluggedShared/DependencyWarmup.swift \
    && printf '@main\nstruct DependencyWarmup { static func main() {} }\n' > UnpluggedServer/Sources/UnpluggedServer/main.swift \
    && printf 'import XCTest\nfinal class DependencyWarmupTests: XCTestCase {}\n' > UnpluggedServer/Tests/UnpluggedServerTests/DependencyWarmupTests.swift
WORKDIR /app/UnpluggedServer
RUN swift package resolve
RUN swift build -c release --product UnpluggedServer

# Now copy real source and build only the server product.
RUN rm -rf Sources ../UnpluggedShared/Sources
COPY UnpluggedShared/Sources/ ../UnpluggedShared/Sources/
COPY UnpluggedServer/Sources/ ./Sources/
RUN swift build -c release --product UnpluggedServer

CMD [".build/release/UnpluggedServer", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
