#!/bin/bash
#
# Backup Job Entrypoint
#
# Used by the docker container

# Figure out which folder to match
FOLDER_TO_MATCH=/backups
if [ -d /data ]; then
  FOLDER_TO_MATCH=/data
fi

# Execute
/usr/local/bin/entrypoint-demoter --match $FOLDER_TO_MATCH --debug --stdin-on-term stop /opt/bedrock/bedrockifierd
