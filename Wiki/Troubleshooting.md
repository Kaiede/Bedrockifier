Not everything goes perfectly, and some issues are hit in the process of getting your setup running. Here are some errors that have been reported with steps you can take to fix.

## The operation could not be completed. The volume is read only.

The service writes a couple of state files to the configuration folder. This includes a hidden file that marks the service as healthy, and a random 128-bit security token for the HTTP API. If the service tries to write to the config folder and cannot, you will see this error.

* Make sure the docker volume for the configuration is not read-only.
* Make sure the user the service is running as has write permission to the folder.

## SSH Connection Failure: NIOPosix.NIOConnectionError error 1.

This means the service couldn’t connect to the Minecraft docker container using SSH because the connection was refused. If the SSH port isn’t exposed to the backup container, or the Minecraft container isn’t working, you will get this error. It can also happen if you are using an old version of itgz’s Java or Bedrock container that doesn’t have support for SSH_ENABLE.

* Make sure both containers are part of the same docker-compose file, or part of the same docker VLAN.
* Expose port 2222 from the Minecraft container:

```
expose:
      - 2222
```

* Update the backup service docker configuration so that it depends on your Minecraft server being healthy before it starts.

```
depends_on:
      minecraft:
        condition: service_healthy
```

## Host key does not match existing key.

This happens when using SSH to talk to the minecraft server container, and the host key has changed from what it originally was. This can raise a flag that someone might have managed to change your network configuration without you being aware of it, but it can also just mean that a configuration change occurred.

If you encounter this, one of two things happened:
* Someone deleted the host key in the minecraft folder. Possibly because they tore down the server and started from scratch.
* A different host is being contacted than the one it thinks it is contacting. This can be because of a DNS change or switching names between docker containers.

You can remove the offending line from the `.authorizedKeys` file that is created by the service in your configuration directory. Next time the service runs a backup, it will accept and record the new key. No restart is necessary.
