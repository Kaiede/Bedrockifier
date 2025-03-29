There's a couple of steps required to properly configure this service, since it integrates with both docker and the minecraft server containers you are running. You can find a full example of the configuration files in the `Docker/Examples` folder on GitHub.

* [Note File Locations](#note-file-locations)
* [Setup docker-compose.yml](#configure-docker-compose-file)
* [Configure Permissions](#configure-permissions)
* [Setup Backup Service (config.yml)](#configure-backup-service)
* [Run](#run)

### Note File Locations

Backups require access to three locations. Make a note of these.

* Your `docker.sock` file.
  * If you don't know how to look this up, run `echo $DOCKER_HOST` this will either be blank, or something like `/run/user/1000/docker.sock`, if it is blank, check to see if `/var/run/docker.sock` exists and use that.
* Your bedrock server folder.
  * This will either be a named volume, or a folder on the host. As an example, we will be using `/opt/bedrock/server`.
* Where you want to put backups.
  * You will create this yourself. It's recommended to use a host folder. As an example, we will be using `/opt/bedrock/backups`.

### Configure Docker Compose File

In your `docker-compose.yml` file where you configure your minecraft server, you will want to make sure your server container has a couple options set so that the container can be attached to and have commands issued to it:

```
    stdin_open: true
    tty: true
```

Once the options are set on your server container(s), you will want to add another service that will run the backups:

```
  backup:
    image: kaiede/minecraft-bedrock-backup
    container_name: minecraft_backup
    restart: always
    depends_on:
      - "bedrock_server"
    environment:
      TZ: "America/Los_Angeles"
    tty: true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/bedrock/backups:/backups
      - /opt/bedrock/server:/server
```

The service should always depend on all the bedrock servers listed in your `docker-compose.yml` file. We want to let the minecraft servers start before taking a backup on launch. It is recommended to set `container_name ` for each server that will be backed up for ease of configuration later.

In most cases, you only need to configure the timezone for the container, but there are more variables available. [A full list is available here](Docker-Variables).

* `TZ`: This sets the timezone. It is optional, but it will use GMT if not set.

> NOTE: BACKUP_INTERVAL is now part of the configuration file, and has been deprecated. It is currently still supported, but it is recommended to move to specifying the schedule in the configuration YAML.

For the volumes, they need to be configured as such:
* Map in `docker.sock`. The above example should work fine for when docker runs as root. When running rootless, take the value you found earlier and include it like so: `/run/user/1000/docker.sock:/var/run/docker.sock`
* Map in your backups folder. In our example, we put it at `/opt/bedrock/backups` on our host. It should always be mapped into `/backups` in the container.
* Map in each server folder. This can be mapped anywhere in the container, but we use `/server` above for simplicity.

Currently, `tty: true` is required to get the full logs from the service.

### Configure Permissions

In many cases, the default behavior of having the user and group set from your `/backups` folder will work fine and is recommended. The backups folder should be owned by an account with the ability to attach to docker containers, and be part of the docker group (ex. `me:docker`). See “Manage Docker as a non-root user” in the [post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/) documentation for Docker on how to do this.

#### Default Behavior

The service uses a tool called entrypoint-demoter to avoid running the service as root. By default it will automatically demote the service to the user and group that owns your backups directory.

In many cases you can use a regular user that has been added to the docker group (ex. me:docker). This is how I setup my own servers on Ubuntu VMs and similar hosts. It makes things easier when you want to restore backups or otherwise manage the backups manually, as you can do it as a non-root user. See “Manage Docker as a non-root user” in the [post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/) documentation for Docker on how to do this.

#### Overriding User/Group of the Backup Tool

In cases where you need to override the user and group that is picked for you by entrypoint-demoter. The user must be part of the docker group, or otherwise have access to attach to the server containers. This also will have problems when running Docker rootless. To do the override, set the UID and GID environment variables in your docker-compose.yml file.

### Configure Backup Service

Inside your backups folder, you will need to create a `config.yml` file. A quick overview is below, while [more detail is available here](Configuration-File)

> NOTE: The previous JSON format is still supported in backwards-compatibility, but it is recommended to switch to using YAML, which is more readable

```
containers:
  bedrock:
    - name: bedrock_server
      worlds:
        - /server/worlds/MyWorld
schedule:
  interval: 3h
trim:
  trimDays: 2
  keepDays: 14
  minKeep: 2
```

Containers has two sub-nodes, `bedrock` and `java`. Under each is a list of containers you want to backup. `name` is the name of the docker container and must match the one provided by `docker ps`, or `container_name` in your `docker-compose.yml` file. `worlds` is another list of paths to each world. This path is the backup container's file path to the world. So in the example above, `/opt/bedrock/server/worlds/MyWorld` will become `/server/worlds/MyWorld` in the config file.

Make sure to put each server under the correct heading, as doing live backups is slightly different for each, and the service needs to know which type it is working with.

> NOTE: The previous "servers" list is supported via backwards-compatibility, but has been deprecated. It's recommended you update to using the containers structure instead.

The schedule section is how you define the triggers that cause the service to backup your worlds. The simplest schedule is to just backup on an `interval`. This can be set to be in terms of seconds, minutes or hours. So `600s`, `60m` or `3h` are all valid ways to specify the interval. Other triggers can be a specific time of day, or player logins and logouts. A full set of details on scheduling options are [available here](Configuration-File#schedule)

The basic trim settings above will keep backups for 14 days, only keep 1 backup per day after 2 days, and always keep a minimum of 2 backups per world. Trimming is [discussed in detail here](Configuration-File).

### Run

Run `docker-compose up` once the above steps are done to verify via the console that the first backup is successful. Then you can stop the containers and restart them using `docker-compose start` to run them in the background like you normally would.

### Restoring Backups

See [Restoring Backups](Restoring-Backups)
