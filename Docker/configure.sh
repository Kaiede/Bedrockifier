#!/usr/bin/env bash
#
# Outputs configuration variables for Github Actions and Local Builds

arch=$1

swift_base="swift"
swift_version="5.6.2"
if [ "$arch" == "arm64" ]; then 
    swift_base="swiftarm/${swift_base}"
    swift_version="${swift_version}-ubuntu-jammy"
fi

GITHUB_ENV=${GITHUB_ENV:-}
if [ ! -z ${GITHUB_ENV} ]; then
    echo Exporting GitHub Variables
    echo "swift_base=${swift_base}" >> $GITHUB_ENV
    echo "swift_version=${swift_version}" >> $GITHUB_ENV
else
    echo Exporting Local Variables
    export swift_base
    export swift_version
fi

echo Using Swift Image: $swift_base
echo Using Swift Version: $swift_version
