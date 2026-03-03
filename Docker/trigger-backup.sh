#!/bin/bash
#
# Trigger an Immediate Backup Job
#
# Used by the docker container

set -uo pipefail

if [ "${DEBUG:-false}" == "true" ]; then
  set -x
fi

: "${DEBUG:=false}"
: "${CONFIG_DIR:=/config}"
: "${TOKEN_PATH:=${1-$CONFIG_DIR/.bedrockifierToken}}"

if [ "${DEBUG}" == "true" ]; then
  echo "Using Token Path: ${TOKEN_PATH}"
fi

if [ ! -e "${TOKEN_PATH}" ]; then
  echo "Token file not found: ${TOKEN_PATH}" >&2
  exit 1
fi

TOKEN="$(cat "${TOKEN_PATH}")"
if [ -z "${TOKEN}" ]; then
  echo "Token file is empty: ${TOKEN_PATH}" >&2
  exit 1
fi

: "${BACKUP_URL:=http://127.0.0.1:8080/start-backup}"
URL="${BACKUP_URL}"

CURL_ARGS=(-sS -o /dev/null -w "%{http_code}")
if [ "${DEBUG}" == "true" ]; then
  CURL_ARGS=(-v -o /dev/null -w "%{http_code}")
fi

HTTP_CODE="$(curl "${CURL_ARGS[@]}" -H "Authorization: Bearer ${TOKEN}" "${URL}")"
CURL_STATUS=$?

if [ "${CURL_STATUS}" -ne 0 ]; then
  echo "Backup trigger failed (curl exit ${CURL_STATUS}) reaching ${URL}. If this keeps happening, restart the backup service container." >&2
  exit "${CURL_STATUS}"
fi

if [ "${HTTP_CODE}" -ge 200 ] && [ "${HTTP_CODE}" -lt 300 ]; then
  echo "Backup triggered successfully (HTTP ${HTTP_CODE})."
  exit 0
fi

echo "Backup trigger failed (HTTP ${HTTP_CODE})." >&2
exit 1
