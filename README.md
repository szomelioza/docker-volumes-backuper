# docker-volumes-backuper

Simple backup tool for Docker volumes.

# Usage
```bash
./backuper.sh --config backup_config.json
```

# Config anatomy
```jsonc
{
  // List of targets to backup
	"targets": [
		{
      // Host where volume can be found
			"host": "local",
      // Name of the volume
			"volume": "my_volume"
		}
	],
  // Defintion of target to store backups
	"storage": {
    // Path in which backup should be saved
		"path": "/tmp"
	}
}
```