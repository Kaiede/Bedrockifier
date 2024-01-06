#!/usr/bin/env bash
#
# Merges amd64 and arm64 into a single tag

tag=$1

echo Running 'docker buildx imagetools create'
docker buildx imagetools create \
    -t $tag \
    $tag-amd64 \
    $tag-arm64 \
