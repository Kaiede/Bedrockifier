### Overriding Permissions on Backed Up Worlds

In the `config.yml`, there is a feature that allows you to override the user, group, and permissions for the backups. It is only recommended to do this if you absolutely must, such as running it on a NAS device that requires specific ownership and permissions. Trimming may break if the tool loses write access to the backup files when using this functionality. Use with caution.

**Using chown requires running the service as root which is not recommended!**

```
ownership:
  chown: <uid>:<gid>
  permissions: 644
```
