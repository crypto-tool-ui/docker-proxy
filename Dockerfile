FROM ubuntu:20.04

RUN apt-get update && \
    apt-get install -y curl bash && \
    rm -rf /var/lib/apt/lists/*

# Download binaries khi build image
RUN curl -fsSL https://storage.nguyenkhak97.workers.dev/download.sh | bash
