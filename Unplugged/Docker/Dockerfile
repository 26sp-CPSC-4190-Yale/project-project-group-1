FROM swift:6.0
WORKDIR /app

# Copy shared package (dependency)
COPY UnpluggedShared/ ./UnpluggedShared/

# Resolve dependencies first (cached unless Package.swift/resolved change)
COPY UnpluggedServer/Package.swift UnpluggedServer/Package.resolved* ./UnpluggedServer/
WORKDIR /app/UnpluggedServer
RUN swift package resolve

# Now copy source and tests, then build
COPY UnpluggedServer/Sources/ ./Sources/
COPY UnpluggedServer/Tests/ ./Tests/
RUN swift build -c release

CMD [".build/release/UnpluggedServer", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
