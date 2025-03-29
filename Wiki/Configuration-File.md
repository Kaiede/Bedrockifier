The configuration file for the backup service is a YAML file called `config.yml` that is put in your backups folder to control the service in further detail.

```
containers:
  bedrock:
    - name: <container name>
      ssh: <serverAddr>:<serverPort>
      password: <serverPassword>
      passwordFile: <serverPasswordYamlFile>
      worlds:
        - <world path>
        - …
      extras:
        - <folder path>
        - …
      prefixContainerName: <true/false>
  java:
    - name: <container name>
      ssh: <serverAddr>:<serverPort>
      rcon: <serverAddr>:<serverPort>
      password: <serverPassword>
      passwordFile: <serverPasswordYamlFile>
      worlds:
        - <world path>
        - …
      extras:
        - <folder path>
        - …
      prefixContainerName: <true/false>
schedule:
  daily: <time of day>
  interval: <interval>
  startupDelay: <interval>

  onPlayerLogin: <true/false>
  onPlayerLogout: <true/false>
  onLastLogout: <true/false>
  minInterval: <interval>
  runInitialBackup: <true/false>
trim:
  trimDays: <count of days>
  keepDays: <count of days>
  minKeep: <count of backups>
loggingLevel: [debug or trace]
ownership:
  chown: 1000:1001
  permissions: 644
```

### Containers

This section lists all the servers to be backed up, and informs the tool how to talk to docker, and where to find the worlds. It is split into `bedrock` and `java`. Put Bedrock servers under `bedrock` and Java servers under `java` and it will properly back each type up in the correct way.

In addition to backing up the worlds themselves, additional folders for the server can be backed up. The common use for this is wanting to back up log files or installed resource/behavior packs or mods. These get backed up as a separate “Container.extras” zip file next to the worlds themselves.

* `<container name>`: This is the name of the docker container to be backed up. Something like `minecraft_server` as an example. When using Docker to communicate with the server, it needs to match the name visible in `docker ps`, or the `container_name` setting in docker-compose.yml. If using the `ssh` or `rcon` option, this can be any name you like.

* `rcon` and `ssh`: These tell the backup service to use either RCON or SSH instead of Docker to connect to the Minecraft server. The address/port is in the form of 'hostname:port', e.g. 'minecraft:2222' for SSH, or 'minecraft:25575' for RCON. When using docker-compose, the hostname can be the service name given.

* `password` or `passwordFile`: One of these must be set if `rcon` or `ssh` is used. This is the password used to connect to the RCON/SSH server. When using `passwordFile`, it's expected to be a YAML file in the same format that itzg's Minecraft containers use. That is, a YAML file with a single root `password` key that has a string value with the password in it (`password: <password>`).

* `<world path>`: This is the internal path to the world folder you want to backup. For example, if you mapped `/opt/bedrock/server` to `/server` in your `docker-compose.yml`, then this path should be `/server/worlds/<MyWorldName>`

* `<folder path>`: For extras, this is any folder you want to backup that isn’t part of any world. Using an example where a Java server is mapped to `/server`, and you wanted to backup the logs and mods folders, you would simply add `/server/logs` and `/server/mods` to the list under **extras**.

* `prefixContainerName`: When true, it will prefix `name` to the backup files. This setting can be used to avoid collisions where different containers may use the same world name.

### Schedule

* `daily`: This can be used instead of `interval` to set a time of day to trigger a backup. It uses 24-hour time, so valid values are things like "02:30" for 2:30 AM or "23:00" for 11 PM. It relies on TZ being set properly for the container as it will default to UTC time if TZ is not set.

* `interval`: This is the timing on backups, specified in hours, minutes, or seconds. So you can use values like: `600s`, `60m` or `3h` to set how often the backup is kicked off. Cannot be used with `daily`.

* `startupDelay`: This delays the first backup after the container starts, specified in hours, minutes or seconds. This can be useful to give a server time to fully start up in the case of Java, or to just avoid an immediate backup when using `interval`.

* `onPlayerLogin`/`onPlayerLogout`/`onLastLogout`: Perform a backup when the specific event happens when set to true. So every time a player logs in, logs out, or the last player logs out, a backup can be fired. The last one is ideal for Java servers where a backup can easily take many seconds to complete even with an SSD, so avoiding running backups while players are connected can help. Unlike `interval` and `daily` backups, these only backup the container that fired the event.

* `minInterval`: Limit the frequency of backups, specified in hours, minutes, or seconds. Useful for limiting how often backups are fired by server events, but also impacts backups fired by `interval` (in case both are used), but not `daily`.

Good practice here would be to use a `daily` backup along with something like `onLastLogout` along with `minInterval` to have control over how many backups are generated during the day, but still get one good snapshot. Especially if you can run the daily backup before the files are uploaded to a different service or storage provider.

* `runInitialBackup`: Tells the service to run a backup when the service starts, rather than waiting for events or the backup interval. If `startupDelay` is set, it will perform the backup after the delay.

### Trim

Trimming backups allows you control how much disk space is used by backups by deleting old backups, and only keeping daily backups after a certain number of days.

It is controlled by the following settings:

* `keepDays`: This is how many days of backups to keep. Setting this to 14 days means no backups after 14 days are kept, unless kept by minKeep.

* `trimDays`: How many days to keep of backups before trimming them down. Setting this to 2 days, with a 3 hour backup interval means that for the last 2 days, you'll keep all the 3 hour backups. After 2 days, the backups will get trimmed down to just a single daily backup, up to the keepDays limit.

* `minKeep`: A minimum number of backups to keep. This is useful if you switch worlds on your server, as it will make sure you always have a couple backups of any world even if it hasn't been used in a while. This will override keepDays, and let you keep at least this many backups indefinitely.

### Logging Level

By default the service will log all messages, warnings, and errors. If looking to get a very noisy log, or trying to diagnose issues, you can add the below setting to your configuration to get at additional detail.

* `loggingLevel`: This can be set to `debug` or `trace` to enable extra logging for diagnostic purposes.

### Ownership

This is meant for the rare cases where files on disk need to be a very specific user and group, and/or have specific permissions. NAS devices being one example. It allows you to tell the service how to set ownership and permissions on the backups written to disk.

This functionality may break trimming of backups if it causes the service to no longer be able to have write permissions to the backups. Use with caution.

* `chown`: This sets the owner and group on backed up mcworld files. It works much like the `chown` command's argument, but only accepts ids, not names. **Using this requires the service to run as root which is not recommended.**

* `permissions`: Sets unix permissions for the backed up files. This is the standard POSIX bitmask in string form.
