#!/bin/bash

# Plausible Analytics Health Check Script
# This script checks the health of the Plausible Analytics application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_URL="http://localhost:8000"
TIMEOUT=30
MAX_RETRIES=5

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if containers are running
check_containers() {
    log "Checking container status..."
    
    local containers=("plausible" "plausible-postgres" "plausible-clickhouse")
    local all_running=true
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            success "Container $container is running"
        else
            error "Container $container is not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        return 1
    fi
    
    return 0
}

# Check application health endpoint
check_application_health() {
    log "Checking application health endpoint..."
    
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -f -s --connect-timeout $TIMEOUT "$APP_URL" >/dev/null 2>&1; then
            success "Application is responding"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        warning "Health check attempt $retry_count/$MAX_RETRIES failed"
        
        if [ $retry_count -lt $MAX_RETRIES ]; then
            sleep 10
        fi
    done
    
    error "Application health check failed after $MAX_RETRIES attempts"
    return 1
}

# Check database connectivity
check_database_connectivity() {
    log "Checking database connectivity..."
    
    # Check PostgreSQL
    if docker exec plausible-postgres pg_isready -U plausible >/dev/null 2>&1; then
        success "PostgreSQL is ready"
    else
        error "PostgreSQL is not ready"
        return 1
    fi
    
    # Check ClickHouse
    if docker exec plausible-clickhouse clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then
        success "ClickHouse is ready"
    else
        error "ClickHouse is not ready"
        return 1
    fi
    
    return 0
}

# Check disk space
check_disk_space() {
    log "Checking disk space..."
    
    local threshold=90
    local usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt "$threshold" ]; then
        error "Disk usage is above ${threshold}%: ${usage}%"
        return 1
    else
        success "Disk usage is acceptable: ${usage}%"
    fi
    
    return 0
}

# Check memory usage
check_memory_usage() {
    log "Checking memory usage..."
    
    local threshold=90
    local usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    
    if [ "$usage" -gt "$threshold" ]; then
        warning "Memory usage is high: ${usage}%"
    else
        success "Memory usage is acceptable: ${usage}%"
    fi
    
    return 0
}

# Check Docker logs for errors
check_logs_for_errors() {
    log "Checking recent logs for errors..."
    
    local containers=("plausible" "plausible-postgres" "plausible-clickhouse")
    local error_found=false
    
    for container in "${containers[@]}"; do
        local error_count=$(docker logs --since="1h" "$container" 2>&1 | grep -i "error\|exception\|fatal" | wc -l)
        
        if [ "$error_count" -gt 0 ]; then
            warning "Found $error_count error(s) in $container logs in the last hour"
            error_found=true
        else
            success "No errors found in $container logs"
        fi
    done
    
    if [ "$error_found" = true ]; then
        return 1
    fi
    
    return 0
}

# Generate health report
generate_health_report() {
    log "Generating health report..."
    
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local report_file="/tmp/plausible-health-report-$(date +'%Y%m%d-%H%M%S').txt"
    
    {
        echo "Plausible Analytics Health Report"
        echo "Generated: $timestamp"
        echo "================================="
        echo ""
        
        echo "Container Status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep plausible
        echo ""
        
        echo "Resource Usage:"
        echo "Memory:"
        free -h
        echo ""
        echo "Disk:"
        df -h /
        echo ""
        
        echo "Recent Logs (last 50 lines):"
        echo "--- Plausible ---"
        docker logs --tail=50 plausible 2>&1 | tail -20
        echo ""
        
    } > "$report_file"
    
    success "Health report generated: $report_file"
    
    # Show summary
    cat "$report_file"
}

# Main health check function
main() {
    log "Starting health check for Plausible Analytics..."
    
    local overall_health=true
    
    # Run all health checks
    if ! check_containers; then
        overall_health=false
    fi
    
    if ! check_database_connectivity; then
        overall_health=false
    fi
    
    if ! check_application_health; then
        overall_health=false
    fi
    
    if ! check_disk_space; then
        overall_health=false
    fi
    
    check_memory_usage  # This is a warning check, doesn't affect overall health
    
    if ! check_logs_for_errors; then
        warning "Errors found in logs, but application may still be functional"
    fi
    
    # Generate report
    generate_health_report
    
    # Final result
    if [ "$overall_health" = true ]; then
        success "Overall health check: PASSED"
        exit 0
    else
        error "Overall health check: FAILED"
        exit 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -u, --url URL      Application URL (default: $APP_URL)"
    echo "  -t, --timeout SEC  Timeout in seconds (default: $TIMEOUT)"
    echo "  -r, --retries NUM  Max retries (default: $MAX_RETRIES)"
    echo "  -h, --help         Show this help message"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            APP_URL="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -r|--retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"