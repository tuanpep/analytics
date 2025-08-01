#!/bin/bash

# Plausible Community Edition Deployment Script
# This script helps manage deployments across different environments

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=${ENVIRONMENT:-"development"}
ACTION=${ACTION:-"deploy"}
VERBOSE=${VERBOSE:-"false"}

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [ACTION]

Actions:
    deploy      Deploy Plausible Community Edition
    stop        Stop all services
    start       Start all services
    restart     Restart all services
    status      Show status of all services
    logs        Show logs for all services
    backup      Create a backup
    restore     Restore from backup
    update      Update to latest version
    health      Run health checks

Options:
    -e, --environment ENV    Environment (development, staging, production)
    -v, --verbose           Verbose output
    -h, --help              Show this help message

Examples:
    $0 deploy -e production
    $0 status -e staging
    $0 backup -e production
EOF
}

# Function to validate environment
validate_environment() {
    case $ENVIRONMENT in
        development|staging|production)
            return 0
            ;;
        *)
            print_error "Invalid environment: $ENVIRONMENT"
            print_error "Valid environments: development, staging, production"
            exit 1
            ;;
    esac
}

# Function to load environment configuration
load_config() {
    if [ -f "deployment-config.yml" ]; then
        print_status "Loading configuration from deployment-config.yml"
        # In a real implementation, you would parse the YAML file
        # For now, we'll use environment variables
    else
        print_warning "deployment-config.yml not found, using defaults"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker compose &> /dev/null; then
        print_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check if required files exist
    if [ ! -f "compose.yml" ]; then
        print_error "compose.yml not found"
        exit 1
    fi
    
    print_status "All prerequisites met"
}

# Function to create environment file
create_env_file() {
    print_header "Creating Environment Configuration"
    
    # Generate secret if not provided
    if [ -z "${SECRET_KEY_BASE:-}" ]; then
        SECRET_KEY_BASE=$(openssl rand -base64 48)
        print_status "Generated new SECRET_KEY_BASE"
    fi
    
    if [ -z "${TOTP_VAULT_KEY:-}" ]; then
        TOTP_VAULT_KEY=$(openssl rand -base64 32)
        print_status "Generated new TOTP_VAULT_KEY"
    fi
    
    # Set environment-specific values
    case $ENVIRONMENT in
        production)
            BASE_URL=${PRODUCTION_BASE_URL:-"https://plausible.windifi.com"}
            HTTP_PORT=${PRODUCTION_HTTP_PORT:-"80"}
            HTTPS_PORT=${PRODUCTION_HTTPS_PORT:-"443"}
            ;;
        staging)
            BASE_URL=${STAGING_BASE_URL:-"https://staging-plausible.windifi.com"}
            HTTP_PORT=${STAGING_HTTP_PORT:-"8000"}
            HTTPS_PORT=${STAGING_HTTPS_PORT:-"8443"}
            ;;
        development)
            BASE_URL=${DEV_BASE_URL:-"http://localhost:8000"}
            HTTP_PORT=${DEV_HTTP_PORT:-"8000"}
            ;;
    esac
    
    # Create .env file
    cat > .env << EOF
BASE_URL=${BASE_URL}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
TOTP_VAULT_KEY=${TOTP_VAULT_KEY}
HTTP_PORT=${HTTP_PORT}
EOF

    if [ ! -z "${HTTPS_PORT:-}" ]; then
        echo "HTTPS_PORT=${HTTPS_PORT}" >> .env
    fi
    
    print_status "Environment file created"
}

# Function to create compose override
create_compose_override() {
    print_header "Creating Docker Compose Override"
    
    cat > compose.override.yml << EOF
services:
  plausible:
    ports:
      - "${HTTP_PORT}:${HTTP_PORT}"
EOF

    if [ ! -z "${HTTPS_PORT:-}" ]; then
        cat >> compose.override.yml << EOF
      - "${HTTPS_PORT}:${HTTPS_PORT}"
EOF
    fi
    
    print_status "Compose override created"
}

# Function to deploy
deploy() {
    print_header "Deploying Plausible Community Edition"
    
    check_prerequisites
    load_config
    validate_environment
    create_env_file
    create_compose_override
    
    print_status "Pulling latest images..."
    docker compose pull
    
    print_status "Starting services..."
    docker compose up -d
    
    print_status "Waiting for services to be healthy..."
    timeout 300 bash -c 'until docker compose ps | grep -q "healthy"; do sleep 10; echo "Waiting for services..."; done'
    
    print_status "Verifying deployment..."
    sleep 30
    
    if curl -f -I "${BASE_URL}" > /dev/null 2>&1; then
        print_status "✅ Deployment successful!"
        print_status "🌐 Application is available at: ${BASE_URL}"
    else
        print_error "❌ Deployment verification failed"
        docker compose logs
        exit 1
    fi
}

# Function to stop services
stop() {
    print_header "Stopping Services"
    docker compose down
    print_status "Services stopped"
}

# Function to start services
start() {
    print_header "Starting Services"
    docker compose up -d
    print_status "Services started"
}

# Function to restart services
restart() {
    print_header "Restarting Services"
    docker compose restart
    print_status "Services restarted"
}

# Function to show status
status() {
    print_header "Service Status"
    docker compose ps
}

# Function to show logs
logs() {
    print_header "Service Logs"
    docker compose logs -f
}

# Function to create backup
backup() {
    print_header "Creating Backup"
    
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    print_status "Backing up PostgreSQL database..."
    docker compose exec -T plausible_db pg_dump -U postgres plausible > "$BACKUP_DIR/postgres_backup.sql"
    
    print_status "Backing up ClickHouse data..."
    docker compose exec -T plausible_events_db clickhouse-client --query "BACKUP TABLE events TO '$BACKUP_DIR/clickhouse_backup'"
    
    print_status "Backing up configuration..."
    cp .env "$BACKUP_DIR/"
    cp compose.yml "$BACKUP_DIR/"
    cp compose.override.yml "$BACKUP_DIR/" 2>/dev/null || true
    
    print_status "✅ Backup created in $BACKUP_DIR"
}

# Function to restore from backup
restore() {
    print_header "Restoring from Backup"
    
    if [ -z "${BACKUP_PATH:-}" ]; then
        print_error "BACKUP_PATH not specified"
        exit 1
    fi
    
    if [ ! -d "$BACKUP_PATH" ]; then
        print_error "Backup directory not found: $BACKUP_PATH"
        exit 1
    fi
    
    print_status "Stopping services..."
    docker compose down
    
    print_status "Restoring PostgreSQL database..."
    docker compose up -d plausible_db
    sleep 10
    docker compose exec -T plausible_db psql -U postgres -d plausible < "$BACKUP_PATH/postgres_backup.sql"
    
    print_status "Restoring ClickHouse data..."
    docker compose exec -T plausible_events_db clickhouse-client --query "RESTORE TABLE events FROM '$BACKUP_PATH/clickhouse_backup'"
    
    print_status "Starting all services..."
    docker compose up -d
    
    print_status "✅ Restore completed"
}

# Function to update
update() {
    print_header "Updating Plausible Community Edition"
    
    print_status "Creating backup before update..."
    backup
    
    print_status "Pulling latest images..."
    docker compose pull
    
    print_status "Updating services..."
    docker compose up -d
    
    print_status "✅ Update completed"
}

# Function to run health checks
health() {
    print_header "Running Health Checks"
    
    # Check if services are running
    if ! docker compose ps | grep -q "Up"; then
        print_error "Services are not running"
        exit 1
    fi
    
    # Check PostgreSQL
    if docker compose exec -T plausible_db pg_isready -U postgres; then
        print_status "✅ PostgreSQL is healthy"
    else
        print_error "❌ PostgreSQL health check failed"
        exit 1
    fi
    
    # Check ClickHouse
    if docker compose exec -T plausible_events_db wget --no-verbose --tries=1 -O - http://127.0.0.1:8123/ping > /dev/null 2>&1; then
        print_status "✅ ClickHouse is healthy"
    else
        print_error "❌ ClickHouse health check failed"
        exit 1
    fi
    
    # Check Plausible application
    if curl -f "${BASE_URL:-http://localhost:8000}" > /dev/null 2>&1; then
        print_status "✅ Plausible application is healthy"
    else
        print_error "❌ Plausible application health check failed"
        exit 1
    fi
    
    print_status "✅ All health checks passed!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        deploy|stop|start|restart|status|logs|backup|restore|update|health)
            ACTION="$1"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Set verbose mode
if [ "$VERBOSE" = "true" ]; then
    set -x
fi

# Execute action
case $ACTION in
    deploy)
        deploy
        ;;
    stop)
        stop
        ;;
    start)
        start
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    backup)
        backup
        ;;
    restore)
        restore
        ;;
    update)
        update
        ;;
    health)
        health
        ;;
    *)
        print_error "Unknown action: $ACTION"
        show_usage
        exit 1
        ;;
esac 