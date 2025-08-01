# Plausible Analytics Deployment Guide

This guide provides complete instructions for setting up and deploying Plausible Analytics with automated CI/CD.

## 📋 Prerequisites

- A Linux server (Ubuntu 20.04+ or CentOS 8+ recommended)
- Domain name pointing to your server
- GitHub repository with deployment keys configured
- Basic knowledge of Docker and Linux administration

## 🚀 Quick Start

### 1. Server Setup

Run the server setup script on your target server:

```bash
# Download and run the server setup script
curl -fsSL https://raw.githubusercontent.com/your-org/analytics/main/server-setup.sh | sudo bash

# Or clone the repository and run locally
git clone https://github.com/your-org/analytics.git
cd analytics
sudo ./server-setup.sh
```

This script will:

- Install Docker and Docker Compose
- Create a deploy user
- Set up firewall rules
- Configure log rotation
- Install security tools

### 2. Repository Setup

Clone your repository to the server:

```bash
# Switch to deploy user
sudo -u deploy -i

# Clone repository
cd /home/deploy
git clone https://github.com/your-org/analytics.git
cd analytics
```

### 3. Environment Configuration

Create your environment file:

```bash
# Copy the example environment file
cp env.example .env

# Edit with your actual values
nano .env
```

**Required environment variables:**

```bash
BASE_URL=https://your-domain.com
SECRET_KEY_BASE=your-secret-key-base-here
TOTP_VAULT_KEY=your-totp-vault-key-here
DATABASE_URL=postgres://plausible:plausible@postgres:5432/plausible
CLICKHOUSE_DATABASE_URL=http://clickhouse:8123/plausible?user=default&password=
ENVIRONMENT=prod
```

**Generate secrets:**

```bash
# Generate SECRET_KEY_BASE
openssl rand -base64 64

# Generate TOTP_VAULT_KEY
openssl rand -base64 32
```

### 4. GitHub Secrets Configuration

Configure the following secrets in your GitHub repository (Settings → Secrets and variables → Actions):

**Required Secrets:**

- `VPS_SSH_KEY`: Private SSH key for server access
- `VPS_HOST`: Your server IP address or hostname
- `VPS_USER`: SSH username (usually "deploy")
- `SECRET_KEY_BASE`: Application secret key
- `TOTP_VAULT_KEY`: 2FA vault key
- `SLACK_WEBHOOK_URL`: (Optional) Slack webhook for notifications

**Required Variables:**

- `BASE_URL`: Your application URL
- `DATABASE_URL`: PostgreSQL connection string
- `CLICKHOUSE_DATABASE_URL`: ClickHouse connection string
- `ENVIRONMENT`: "prod" for production

### 5. SSH Key Setup

Generate SSH keys for deployment:

```bash
# On your local machine
ssh-keygen -t ed25519 -C "github-deploy" -f ~/.ssh/github_deploy

# Add public key to server
ssh-copy-id -i ~/.ssh/github_deploy.pub deploy@your-server.com

# Add private key to GitHub secrets as VPS_SSH_KEY
cat ~/.ssh/github_deploy | pbcopy  # macOS
cat ~/.ssh/github_deploy | xclip -selection clipboard  # Linux
```

## 🔧 Manual Deployment

If you need to deploy manually:

```bash
# On your server as deploy user
cd /home/deploy/analytics

# Run deployment
./deploy.sh main production

# Check health
./health-check.sh
```

## 🔄 CI/CD Workflow

The deployment workflow automatically triggers on:

- **Push to `main`**: Deploys to production
- **Push to `develop`**: Deploys to staging
- **Manual workflow dispatch**: Deploy to chosen environment

### Workflow Steps:

1. **Test**: Runs full test suite with PostgreSQL and ClickHouse
2. **Security**: CodeQL security scanning
3. **Deploy**: SSH to server and run deployment script
4. **Health Check**: Verify application is running correctly
5. **Notifications**: Send Slack notifications on success/failure

## 📊 Monitoring and Health Checks

### Automated Health Checks

The `health-check.sh` script monitors:

- Container status
- Database connectivity
- Application responsiveness
- Disk space usage
- Memory usage
- Recent error logs

### Manual Health Check

```bash
# Run comprehensive health check
./health-check.sh

# Quick container status
docker-compose ps

# View logs
docker-compose logs -f plausible
```

### Log Locations

- Deployment logs: `/var/log/plausible-deploy.log`
- Application logs: `docker-compose logs plausible`
- Database logs: `docker-compose logs postgres clickhouse`

## 🔒 Security Considerations

### Firewall Configuration

The setup script configures these ports:

- 22 (SSH)
- 80 (HTTP)
- 443 (HTTPS)
- 8000 (Plausible)

### SSL/TLS Setup

For production, set up a reverse proxy with SSL:

```bash
# Install Nginx
sudo apt install nginx certbot python3-certbot-nginx

# Configure Nginx (example)
sudo nano /etc/nginx/sites-available/plausible

# Get SSL certificate
sudo certbot --nginx -d your-domain.com
```

Example Nginx configuration:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 🛠️ Troubleshooting

### Common Issues

**Containers not starting:**

```bash
# Check container logs
docker-compose logs

# Restart services
docker-compose down && docker-compose up -d
```

**Database connection issues:**

```bash
# Check database status
docker-compose exec postgres pg_isready -U plausible
docker-compose exec clickhouse clickhouse-client --query "SELECT 1"

# Reset databases (⚠️ DATA LOSS)
docker-compose down -v
docker-compose up -d
```

**Permission issues:**

```bash
# Fix ownership
sudo chown -R deploy:deploy /home/deploy/analytics

# Fix script permissions
chmod +x deploy.sh health-check.sh
```

### Getting Help

1. Check the health check report: `./health-check.sh`
2. Review deployment logs: `tail -f /var/log/plausible-deploy.log`
3. Check application logs: `docker-compose logs -f plausible`
4. Verify environment variables: `docker-compose config`

## 📈 Scaling and Performance

### Resource Requirements

**Minimum:**

- 2 CPU cores
- 4GB RAM
- 20GB storage

**Recommended:**

- 4+ CPU cores
- 8GB+ RAM
- 50GB+ SSD storage

### Performance Tuning

Edit your `.env` file:

```bash
# ClickHouse performance
CLICKHOUSE_MAX_BUFFER_SIZE_BYTES=500000
CLICKHOUSE_FLUSH_INTERVAL_MS=3000
CLICKHOUSE_INGEST_POOL_SIZE=10

# Application performance
OTEL_SAMPLER_RATIO=0.01
IMPORTED_MAX_BUFFER_SIZE=50000
```

### Backup Strategy

Backups are automatically created during deployment in `/home/deploy/backups/`:

- PostgreSQL data
- ClickHouse data
- Application data

Manual backup:

```bash
# Create backup
docker run --rm -v analytics_postgres-data:/data -v /home/deploy/backups:/backup alpine tar czf /backup/manual-postgres-$(date +%Y%m%d).tar.gz -C /data .
```

## 🔄 Updates and Maintenance

### Updating the Application

Updates are handled automatically through the CI/CD pipeline. For manual updates:

```bash
cd /home/deploy/analytics
git pull origin main
./deploy.sh main production
```

### Database Migrations

Migrations run automatically during deployment. For manual migration:

```bash
docker-compose exec plausible /app/bin/plausible eval "Plausible.Release.migrate()"
```

### Maintenance Tasks

```bash
# Clean up old Docker images
docker system prune -f

# Rotate logs manually
sudo logrotate /etc/logrotate.d/plausible

# Update system packages
sudo apt update && sudo apt upgrade -y
```

---

## 📞 Support

For issues and questions:

1. Check this documentation
2. Review GitHub Issues
3. Check application logs
4. Run health check script

Remember to always test deployments in a staging environment first!
