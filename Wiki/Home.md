**Updated for v1.3.1**

There are a few steps to get started. In this guide, we will be using `docker-compose` to configure the docker containers as a group. If you are using something other than `docker-compose`, this guide may still be a useful reference, but will not have step-by-step instructions.

* Add backup container
* Configure the service's schedule and trim settings
* Tweak the configuration to backup each container

There are also full examples of a few different configurations available in the [Examples](https://github.com/Kaiede/Bedrockifier/tree/main/Examples) folder for reference.

# Configuring Docker Compose

First, we want to start with a docker-compose with the Minecraft server you want to use. itzg's containers are recommended, and you can find more details in the documentation available for those containers if you haven't already configured your server:

* [itzg's Minecraft Server Docs](https://docker-minecraft-server.readthedocs.io/en/latest/)
* [itzg's Bedrock Minecraft Server Readme](https://github.com/itzg/docker-minecraft-bedrock-server/blob/master/README.md)

Once you have a working Minecraft server, we will want to add the backup service to the composed docker application. For these examples, I'll have a minecraft server called 'public' that hosts a public SMP world called PublicSMP. The backup container needs to be configured to depend on your servers, have a timezone configured if you want your log timestamps to match your timezone, and map in the backup and minecraft folders the backup service will be working with. A simple example is below.

```
version: '3.7'

services:
  public:
    # ... my SMP config is here ...

  backup:
    image: kaiede/minecraft-bedrock-backup
    restart: always
    depends_on:
      # Make sure the minecraft service starts before the backup
      - "public"
    environment:
        # Without this, your log timestamps will be in the GMT timezone.
        TZ: "America/Los_Angeles"
    volumes:
      # (Optional) Map a configuration folder separately from the backups.
      # - /minecraft/backup-config:/config
      # Map your backups folder into /data
      - /minecraft/backups:/data
      # Map your server's data folder wherever you like
      - /minecraft/public:/public
```

# Configuring Backup Service

Now that the backup service is defined in the composed docker app, we need to configure the service by creating a `config.yml` and expose it to the service. If you map a folder or volume to `/config`, then the service will look for `/config/config.yml`. Otherwise it will fall back to `/data/config.yml`. This file must be provided

Inside that configuration file, we need to tell the service where to find the worlds it will backup, and how often to do the backups. All configuration files are made up of three sections: `containers`, `schedule` and `trim`.

```
containers:
  # Configures the containers to be backed up
schedule:
  # Configures the schedule for backups
trim:
  # Configures how backups are 'trimmed' to save disk space
```

First, let's look at `schedule` and `trim`. Later on we will look at the `containers` in [Configuring Each Container for Communication/Backup](#configuring-each-container-for-communicationbackup).

Schedules can be configured on intervals or trigged on events. Triggering on events requires using SSH or Docker to connect to the containers, but interval backups work with SSH, RCON or Docker connections. When triggering on events though, there are a few ways to limit the number of backups made to save CPU and disk space, and when using events, you can mix in a daily or interval backup on top. However, you cannot do daily _and_ interval backups at the same time. A few different examples:

```
# Every three hours
schedule:
  interval: 3h

# Every morning at 1AM. Schedule uses 24-hour time.
schedule:
  daily: 01:00

# Whenever a player logs in or out. Limit backups to once every 3 hours
schedule:
  onPlayerLogin: true
  onPlayerLogout: true
  minInterval: 3h

# Whenever the last player logs out, limited to every 3 hours. Plus at 1AM
schedule:
  onLastLogout: true
  minInterval: 3h
  daily: 01:00
```

The other mechanism to save disk space is trimming. Trimming tells the service when and how to delete old backups. The two key settings are `trimDays` and `keepDays`. `trimDays` tells the service how many days to keep all backups before trimming down to a single backup per day. `keepDays` tells the service how many days worth of backups to keep in total. `minKeep` forces the service to keep this many backups around for a given world, ensuring you keep a couple backups around even if they would normally age off entirely. This last setting is useful for worlds you may not have used in a while.

So for example:

```
trim:
  trimDays: 2
  keepDays: 14
  minKeep: 2
```

The above will keep all backups going back 2 days, and keep one backup per day going back 14 days after that. Any world will keep at least two backups. So if I have a world that I haven't used in a month, the last two backups kept from that world will always remain unless I remove them manually.

For more details on what the `config.yml` can do, see '[Configuration File](./Configuration-File)'.

# Configuring Each Container for Communication/Backup

There are multiple ways to configure a container starting with 1.3. SSH and RCON are recommended as they are neutral to the container platform you use. Docker can be used as well, but it is no longer recommended. SSH works with both Bedrock and Java, while RCON only works with Java. RCON also doesn't support listening to server events, and so only supports interval/daily backups. If you want full functionality, SSH is the top recommendation.

## SSH

SSH is only supported on itzg's containers at this point in time, and is supported on both Bedrock and Java. It was added to support the 1.3 release of Bedrockifier. By default, these containers will write out a `.env` and `.yaml` file into the /data volume with a random password that's regenerated each time the server starts. Bedrockifier can read the yaml file for you, so you don't have to set any password in your config files. On Java this is `.rcon-cli.yaml` (same as for RCON), while on Bedrock it is `.remote-console.yaml`

The first step is to enable SSH in your docker-compose.yml:

* Expose the `2222` port to other containers, but not the public network, if necessary.
* Set the `ENABLE_SSH` variable to true on the minecraft server container.
* Make note of the _name_ of the service in your compose.yml.

For example:

```
services:
  backup:
    # ... etc ...
    volumes:
      - /minecraft/public:/public

  public:
    image: itzg/minecraft-bedrock-server
    # ... etc ...
    expose:
      # This is a reminder that this port is exposed to other containers in this compose file.
      - 2222
    environment:
      ENABLE_SSH: "TRUE"
      # ... server variables ...
    # ... etc ...
```

The second step is to configure the container in your config.yaml for Bedrockifier. In the example above, we created a pair of services called `backup` and `public`, where `public` is our SMP server, and `backup` is our backup container. Docker compose will create host entries with those service names, allowing each container to identify one another using those service names, rather than IP addresses. So in this example, the SSH port of 2222 we exposed can be reached at `public:2222`. We can use the exported password from itzg's container as well, giving us an example Bedrock configuration that looks like this:

```
containers:
  bedrock:
    - name: bedrock_public
      # The hostname here is the name of the service in the compose YML.
      ssh: public:2222
      # itzg writes out the password as yaml to the root of /data
      passwordFile: /public/.remote-console.yaml
      worlds:
        - /public/worlds/PublicSMP
```

While an example Java container configured similarly looks like this:

```
containers:
  java:
    - name: java_public
      # The hostname here is the name of the service in the compose YML.
      ssh: public:2222
      # itzg writes out the password as yaml to the root of /data
      passwordFile: /public/.rcon-cli.yaml
      worlds:
        - /public/PublicSMP
```

## RCON (Java Only)

RCON uses the built-in RCON support of the Java Minecraft server. The limitation is that this only works for interval/daily backups, and cannot be used to backup the container based on when users log in or out. When using itzg's container, it will generate a random RCON password by default and write it out to `.rcon-cli.yaml` and `.rcon-cli.env`. We can use the yaml file to pass along the password to the backup service without having to enter it into our configuration files, and is highly recommended.

When configuring `docker-compose.yml`, we need to expose the RCON port to the backup service. Optionally, we can ensure RCON is enabled using the `ENABLE_RCON` variable when using itzg's container. It's enabled by default (unlike SSH), so it's not needed, but I like being explicit in my configuration files.

```
services:
  backup:
    # ... etc ...
    volumes:
      - /minecraft/public:/public

  public:
    image: itzg/minecraft-server
    # ... etc ...
    expose:
      # This port is the one used by RCON, _only_ expose it to other services in this compose file.
      - 25575
    environment:
      # RCON is enabled by default, but you can be explicit here.
      ENABLE_RCON: "TRUE"
      # ... server variables ...
    # ... etc ...
```

Here we have an example container based on the docker-compose above, where the "public" service is our SMP server, so we just need to tell Bedrockifier that for this container, this is the RCON server to connect to, and where to find the RCON password. Here, we use the `.rcon-cli.yaml` file that itzg's container writes out with the password to keep things a little simpler.

```
containers:
  java:
    - name: java_public
      rcon: public:25575
      passwordFile: /java_public/.rcon-cli.yaml
      worlds:
        - /java_public/PublicSMP
```

## Docker (Not Recommended)

Originally, Bedrockifier used Docker to communicate with the containers and issue commands. However, it is the most complex way to go about doing this of the three options. The above options were added to make things simpler and should be used unless there is a very good reason not to.

To get at the old documentation for Docker configuration, see '[Old Configuration](./Old-Configuration)'
