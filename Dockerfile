# Use the official Ubuntu image as the base
FROM ubuntu:24.04

# Set non-interactive mode for apt-get to avoid prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install systemd and other required dependencies
RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    build-essential \
    net-tools \
    iproute2 \
    iputils-ping \
    wget \
    curl \
    grep \
    nano \
    fzf \
    dialog \
    vim \
    htop \
    sudo \
    unzip \
    openssh-server \
    adduser \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "export VISIBLE=now" >> /etc/profile

# Expose SSH port
EXPOSE 22

# Start systemd as the init system
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
