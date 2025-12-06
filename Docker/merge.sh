#!/usr/bin/env bash
#
# Merges amd64 and arm64 into a single tag

do_semver=0
args=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --semver)
            do_semver=1
            shift
            ;;
        --*)
            echo "Unknown option"
            exit 1
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

tag=${args[0]}
sourceTag=${args[1]}

echo Running 'docker buildx imagetools create'
docker buildx imagetools create \
    -t $tag \
    $sourceTag-amd64 \
    $sourceTag-arm64 \

if [ "${do_semver}" = "1" ]; then
    components=($(echo $tag | tr "." "\n"))
    minor_tag=${components[0]}.${components[1]}
    docker buildx imagetools create \
        -t $minor_tag \
        $sourceTag-amd64 \
        $sourceTag-arm64 \

    major_tag=${components[0]}
    docker buildx imagetools create \
        -t $major_tag \
        $sourceTag-amd64 \
        $sourceTag-arm64 \

fi
