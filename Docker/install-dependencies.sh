#!/bin/bash
#
# Make
set -xeuo pipefail

apt update

if [ "${IMAGEVARIANT}" == "slim" ]; then
    apt install -y curl
else
    apt install -y ca-certificates curl

    # Docker Repo
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    tee /etc/apt/sources.list.d/docker.sources <<EOF | sed 's/^        //'
        Types: deb
        URIs: https://download.docker.com/linux/ubuntu
        Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
        Components: stable
        Architectures: $(dpkg --print-architecture)
        Signed-By: /etc/apt/keyrings/docker.asc
EOF

    # Docker packages
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
fi

apt clean
rm -rf /var/lib/apt/lists/*