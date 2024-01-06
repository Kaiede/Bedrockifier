#!/bin/bash
#
# Backup Job Healthcheck
#
# Used by the docker container

set -uo pipefail

if [ "${DEBUG:-false}" == "true" ]; then
  set -x
fi

: "${DATA_DIR:=/backups}"

if [ ! -e "${DATA_DIR}/.service_is_healthy" ]; then
  exit 1
fi

exit 0
