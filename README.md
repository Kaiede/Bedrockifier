# BedrockifierCLI

A command-line tool 

### Usage

There are a set of commands available currently:

* pack
* unpack

These pack or unpack Bedrock worlds. They are intended to let you package up a world folder into a *.mcworld file, or vice versa.

* backup
* backupjob
* trim

These provide backup support for a running bedrock server. backup can perform a single backup task. backupjob can do the same using JSON to configure one or more backup tasks in situations where you are running multiple servers in different docker containers. Finally, trim allows manual trimming of the backups folder given specific rules. 

These commands can be used to setup a cron job or timer-based service using systemd to periodically backup and trim world data from bedrock dedicated servers.

Currently, this only works for certain docker containers like itzg/minecraft-bedrock-server, as it assumes it needs to attach to the container to safely save game data for backup. 

### Docker Container

Also available is a containerized version of this tool which is pre-configured to help run backups. 
