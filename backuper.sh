#!/bin/bash

CONFIG_PATH=""

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

# Loop over targets from config
jq -c '.targets[]' "$CONFIG_PATH" | while read -r target; do
	# Parse config values
	eval "$(echo "$target" | jq -r 'to_entries[] | "\(.key)=\(.value|@sh)"')"
	
	if [[ "$host" = "local" ]]; then
		# Check if volume exists
		if ! docker volume inspect "$volume" >/dev/null 2>&1; then
			echo "ERROR: Volume: $volume on host: $host doesn't exist!"
			exit 1			
		fi

		# Get containers that are using the volume
		readarray -t VOLUME_CONTAINERS < <(docker ps -a --filter volume="$volume" --format '{{.ID}}')

		# Stop containers
		for container_id in "${VOLUME_CONTAINERS[@]}"; do
			docker stop "$container_id"
		done

		# Backup volume
		docker run --rm \
			-v "$volume":/volume \
			-v "/tmp:/backup" \
			alpine:latest \
			tar czf /backup/$volume-backup.tar.gz -C /volume .

		# Start containers
		for container_id in "${VOLUME_CONTAINERS[@]}"; do
			docker start "$container_id"
		done
	fi

done

echo "Backuper ended"
