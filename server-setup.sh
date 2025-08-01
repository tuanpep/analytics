#!/bin/bash

# Plausible Analytics Server Setup Script
# This script sets up a server for Plausible Analytics deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEPLOY_USER="deploy"
APP_NAME="analytics"
APP_DIR="/home/$DEPLOY_USER/$APP_NAME"
BACKUP_DIR="/home/$DEPLOY_USER/backups"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    
    # Detect OS
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get upgrade -y
        apt-get install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release
    elif [ -f /etc/redhat-release ]; then
        yum update -y
        yum install -y curl wget git unzip
    else
        error "Unsupported operating system"
    fi
    
    success "System packages updated"
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        warning "Docker is already installed"
        return 0
    fi
    
    # Install Docker based on OS
    if [ -f /etc/debian_version ]; then
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Set up stable repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        
    elif [ -f /etc/redhat-release ]; then
        # Install Docker on CentOS/RHEL
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    fi
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    success "Docker installed successfully"
}

# Install Docker Compose
install_docker_compose() {
    log "Installing Docker Compose..."
    
    # Check if Docker Compose is already installed
    if command -v docker-compose >/dev/null 2>&1; then
        warning "Docker Compose is already installed"
        return 0
    fi
    
    # Install Docker Compose
    DOCKER_COMPOSE_VERSION="2.24.0"
    curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for backward compatibility
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    success "Docker Compose installed successfully"
}

# Create deploy user
create_deploy_user() {
    log "Creating deploy user..."
    
    # Check if user already exists
    if id "$DEPLOY_USER" &>/dev/null; then
        warning "User $DEPLOY_USER already exists"
        return 0
    fi
    
    # Create user
    useradd -m -s /bin/bash "$DEPLOY_USER"
    
    # Add user to docker group
    usermod -aG docker "$DEPLOY_USER"
    
    # Create SSH directory
    mkdir -p "/home/$DEPLOY_USER/.ssh"
    chmod 700 "/home/$DEPLOY_USER/.ssh"
    chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
    
    success "Deploy user created successfully"
}

# Setup SSH key for deploy user
setup_ssh_key() {
    log "Setting up SSH key for deploy user..."
    
    if [ -z "$SSH_PUBLIC_KEY" ]; then
        warning "SSH_PUBLIC_KEY environment variable not set. You'll need to manually add the SSH key."
        echo "Run: echo 'your-public-key' >> /home/$DEPLOY_USER/.ssh/authorized_keys"
        return 0
    fi
    
    # Add SSH key
    echo "$SSH_PUBLIC_KEY" >> "/home/$DEPLOY_USER/.ssh/authorized_keys"
    chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
    chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"
    
    success "SSH key added for deploy user"
}

# Setup application directory
setup_app_directory() {
    log "Setting up application directory..."
    
    # Create directories
    sudo -u "$DEPLOY_USER" mkdir -p "$APP_DIR"
    sudo -u "$DEPLOY_USER" mkdir -p "$BACKUP_DIR"
    
    # Set permissions
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER"
    
    success "Application directory setup complete"
}

# Setup firewall
setup_firewall() {
    log "Setting up firewall..."
    
    # Check if ufw is available (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        ufw --force enable
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow 8000/tcp  # Plausible port
        ufw allow 80/tcp    # HTTP
        ufw allow 443/tcp   # HTTPS
        success "UFW firewall configured"
        
    # Check if firewalld is available (CentOS/RHEL)
    elif command -v firewall-cmd >/dev/null 2>&1; then
        systemctl start firewalld
        systemctl enable firewalld
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-port=8000/tcp
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        success "Firewalld configured"
        
    else
        warning "No firewall manager found. Please configure firewall manually."
    fi
}

# Setup log rotation
setup_log_rotation() {
    log "Setting up log rotation..."
    
    cat > /etc/logrotate.d/plausible << 'EOF'
/var/log/plausible-deploy.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF
    
    success "Log rotation configured"
}

# Setup systemd service for automatic startup
setup_systemd_service() {
    log "Setting up systemd service..."
    
    cat > /etc/systemd/system/plausible.service << EOF
[Unit]
Description=Plausible Analytics
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
User=$DEPLOY_USER
Group=$DEPLOY_USER

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable plausible.service
    
    success "Systemd service configured"
}

# Install additional tools
install_additional_tools() {
    log "Installing additional tools..."
    
    if [ -f /etc/debian_version ]; then
        apt-get install -y htop ncdu fail2ban logrotate cron
    elif [ -f /etc/redhat-release ]; then
        yum install -y htop ncdu fail2ban logrotate cronie
        systemctl enable crond
        systemctl start crond
    fi
    
    # Setup fail2ban for SSH protection
    systemctl enable fail2ban
    systemctl start fail2ban
    
    success "Additional tools installed"
}

# Main setup function
main() {
    log "Starting server setup for Plausible Analytics..."
    
    check_root
    update_system
    install_docker
    install_docker_compose
    create_deploy_user
    setup_ssh_key
    setup_app_directory
    setup_firewall
    setup_log_rotation
    setup_systemd_service
    install_additional_tools
    
    success "Server setup completed successfully!"
    
    echo ""
    echo "==================================================================="
    echo "SERVER SETUP COMPLETE"
    echo "==================================================================="
    echo ""
    echo "Next steps:"
    echo "1. Clone your repository to $APP_DIR"
    echo "2. Copy env.example to .env and configure it"
    echo "3. Run the deployment script"
    echo ""
    echo "Deploy user: $DEPLOY_USER"
    echo "App directory: $APP_DIR"
    echo "Backup directory: $BACKUP_DIR"
    echo ""
    echo "To deploy:"
    echo "  sudo -u $DEPLOY_USER bash -c 'cd $APP_DIR && ./deploy.sh'"
    echo ""
    echo "==================================================================="
}

# Run main function
main "$@"