FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install CMake >= 3.25 from Kitware official repository (apt provides only 3.22 on Ubuntu 22.04)
# Update system and install required build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    gcc-arm-none-eabi \
    libnewlib-arm-none-eabi \
    libstdc++-arm-none-eabi-newlib \
    binutils-arm-none-eabi \
    make \
    ninja-build \
    git \
    python3 \
    python3-pip \
    curl \
    gpg \
    zip \
    && curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ jammy main' > /etc/apt/sources.list.d/kitware.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        cmake \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies (cryptography for ECDSA signing, boto3 for AWS KMS)
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Set the working directory inside the container
WORKDIR /workspace

# Define a default command to simply execute bash
CMD ["/bin/bash"]
