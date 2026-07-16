### Validating Changes

Unit tests can do the work to make sure basic functionality isn't impacted:

`swift test` 

However, to get better coverage of the different configurations people might use in practice, it helps to run a variety of configurations. With a little effort, it's possible to use the examples in this repository directly as end-to-end tests. From the root directory, run these steps.

```
# Build a docker image.
./build-docker

# Tag the image to match the examples, or modify the examples to match the tag
docker tag <generated image tag> kaiede/minecraft-bedrock-backup:latest

# Go to the example 
cd Examples/<example>
mkdir -p data/backups data/public

# Bring up the stack
docker compose up
```

The current examples all kick off an initial backup after a 60 second delay. This lets you catch the most egregious integration problems quickly. But since this brings up a full minecraft stack, you can login, logout, and generally play around to ensure that logic works. 

The most important examples to check are:

* bedrock-itzg-ssh-interval
* bedrock-itgz-ssh-login
* java-itzg-rcon-lastlogout
* java-itzg-ssh-lastlogout

This ensures that Java + Bedrock are tested, as well as Interval + Event-Based schedules.

Note: Podman can be used for testing here, but podman compose doesn't seem to fully support dependencies that are used in the compose examples. So it will not wait for the server to be healthy before it starts the backup service, and may kick off the backup service first.
