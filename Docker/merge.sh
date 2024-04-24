#!/usr/bin/env bash
#
# Merges amd64 and arm64 into a single tag

tag=$1
sourceTag=$2

echo Running 'docker buildx imagetools create'
docker buildx imagetools create \
    -t $tag \
    $sourceTag-amd64 \
    $sourceTag-arm64 \
