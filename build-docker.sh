#!/usr/bin/env bash
#
# Builds the docker backup service

set -euo pipefail

tag=${1:-dev}
COMMIT=${2:-main}
PUSH=${3:-nopush}
dockerRepo=kaiede/minecraft-bedrock-backup
dockerBaseTag=$dockerRepo:${tag}

arch=`arch`
if [ "$arch" == "x86_64" ]; then
    arch=amd64
fi
if [ "$arch" == "aarch64" ]; then
    arch=arm64
fi

#. Docker/configure.sh $arch

dockerTag=$dockerRepo:${tag}-${arch}

docker build . -f Docker/Dockerfile \
    -t $dockerTag \
    --build-arg arch=${arch} \
#    --build-arg swift_base=${swift_base} \
#    --build-arg swift_version=${swift_version}
