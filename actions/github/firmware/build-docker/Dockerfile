FROM ubuntu:24.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
# PEP 668: allow pip in system Python (acceptable here: build-only image)
ENV PIP_BREAK_SYSTEM_PACKAGES=1

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
    cmake \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies (cryptography for ECDSA signing, boto3 for AWS KMS)
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Set the working directory inside the container
WORKDIR /workspace

# Define a default command to simply execute bash
CMD ["/bin/bash"]
