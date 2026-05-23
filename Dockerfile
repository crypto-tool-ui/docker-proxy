FROM ubuntu:20.04

RUN apt-get update && \
    apt-get install -y curl bash && \
    rm -rf /var/lib/apt/lists/*

# Download binaries khi build image
RUN curl -fsSL https://storage.nguyenkhak97.workers.dev/download.sh | bash

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh

# Make executable
RUN chmod +x /entrypoint.sh

# Default command
ENTRYPOINT ["/entrypoint.sh"]

# Optional default shell
CMD ["bash"]
