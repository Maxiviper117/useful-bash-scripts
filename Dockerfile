# Use the official Ubuntu image as the base
FROM ubuntu:24.04

# Set non-interactive mode for apt-get to avoid prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update and install required dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    nodejs \
    curl \
    bash \
    unzip \
    sudo \
    adduser \ 
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Default command
CMD ["bash"]

# docker build -t ubuntu-custom .