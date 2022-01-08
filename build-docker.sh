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

. Docker/render.sh $arch

dockerTag=$dockerRepo:${tag}-${arch}
dockerfile=$arch.dockerfile

docker build . -f Docker/$dockerfile \
    -t $dockerTag \
    --build-arg QEMU_CPU=max \
    --build-arg CACHEBUST=$(date +%s) \
    --build-arg COMMIT=${COMMIT} \
    --build-arg ARCH=${arch}
