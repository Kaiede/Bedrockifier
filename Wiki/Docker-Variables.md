Below is a full list of variables that can be provided as environment variables in the `docker-compose.yml` file to the backup container.

### Core Variables

* `TZ`: This sets the timezone. It is optional, but it will use GMT if not set.

### Security/Permissions Variables

* `UID`: User to run the backup as, overriding the owner of the `/backups` folder.
* `GID`: Group to run the backup as, overriding the group of the `/backups` folder.

### Optional Variables

* `CONFIG_FILE`: Use this in the rare case that you want to use something other than `config.yml` as the file name of your backup configuration.
* `DATA_DIR`: Use this when you want to change the location of the `/data` directory to something different within the container. The main reason you might want to do that is if you are using a named volume for backups from multiple sources, and want your minecraft backups to live in a subfolder of that volume.
* `LISTENER_RECONNECT_INTERVAL`: Controls how often listener-mode connections are checked and reconnected if needed. Accepts interval values like `30s`, `2m`, or `1h`. Defaults to `60s` if not set, and values lower than `5s` are clamped to `5s`.

### Restore Variables

These are primarily used by `/opt/bedrock/restore-menu.sh` when the container is run in restore mode.

* `BACKUP_DIR`: Search directory for backup archives. Defaults to `/data`.
* `RESTORE_CONFIG_PATH`: Explicit path to the `config.yml` file to use for restore target discovery.
* `RESTORE_UID`: UID to apply to the restored world after unpacking.
* `RESTORE_GID`: GID to apply to the restored world after unpacking.
* `RESTORE_MODE`: File mode to apply recursively after restore, for example `775`.

### Restore Config Lookup Variables

These also affect restore behavior when the helper is discovering `config.yml`.

* `CONFIG_DIR`: If set, `${CONFIG_DIR}/config.yml` is checked before the default restore lookup locations.
* `CONFIG_FILE`: The config filename to look for instead of the default `config.yml`.
* `DATA_DIR`: If set, `${DATA_DIR}/${CONFIG_FILE:-config.yml}` is checked before `/data/config.yml`.

By default, the restore helper looks for `config.yml` in these locations:

* `/config/config.yml`
* `/data/config.yml`
* `/backups/config.yml`

### Advanced Restore Variables

These are mostly useful for troubleshooting or development.

* `DIALOG_BIN`: Override the `dialog` binary path used for interactive restore mode.
* `TOOL_BIN`: Override the Bedrockifier tool path used for archive unpacking.
* `TERM`: Terminal type exported for dialog rendering. Defaults to `xterm-256color`.

### Deprecated Settings

* `BACKUP_INTERVAL`: This configures how often the backups are run. It has been replaced by the schedule configuration in the `config.yml` file.
