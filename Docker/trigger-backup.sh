#!/bin/bash
#
# Trigger an Immediate Backup Job
#
# Used by the docker container

set -uo pipefail

if [ "${DEBUG:-false}" == "true" ]; then
  set -x
fi

: "${CONFIG_DIR:=/config}"
: "${TOKEN_PATH:=${1-$CONFIG_DIR/.bedrockifierToken}}"

echo Using Token Path: ${TOKEN_PATH}
if [ ! -e "${TOKEN_PATH}" ]; then
  echo Token file not found.
  exit 1
fi

curl -v http://127.0.0.1:8080/start-backup -H "Authorization: Bearer $(cat ${TOKEN_PATH})"
exit $?
