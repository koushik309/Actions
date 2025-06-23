FROM alpine:latest

# Install required tools
RUN apk add --no-cache curl jq git bash unzip

# Copy our orchestration script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]