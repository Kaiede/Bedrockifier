#!/usr/bin/env bash
#
# Builds the docker backup service

set -euo pipefail

tag=${1:-dev}
COMMIT=${2:-main}
PUSH=${3:-nopush}
dockerRepo=kaiede/minecraft-bedrock-backup
dockerBaseTag=$dockerRepo:${tag}

TARGETOS='linux'
TARGETARCH=`arch`
TARGETVARIANT=''
if [ "$TARGETARCH" == "x86_64" ]; then
    TARGETARCH=amd64
fi
if [ "$TARGETARCH" == "aarch64" ]; then
    TARGETARCH=arm64
fi

#. Docker/configure.sh $arch

dockerTag=$dockerRepo:${tag}-${TARGETARCH}

docker build . -f Docker/Dockerfile \
    -t $dockerTag \
    --build-arg TARGETOS=${TARGETOS} \
    --build-arg TARGETARCH=${TARGETARCH} \
    --build-arg TARGETVARIANT="" \
#    --build-arg swift_base=${swift_base} \
