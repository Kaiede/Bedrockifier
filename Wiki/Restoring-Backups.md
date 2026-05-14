## Restoring Backups

Bedrockifier now supports an assisted restore workflow in the main container image. The recommended workflow is the protected/scripted restore pattern shown in the updated example stacks:

* `Examples/bedrock-itzg-ssh/docker-compose.yml`
* `Examples/bedrock-itzg-ssh-multiple/docker-compose.yml`
* `Examples/java-itzg-ssh/docker-compose.yml`
* `Examples/java-itzg-rcon/docker-compose.yml`

In that pattern:

* the backup service mounts the backup volume read-write
* the backup service mounts server data read-only
* the restore helper mounts the backup volume read-only
* the restore helper mounts the destination server data read-write
* the restore helper uses the same `config.yml` as the backup service

This keeps the recommended workflow focused on one supported image and one documented restore path.

## Recommended Workflow

The examples include a `restore` command that reuses the backup image, but calling into Bedrockifier's restore flow:

```yaml
restore:
  image: kaiede/minecraft-bedrock-backup
  profiles:
    - restore
  entrypoint: ["/opt/bedrock/bedrockifier", "restore"]
```

Run restores with:

```bash
docker compose --profile restore run --rm restore
```

This tool loads your configuration, and walks you through the process. It will:

1. Ask you to choose a container/world when more than one target exists.
2. Show backups that match that target.
3. Confirm the selected restore target.
4. Replace the selected world with the chosen backup.
5. Reapply permissions to match the existing permissions.

### Operational Sequence

Before restoring:

1. Stop the Minecraft compose stack (this will stop both server and backup container)
2. Run the restore helper with the `restore` profile.
3. Confirm the restored world starts correctly.
4. Start your server stack again.

Example:

```bash
docker compose stop
docker compose --profile restore run --rm restore-menu
docker compose start
```

### Restore Environment Variables

A couple environment variables specific to restoring backups are provided if needed:

* `RESTORE_OWNER`
* `RESTORE_MODE`

These override the default logic, which should work in most cases. Details are available in [Docker Variables](https://github.com/Kaiede/Bedrockifier/wiki/Docker-Variables).

## Bedrock Notes

Bedrock backups are stored as `.mcworld` files. Restore targets are derived from the Bedrock world paths configured in `config.yml`, for example:

```yaml
containers:
  bedrock:
    - name: bedrock_public
      worlds:
        - /bedrock_public/worlds/PublicSMP
```

The restore helper will restore into the configured world path, not a hardcoded default.

## Java Notes

Java backups are stored as `.zip` archives with a top-level world folder. Restore targets are derived from the Java world paths configured in `config.yml`, for example:

```yaml
containers:
  java:
    - name: minecraft_public
      worlds:
        - /public/PublicSMP
```

The helper restores the selected `.zip` backup to the configured Java parent/world path.

## Multi-Server Notes

When `config.yml` contains more than one restore target, the helper prompts for the target before showing backups.

If multiple containers back up worlds with the same name, enable `prefixContainerName: true` so backup filenames stay unambiguous. The multi-server Bedrock example does this by default:

```yaml
prefixContainerName: true
```

This is strongly recommended whenever multiple targets share a backup volume.

If unprefixed backup names would be ambiguous across multiple targets, the helper refuses to guess.

The helper does not use relaxed fallback matching. If the archive name does not match the configured target naming pattern, it is not offered as a restore candidate.

## Run Directly

In the case that your docker compose stack doesn't already include the restore profile, you can run it using docker as a one-off. So long as you mount `/config`, `/data` and the server folder in the same way that your backup container does it, you can run the restore.

As before, make sure you stop your service stack (both backup and server) before performing the restore, and start it again afterwards once confirming the restore worked.

`docker run -it -rm -v ./config.yml:/config/config.yml:ro -v minecraft-server-backups:/data:ro -v minecraft-data:/minecraft --entrypoint /opt/bedrock/bedrockifier kaiede/minecraft-bedrock-backup restore`

## Manual Restore

Manually restoring your backup is the last resort for when:

* you have not added the restore service to your stack yet
* you cannot run the restore helper
* you need to recover directly from the raw backup archives

### Bedrock Manual Restore

For Bedrock servers, backups are `.mcworld` archives:

1. Stop the Minecraft server container.
2. Stop the Bedrockifier backup container.
3. Change into the Bedrock worlds folder.
4. Move the existing world out of the way.
5. Create a replacement world folder.
6. Unzip the backup archive into that folder.
7. Start the server again.
8. Delete the moved-aside world only after you verify the restore.

Example:

```bash
docker compose stop public backup
cd /opt/bedrock/public/worlds
mv PublicSMP PublicSMP.bak
mkdir PublicSMP
cd PublicSMP
unzip /opt/minecraft/backups/PublicSMP-<TIMESTAMP>.mcworld
docker compose start public backup
```

### Java Manual Restore

Java backups are `.zip` files with a single top-level world folder:

1. Stop the Minecraft server container.
2. Stop the Bedrockifier backup container.
3. Change into the Java server data folder.
4. Move the existing world folder out of the way.
5. Unzip the backup archive into the server data folder.
6. Start the server again.
7. Delete the moved-aside world only after you verify the restore.

Example:

```bash
docker compose stop public backup
cd /opt/minecraft/public
mv PublicSMP PublicSMP.bak
unzip /opt/minecraft/backups/PublicSMP-<TIMESTAMP>.zip
docker compose start public backup
```
