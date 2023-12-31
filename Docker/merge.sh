#!/usr/bin/env bash
#
# Merges amd64 and arm64 into a single tag

tag=$1

docker buildx imagetools create \
    -t $tag \
    $tag-amd64 \
    $tag-arm64 \

docker push $tag
