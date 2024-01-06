#!/bin/bash
#
# Backup Job Entrypoint
#
# Used by the docker container


# Configure User for SSH
uid=$(stat -c %u /backups)
[ -x /usr/sbin/useradd ] && useradd -m -u ${uid} u1 -s /bin/sh || adduser -D -u ${uid} u1 -s /bin/sh;

# Execute
/usr/local/bin/entrypoint-demoter --match /backups --debug --stdin-on-term stop /opt/bedrockifier/bedrockifierd
