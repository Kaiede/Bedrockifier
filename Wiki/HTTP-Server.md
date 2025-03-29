Starting with 1.4.0, Bedrockifier includes a minimal HTTP endpoint that can be used to perform a couple different tasks. It runs on port 8080 and can be exposed in your docker container configuration, or the `ports` configuration in docker-compose. By default, it is not accessible except to the services in the same docker-compose file, or to commands running in the container's shell environment.

A copy of curl is provided in the container and can be used for scripts if desired.

## Unprivileged Tasks

These tasks do not require a token to execute.

### Health Check
- `/live`
- `/health`

If the service is healthy, this will return HTTP status 200. If the service is unhealthy, it will return HTTP status 503 or another error.

The service is considered unhealthy if there was an error or other failure during the last backup attempt.

### Service Status
- `/status`

This provides more details. Currently only provides information about the last backup. The date of the backup, wether or not it succeeded, and the size of the worlds backed up.

## Privileged Tasks

These tasks require a token to execute. On each launch, Bedrockifier currently generates a new random token and writes it to `/config/.bedrockifierToken`. This token must be provided when making requests to these endpoints.

This is done by providing an authorization header as part of the request, providing the token stored in the token file: `Authorization: Bearer <Token>`. When using curl, it's possible to pass the token in using a command similar to this:

```
curl -v http://127.0.0.1:8080/start-backup -H "Authorization: Bearer $(cat <TOKEN_PATH>)"
```

You will need to provide the appropriate address depending

### Trigger Backup
- `/start-backup`

This triggers a full backup of all containers. Can be used to create one-off backups. Useful when wanting to trim chunks or do other administrative tasks.

Alternatively, an admin can access the docker container shell and execute `/trigger-backup.sh [tokenFile]`. This will read the local token from `/config/.bedrockifierToken` if a token file path isn't provided..
