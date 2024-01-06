#!/bin/bash
#
# Backup Job Entrypoint
#
# Used by the docker container


# Configure User for SSH
uid=$(stat -c %u /backups)
deluser bedrockifier
[ -x /usr/sbin/useradd ] && useradd -m -u ${uid} bedrockifier -s /bin/sh || adduser --disabled-login --uid ${uid} bedrockifier --shell /bin/sh;
export HOME=/backups

# Execute
/usr/local/bin/entrypoint-demoter --match /backups --debug --stdin-on-term stop /opt/bedrock/bedrockifierd
