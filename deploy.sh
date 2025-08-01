#!/bin/bash

# Plausible Analytics Deployment Script
# Usage: ./deploy.sh [branch] [environment]

set -e

# Configuration
BRANCH=${1:-main}
ENVIRONMENT=${2:-production}
APP_DIR="/home/tuanbt/analytics"
BACKUP_DIR="/home/tuanbt/backups"
LOG_FILE="/var/log/plausible-deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Pre-deployment checks
pre_deployment_checks() {
    log "Starting pre-deployment checks..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running. Please start Docker service."
    fi
    
    # Check if Docker Compose is available
    if ! command -v docker-compose >/dev/null 2>&1; then
        error "Docker Compose is not installed."
    fi
    
    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        error "Git is not installed."
    fi
    
    # Check if app directory exists
    if [ ! -d "$APP_DIR" ]; then
        error "Application directory $APP_DIR does not exist."
    fi
    
    success "Pre-deployment checks passed"
}

# Create backup
create_backup() {
    log "Creating backup..."
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    # Create timestamped backup
    BACKUP_NAME="plausible-backup-$(date +'%Y%m%d-%H%M%S')"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
    
    # Backup database volumes
    log "Backing up database volumes..."
    docker run --rm -v analytics_postgres-data:/data -v "$BACKUP_DIR":/backup alpine tar czf "/backup/$BACKUP_NAME-postgres.tar.gz" -C /data .
    docker run --rm -v analytics_clickhouse-data:/data -v "$BACKUP_DIR":/backup alpine tar czf "/backup/$BACKUP_NAME-clickhouse.tar.gz" -C /data .
    
    # Backup application data
    docker run --rm -v analytics_plausible-data:/data -v "$BACKUP_DIR":/backup alpine tar czf "/backup/$BACKUP_NAME-app.tar.gz" -C /data .
    
    # Keep only last 5 backups
    cd "$BACKUP_DIR"
    ls -t plausible-backup-*.tar.gz | tail -n +16 | xargs -r rm --
    
    success "Backup created: $BACKUP_NAME"
}

# Pull latest code
pull_code() {
    log "Pulling latest code from branch: $BRANCH"
    
    cd "$APP_DIR"
    
    # Fetch latest changes
    git fetch origin
    
    # Check if branch exists
    if ! git show-ref --verify --quiet refs/remotes/origin/$BRANCH; then
        error "Branch $BRANCH does not exist in remote repository"
    fi
    
    # Switch to branch and pull
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
    
    success "Code updated to latest $BRANCH"
}

# Build and deploy
deploy_application() {
    log "Starting application deployment..."
    
    cd "$APP_DIR"
    
    # Stop existing containers
    log "Stopping existing containers..."
    docker-compose down --remove-orphans
    
    # Pull latest images
    log "Pulling latest images..."
    docker-compose pull
    
    # Build application
    log "Building application..."
    docker-compose build --no-cache plausible
    
    # Start services
    log "Starting services..."
    docker-compose up -d
    
    success "Application deployed successfully"
}

# Health check
health_check() {
    log "Performing health check..."
    
    # Wait for services to start
    sleep 30
    
    # Check if containers are running
    if ! docker-compose ps | grep -q "Up"; then
        error "Some containers failed to start"
    fi
    
    # Use the dedicated health check script
    if [ -f "./health-check.sh" ]; then
        log "Running comprehensive health check..."
        if ./health-check.sh; then
            success "Application health check passed"
            return 0
        else
            error "Application health check failed"
            return 1
        fi
    else
        # Fallback to simple HTTP check
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            log "Health check attempt $attempt/$max_attempts"
            
            if curl -f -s http://localhost:8000 >/dev/null 2>&1; then
                success "Application is responding"
                return 0
            fi
            
            sleep 10
            ((attempt++))
        done
        
        error "Application health check failed after $max_attempts attempts"
        return 1
    fi
}

# Database migration
run_migrations() {
    log "Running database migrations..."
    
    cd "$APP_DIR"
    
    # Run migrations
    docker-compose exec -T plausible /app/bin/plausible eval "Plausible.Release.migrate()"
    
    success "Database migrations completed"
}

# Cleanup old images
cleanup() {
    log "Cleaning up old Docker images..."
    
    # Remove unused images
    docker image prune -f
    
    # Remove unused volumes
    docker volume prune -f
    
    success "Cleanup completed"
}

# Send notification
send_notification() {
    local status=$1
    local message=$2
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local payload=$(cat <<EOF
{
    "text": "🚀 Plausible Analytics Deployment",
    "blocks": [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*Plausible Analytics Deployment*"
            }
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*Status:*\n$status"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Branch:*\n$BRANCH"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Environment:*\n$ENVIRONMENT"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Time:*\n$timestamp"
                }
            ]
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*Message:*\n$message"
            }
        }
    ]
}
EOF
        )
        
        curl -X POST -H 'Content-type: application/json' \
            --data "$payload" \
            "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
    fi
}

# Main deployment function
main() {
    log "Starting deployment process..."
    log "Branch: $BRANCH"
    log "Environment: $ENVIRONMENT"
    
    # Trap errors and send notification
    trap 'send_notification "❌ FAILED" "Deployment failed at step: $BASH_COMMAND"' ERR
    
    pre_deployment_checks
    create_backup
    pull_code
    deploy_application
    run_migrations
    health_check
    cleanup
    
    success "Deployment completed successfully!"
    send_notification "✅ SUCCESS" "Deployment completed successfully"
}

# Run main function
main "$@"