# Basic Example: bedrock-itzg-ssh-recovery

This basic example uses the main `kaiede/minecraft-bedrock-backup` image for both backup and restore workflows.

- The `backup` service runs normally with the default image entrypoint.
- The `restore-menu` service uses the same image, but overrides the entrypoint to run `/opt/bedrock/restore-menu.sh`.
- No second published image is required for restore.

## Files

- `docker-compose.yml`: compose setup for server, backup, and restore-menu.
- `config.yml`: Bedrockifier backup config loaded by the backup container.

## How to run

1. Update the host bind mounts in `docker-compose.yml` for your environment.
2. Start normal operations:

```bash
docker compose up -d public backup
```

3. Before restoring, stop backup writes:

```bash
docker compose stop backup
```

4. Run the interactive restore menu:

```bash
docker compose --profile tools run --rm restore-menu
```

5. Start backup service again:

```bash
docker compose start backup
```

## Non-interactive restore

```bash
docker compose --profile tools run --rm restore-menu \
  --file PublicSMP.2026-03-01_0100-00.mcworld --yes
```
