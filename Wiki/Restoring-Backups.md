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

The examples include a `restore-menu` service that reuses the normal `kaiede/minecraft-bedrock-backup` image with an entrypoint override:

```yaml
restore-menu:
  image: kaiede/minecraft-bedrock-backup
  profiles:
    - restore
  entrypoint: ["/opt/bedrock/restore-menu.sh"]
```

Run restores with:

```bash
docker compose --profile restore run --rm restore-menu
```

The helper reads the same `config.yml` Bedrockifier uses for backups. It will:

1. Load configured restore targets.
2. Ask you to choose a server/world when more than one target exists.
3. Show backups that match that target.
4. Confirm the selected restore target.
5. Replace the selected world with the chosen backup.

The restore helper supports the current `containers:` layout used by the examples and normal Bedrockifier configs.

In interactive mode:

* `Cancel` from `Select Backup` returns to target selection.
* `No Matching Backups` returns to target selection after you acknowledge the dialog.

By default, it looks for `config.yml` in these locations:

* `/config/config.yml`
* `/data/config.yml`
* `/backups/config.yml`

If `RESTORE_CONFIG_PATH` is set, that path is used first. If `CONFIG_DIR` is set, `${CONFIG_DIR}/config.yml` is also checked before the default locations.

### Operational Sequence

Before restoring:

1. Stop the Minecraft server container you are restoring.
2. Stop the Bedrockifier backup container so no new backups are written during restore.
3. Run the restore helper with the `restore` profile.
4. Confirm the restored world starts correctly.
5. Start the backup service again.

Example:

```bash
docker compose stop public backup
docker compose --profile restore run --rm restore-menu
docker compose start public backup
```

Adjust service names for your stack.

### Non-Interactive Restore

The restore helper also supports a non-interactive mode:

```bash
docker compose --profile restore run --rm restore-menu \
  --file minecraft_public.PublicSMP.2026-03-31_1200-00.zip \
  --target minecraft_public \
  --yes
```

Rules:

* `--file` is required.
* `--target` is optional when the selected archive maps to exactly one configured restore target.
* `--target` is required when the selected archive could restore to more than one configured target.
* `--target` should be the container name from `config.yml`.
* archive filenames must match the configured target naming pattern exactly
* if the configured destination already exists, the helper deletes it and restores in place
* the archive is expected to match the configured target naming and restore-path expectations
* non-interactive mode prints status to the terminal and does not clear the console on exit

### Restore Environment Variables

The main restore variables are:

* `BACKUP_DIR`
* `RESTORE_CONFIG_PATH`
* `RESTORE_UID`
* `RESTORE_GID`
* `RESTORE_MODE`

The full restore environment-variable reference is documented in:

* [Docker Variables](https://github.com/Kaiede/Bedrockifier/wiki/Docker-Variables)

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

## Manual Fallback

Manual restore remains the fallback workflow if:

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
