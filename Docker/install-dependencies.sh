#!/bin/bash
#
# Install dependencies from package manager
set -xeuo pipefail

apt update

apt install -y curl

apt clean
rm -rf /var/lib/apt/lists/*
