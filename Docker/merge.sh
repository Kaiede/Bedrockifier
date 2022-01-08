#!/bin/bash
#
# Merges the Manifests for 

$tag=$1

docker manifest $tag

docker manifest create $tag \
    --amend $tag-amd64 \
    --amend $tag-arm64 \

docker manifest push $tag