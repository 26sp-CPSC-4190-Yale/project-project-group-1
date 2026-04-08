FROM swift:6.0
WORKDIR /app
COPY UnpluggedShared/ ./UnpluggedShared/
COPY UnpluggedServer/ ./UnpluggedServer/
WORKDIR /app/UnpluggedServer
RUN swift build -c release
CMD [".build/release/UnpluggedServer", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
