#!/bin/bash

set -o allexport
source .env set
set +o allexport

# Declare the directories
DIRS=(
  "$CONTENT_DIR/media/movies"
  "$CONTENT_DIR/media/music"
  "$CONTENT_DIR/media/tv"
  "$CONTENT_DIR/torrents/movies"
  "$CONTENT_DIR/torrents/music"
  "$CONTENT_DIR/torrents/tv"
  "$PROVISION_DIR"
)

# Loop over the directories
for DIR in "${DIRS[@]}"; do
  # Create the directory
  mkdir -p "$DIR"

  # # Create the .gitkeep file
  touch "$DIR/.gitkeep"
done