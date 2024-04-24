#!/bin/bash
#
# Backup Job Healthcheck
#
# Used by the docker container

set -uo pipefail

if [ "${DEBUG:-false}" == "true" ]; then
  set -x
fi

: "${CONFIG_DIR:=/config}"

if [ ! -e "${CONFIG_DIR}/.service_is_healthy" ]; then
  exit 1
fi

exit 0
