#!/usr/bin/env bash
#
# Outputs configuration variables for Github Actions and Local Builds

arch=$1

swift_base="swift"
swift_version="5.5.2"
if [ "$arch" == "arm64" ]; then 
    swift_base="swiftarm/${swift_base}"
    swift_version="${swift_version}-ubuntu-21.04"
fi

set-env swift_base
export swift_version
echo Using Swift Image: $swift_base
echo Using Swift Version: $swift_version