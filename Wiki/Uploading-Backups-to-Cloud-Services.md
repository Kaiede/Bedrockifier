Bedrockifier doesn't handle uploading files to cloud services for you, instead focusing on making the snapshots accessible for local restores in the case of a corrupted world.

One approach is to store the backups somewhere that you upload automatically. Such as a share on a NAS that is automatically synced off-site. Docker (and compose) can create volumes by mounting NFS or CIFS shares, and this can be mapped to your `/data` directory for the backup container. Just take care to handle secrets such as the share username/password securely.

Another approach to upload these is to use the `linuxserver/duplicati` docker container to do regular uploads to your preferred service.

### Example Duplicati Configuration

```
  duplicati:
    image: ghcr.io/linuxserver/duplicati
    container_name: duplicati
    environment:
      - PUID=1000
      - PGID=1001
      - TZ=America/Los_Angeles
      - CLI_ARGS= #optional
    volumes:
      - /home/user/duplicati/config:/config
      - /home/user/duplicati/backups:/backups
      - /home/user/minecraft/backups:/source/bedrock
    ports:
      - 8200:8200
    restart: unless-stopped
```
