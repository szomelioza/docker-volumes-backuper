#!/bin/bash

CONFIG_PATH=""

backup_volume() {
	local volume="$1"
	local host="$2"

	# Check if volume exists
	if ! docker volume inspect "$volume" >/dev/null 2>&1; then
		echo "ERROR: Volume: $volume on host: $host doesn't exist!"
		exit 1			
	fi

	# Get containers that are using the volume
	readarray -t VOLUME_CONTAINERS < <(docker ps -a --filter volume="$volume" --format '{{.ID}}')

	# Stop containers
	for container_id in "${VOLUME_CONTAINERS[@]}"; do
		docker stop "$container_id" > /dev/null
	done

	# Backup volume
	docker run --rm \
		-v "$volume":/volume \
		-v "/tmp:/backup" \
		alpine:latest \
  	sh -c "tar czf /backup/$volume-backup.tar.gz -C /volume . && chown $(id -u):$(id -g) /backup/$volume-backup.tar.gz"
	# Start containers
	for container_id in "${VOLUME_CONTAINERS[@]}"; do
		docker start "$container_id" > /dev/null
	done
}

# Read args
while [[ "$#" -gt 0 ]]; do
	case "$1" in
		-c|--config)
			CONFIG_PATH="$2"
			shift 2
			;;
		-h|--help)
			echo "Usage: $0 [-c|--config <path_to_config>]"
			exit 0
			;;
		-*)
			echo "Unknown option: $1"
			exit 1
			;;
		*)
			echo "Unknown argument: $1"
			exit 1
			;;
	esac
done

# Validate args
if [[ -z "$CONFIG_PATH" ]]; then
	echo "Error: Config path is required."
	echo "Usage: $0 [-c|--config <path_to_config>]"
	exit 1
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
	echo "Error: Config file not found at '$CONFIG_PATH'."
	exit 1
fi

# Validate config
if ! jq empty "$CONFIG_PATH" >/dev/null 2>&1; then
	echo "Error: Config file is not a valid JSON."
	exit 1
fi

echo "Backuper started"

# Read backup storage config
BACKUP_PATH=$(jq -r '.storage.path' "$CONFIG_PATH" | xargs)
BACKUP_HOST=$(jq -r '.storage.host // empty' "$CONFIG_PATH" | xargs)
BACKUP_USER=$(jq -r '.storage.user // empty' "$CONFIG_PATH" | xargs)
BACKUP_SSH_KEY_PATH=$(jq -r '.storage.ssh_key_path // empty' "$CONFIG_PATH" | xargs)

# Check if local backup or remote
if [[ -z "$BACKUP_HOST" || -z "$BACKUP_USER" || -z "$BACKUP_SSH_KEY_PATH" ]]; then
	LOCAL_BACKUP=1
else
	LOCAL_BACKUP=0
fi

# Loop over targets from config
jq -c '.targets[]' "$CONFIG_PATH" | while read -r target; do
	# Parse config values
	eval "$(echo "$target" | jq -r 'to_entries[] | "\(.key)=\(.value|@sh)"')"
	
	if [[ "$host" = "local" ]]; then
		backup_volume "$volume" "$host"
	else
		ssh -i $ssh_key_path "$user@$host" \
			"$(declare -f backup_volume); backup_volume \"$volume\" \"$host\""
		scp -i "$ssh_key_path" "$user@$host:/tmp/$volume-backup.tar.gz" "/tmp"
	fi

	if [[ "$LOCAL_BACKUP" -eq 0 ]]; then
		# Upload to remote backup
		scp -O -i "$BACKUP_SSH_KEY_PATH" "/tmp/$volume-backup.tar.gz" "$BACKUP_USER@$BACKUP_HOST:$BACKUP_PATH"
	else
		# Move to local backup
		mv "/tmp/$volume-backup.tar.gz" "$BACKUP_PATH"
	fi

done

echo "Backuper ended"
