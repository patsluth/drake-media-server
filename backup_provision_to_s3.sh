#!/bin/bash

# Drake Media Server Provision Backup Script
# This script stops containers, creates a tar archive of the provision folder
# with preserved file permissions, uploads to S3, and restarts containers.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration - Modify these variables as needed
S3_BUCKET="${S3_BUCKET:-drake-media-server}"
AWS_PROFILE="${AWS_PROFILE:-default}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
PROVISION_DIR="${PROVISION_DIR:-./provision}"
TEMP_DIR="${TEMP_DIR:-/tmp}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Source environment variables if .env exists
if [[ -f .env ]]; then
    source .env
    log_info "Loaded environment variables from .env file"
fi

# Cleanup function
cleanup() {
    if [[ -n "${LOCAL_BACKUP_FILE_PATH:-}" ]] && [[ -f "$LOCAL_BACKUP_FILE_PATH" ]]; then
        log_info "Cleaning up temporary archive file: $LOCAL_BACKUP_FILE_PATH"
        rm -r "$LOCAL_BACKUP_FILE_PATH"
    fi
}

# Set up trap for cleanup on exit
trap cleanup EXIT

# Validation functions
validate_requirements() {
    log_info "Validating requirements..."
    
    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        log_error "Neither docker-compose nor docker compose is available"
        exit 1
    fi
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if tar is available
    if ! command -v tar &> /dev/null; then
        log_error "tar command is not available"
        exit 1
    fi
    
    # Check if compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    # Check if provision directory exists
    if [[ ! -d "$PROVISION_DIR" ]]; then
        log_error "Provision directory not found: $PROVISION_DIR"
        exit 1
    fi
    
    log_success "All requirements validated"
}

validate_aws_config() {
    log_info "Validating AWS configuration..."
    
    # Test AWS credentials and S3 access
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
        log_error "AWS credentials not configured or invalid for profile: $AWS_PROFILE"
        exit 1
    fi
    
    # Test S3 bucket access
    if ! aws s3 ls "s3://$S3_BUCKET/" --profile "$AWS_PROFILE" &> /dev/null; then
        log_error "Cannot access S3 bucket: $S3_BUCKET (check bucket name and permissions)"
        exit 1
    fi
    
    log_success "AWS configuration validated"
}

# Docker management functions
get_compose_command() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        log_error "No compatible docker compose command found"
        exit 1
    fi
}

stop_containers() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    log_info "Stopping Docker containers..."
    if $compose_cmd -f "$COMPOSE_FILE" down; then
        log_success "Containers stopped successfully"
    else
        log_error "Failed to stop containers"
        exit 1
    fi
}

start_containers() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    log_info "Starting Docker containers..."
    if $compose_cmd -f "$COMPOSE_FILE" up -d; then
        log_success "Containers started successfully"
    else
        log_error "Failed to start containers"
        exit 1
    fi
}

# Archive and upload functions
create_archive() {
    TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
    REMOTE_BACKUP_FILE_NAME="${TIMESTAMP}.tar.gz"
    REMOTE_BACKUP_FILE_PATH="provision-backups/$(hostname | sed "s|\.|_|g")/${REMOTE_BACKUP_FILE_NAME}"
    LOCAL_BACKUP_FILE_NAME=$(echo "$REMOTE_BACKUP_FILE_PATH" | sed "s|/|-|g")
    LOCAL_BACKUP_FILE_PATH="$TEMP_DIR/$LOCAL_BACKUP_FILE_NAME"
    
    log_info "Creating archive: $LOCAL_BACKUP_FILE_PATH"

    mkdir -p $(dirname $LOCAL_BACKUP_FILE_PATH)

    log_info "Archiving provision directory: $PROVISION_DIR"
    
    # Create tar archive with preserved permissions and ownership
    # -p preserves permissions
    # -z compresses with gzip
    # -c creates archive
    # -f specifies filename
    # --numeric-owner preserves numeric user/group IDs
    if tar -pzcf $LOCAL_BACKUP_FILE_PATH --numeric-owner -C "$(dirname "$PROVISION_DIR")" "$(basename "$PROVISION_DIR")"; then
        local archive_size
        archive_size=$(du -h "$LOCAL_BACKUP_FILE_PATH" | cut -f1)
        log_success "Archive created successfully ($archive_size)"
    else
        log_error "Failed to create archive"
        exit 1
    fi
}

upload_to_s3() {
    local s3_url="s3://$S3_BUCKET/$REMOTE_BACKUP_FILE_PATH"
    
    log_info "Uploading to S3: $s3_url"
    
    # Upload with server-side encryption
    if aws s3 cp "$LOCAL_BACKUP_FILE_PATH" "$s3_url" --profile "$AWS_PROFILE"; then
        log_success "Uploaded to S3: $s3_url"
    else
        log_error "Failed to upload to S3"
        exit 1
    fi
}

# Main execution function
main() {
    log_info "Starting drake-media-server provision backup process"
    
    # Validation
    validate_requirements
    validate_aws_config
    
    # Check if S3_BUCKET is still the default placeholder
    if [[ "$S3_BUCKET" == "your-backup-bucket-name" ]]; then
        log_error "Please set the S3_BUCKET environment variable or modify the script configuration"
        exit 1
    fi
    
    # Main backup process
    stop_containers
    
    # Create archive even if containers failed to stop (for partial backup)
    create_archive
    upload_to_s3
    
    # Always try to restart containers
    start_containers
    
    log_success "Backup process completed successfully!"
}

# Run main function
main "$@"
