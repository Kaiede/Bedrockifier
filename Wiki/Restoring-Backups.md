### Bedrock

For Bedrock servers, backups are stored as .mcworld files, which also happen to be zip files. It makes it possible to restore a backup doing something like this:

* docker-compose stop
* cd /opt/minecraft/bedrock-server/worlds
* mv MyWorld MyWorld.bak
* mkdir MyWorld
* cd MyWorld
* unzip /opt/minecraft/backups/MyWorld-<TIMESTAMP>.mcworld
* docker-compose start
* Delete MyWorld.bak once everything is confirmed working

In this example, /opt/minecraft/bedrock-server is the data folder for the minecraft server container, and /opt/minecraft/backups is the backup folder for the backup container.

### Java

Java backups follow the same format that the client uses for backups made of single-player worlds. It is a zip file with a single folder inside, with the name of the world. Inside the folder is the world contents.

* docker-compose stop
* cd /opt/minecraft/java-server/
* mv MyWorld MyWorld.bak
* unzip /opt/minecraft/backups/MyWorld-<TIMESTAMP>.mcworld
* docker-compose start
* Delete MyWorld.bak once everything is confirmed working

In this example, /opt/minecraft/java-server is the data folder for the Minecraft server container, and /opt/minecraft/backups is the backup folder for the backup container.

### Future Improvements

`bedrockifier-tool` can also pack and unpack worlds by itself. At the moment running it from the docker container is a catch-22 if the backup container is dependent on the server containers. You don't want the server to be running when restoring a backup, but the backup container depends on the servers so it can make the backup.

A future improvement here would be to figure out a process to make the restoration process less manual.
