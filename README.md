# Bedrockifier

[![CI Status](https://github.com/Kaiede/Bedrockifier/actions/workflows/swift.yml/badge.svg)](https://github.com/Kaiede/Bedrockifier/actions)
![Swift](https://img.shields.io/badge/Swift-5.5.2-brightgreen.svg?style=flat)
[![MIT license](http://img.shields.io/badge/License-MIT-brightgreen.svg)](http://opensource.org/licenses/MIT)

[![CI Status](https://github.com/Kaiede/Bedrockifier/actions/workflows/docker.yml/badge.svg)](https://github.com/Kaiede/Bedrockifier/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/kaiede/minecraft-bedrock-backup.svg)](https://hub.docker.com/r/kaiede/minecraft-bedrock-backup)
[![GitHub Issues](https://img.shields.io/github/issues-raw/kaiede/Bedrockifier.svg)](https://github.com/kaiede/Bedrockifier/issues)

A multi-purpose tool for working with Minecraft Java and Bedrock world backups, including a manual tool, a backup service, and a dockerized contianer for making backups of the Minecraft [Bedrock](https://hub.docker.com/r/itzg/minecraft-bedrock-server) and [Java](https://hub.docker.com/r/itzg/minecraft-server) docker containers provided by itzg.

### Features

- Bedrock backups use the .mcworld format, meaning Vanilla worlds can be imported using any Bedrock client.
- Java backups use the same .zip backup format as the game client, making them easier to work with.
- Takes snapshots while the server is running.
- Supports trimming backups to limit disk space usage.

### Usage

Detailed instructions are in the [Wiki](https://github.com/Kaiede/Bedrockifier/wiki).

### Release Notes

Release Notes are available on [GitHub](https://github.com/Kaiede/Bedrockifier/releases).

### Credits

This was built in part by understanding how itzg/mc-backup works for Java, and is offered under similar license: https://github.com/itzg/docker-mc-backup 

Older source history for the docker container can be found at https://github.com/Kaiede/docker-minecraft-bedrock-backup
