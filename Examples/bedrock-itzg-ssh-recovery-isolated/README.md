# Isolated Restore Example: bedrock-itzg-ssh-recovery-isolated

This isolated restore example separates backup and restore into different containers and emphasizes protected mounts.

- `backup` uses the main `kaiede/minecraft-bedrock-backup` image.
- Backup reads server content from a read-only source mount (`/bedrock_public:ro`).
- `restore-menu` uses a lightweight Alpine-based image built from `restore.dockerfile` in this example folder.
- Restore reads backup archives from a read-only source mount (`/backups:ro`).

This layout gives a safer permissioned layout by reducing unnecessary write access:

- backup can write backup output, but cannot modify server source files through the mounted backup source path.
- restore can write the restore destination, but cannot modify backup archive source data.

## Files

- `docker-compose.yml`: compose setup with protected mounts and isolated restore service.
- `config.yml`: Bedrockifier backup config used by the backup container.
- `restore.dockerfile`: local example Dockerfile used only for the isolated restore service.

## How to run

1. Update shared volume env vars for your environment:
   `MC_DATA_DIR` and `BEDROCKIFIER_BACKUPS_DIR`.
   Defaults are local bind paths: `/opt/bedrock/public` and `/opt/minecraft/backups`.
2. Start normal server + backup:

```bash
docker compose up -d public backup
```

3. Stop backup writes before restore:

```bash
docker compose stop backup
```

4. Run isolated restore menu (builds the small restore image if needed):

```bash
docker compose --profile restore run --rm restore-menu
```

5. Start backup again:

```bash
docker compose start backup
```
