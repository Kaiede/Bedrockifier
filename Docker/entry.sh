#!/bin/bash
#
# Backup Job Entrypoint
#
# Used by the docker container

# Execute
/usr/local/bin/entrypoint-demoter --match /backups --debug --stdin-on-term stop /opt/bedrock/bedrockifierd
