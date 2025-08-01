# Plausible Community Edition Deployment Guide

## 🌐 Production Deployment: https://plausible.windifi.com

This guide covers the deployment of Plausible Community Edition using the updated CI/CD pipeline and deployment scripts.

## 📋 Prerequisites

- Docker and Docker Compose installed
- Server with at least 2GB RAM
- Domain configured to point to your server
- SSL certificate (Let's Encrypt recommended)

## 🚀 Quick Deployment

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/your-org/analytics.git
cd analytics

# Make deployment script executable
chmod +x scripts/deploy.sh
```

### 2. Configure Environment

Create a `.env` file with your production settings:

```bash
# Required Configuration
BASE_URL=https://plausible.windifi.com
SECRET_KEY_BASE=$(openssl rand -base64 48)
TOTP_VAULT_KEY=$(openssl rand -base64 32)

# Web Configuration
HTTP_PORT=80
HTTPS_PORT=443
```

### 3. Deploy

```bash
# Deploy to production
./scripts/deploy.sh deploy -e production

# Or using environment variables
ENVIRONMENT=production ./scripts/deploy.sh deploy
```

## 🔧 Environment-Specific Configurations

### Production Environment

- **URL**: https://plausible.windifi.com
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Resources**: 2GB RAM, 1 CPU
- **SSL**: Auto-configured with Let's Encrypt

### Staging Environment

- **URL**: https://staging-plausible.windifi.com
- **Ports**: 8000 (HTTP), 8443 (HTTPS)
- **Resources**: 1GB RAM, 0.5 CPU

### Development Environment

- **URL**: http://localhost:8000
- **Ports**: 8000 (HTTP)
- **Resources**: 512MB RAM, 0.25 CPU

## 📊 CI/CD Pipeline

### GitHub Actions Workflow

The deployment pipeline includes:

1. **Validation**: Checks Docker Compose configuration
2. **Deployment**: Deploys services with health checks
3. **Verification**: Tests application accessibility
4. **Health Check**: Comprehensive service health verification
5. **Rollback**: Automatic rollback on failure
6. **Cleanup**: Resource cleanup after deployment

### Triggering Deployment

```bash
# Automatic deployment on push to main/stable
git push origin main

# Manual deployment via GitHub Actions
# Go to Actions > Deploy Plausible Community Edition > Run workflow
```

## 🛠️ Management Commands

### Service Management

```bash
# Check service status
./scripts/deploy.sh status -e production

# View logs
./scripts/deploy.sh logs -e production

# Restart services
./scripts/deploy.sh restart -e production

# Stop services
./scripts/deploy.sh stop -e production

# Start services
./scripts/deploy.sh start -e production
```

### Backup and Recovery

```bash
# Create backup
./scripts/deploy.sh backup -e production

# Restore from backup
BACKUP_PATH=backups/20240801_143022 ./scripts/deploy.sh restore -e production
```

### Updates and Maintenance

```bash
# Update to latest version
./scripts/deploy.sh update -e production

# Run health checks
./scripts/deploy.sh health -e production
```

## 🔐 Security Configuration

### Environment Variables

Set these in your GitHub repository secrets:

- `SECRET_KEY_BASE`: Base64 encoded secret key
- `TOTP_VAULT_KEY`: TOTP vault encryption key
- `PRODUCTION_BASE_URL`: https://plausible.windifi.com
- `PRODUCTION_HTTP_PORT`: 80
- `PRODUCTION_HTTPS_PORT`: 443

### SSL Configuration

For automatic SSL with Let's Encrypt:

1. Ensure your domain points to the server
2. Set `HTTP_PORT=80` and `HTTPS_PORT=443`
3. The application will automatically request SSL certificates

## 📈 Monitoring and Health Checks

### Health Check Endpoints

- **Application**: https://plausible.windifi.com/health
- **PostgreSQL**: Internal health check
- **ClickHouse**: Internal health check

### Monitoring Features

- Automatic health checks every 30 seconds
- Service status monitoring
- Resource usage tracking
- Error logging and alerting

## 🔄 Backup Strategy

### Automated Backups

- **Schedule**: Daily at 2 AM
- **Retention**: 30 days, 7 copies
- **Storage**: Local backup directory
- **Components**: PostgreSQL, ClickHouse, Configuration

### Manual Backups

```bash
# Create immediate backup
./scripts/deploy.sh backup -e production

# Backup location: backups/YYYYMMDD_HHMMSS/
```

## 🚨 Troubleshooting

### Common Issues

1. **Services not starting**

   ```bash
   docker compose logs
   ./scripts/deploy.sh health -e production
   ```

2. **SSL certificate issues**

   - Verify domain DNS settings
   - Check firewall settings (ports 80, 443)
   - Review Let's Encrypt logs

3. **Database connection issues**
   ```bash
   docker compose exec plausible_db pg_isready -U postgres
   docker compose exec plausible_events_db wget -O - http://127.0.0.1:8123/ping
   ```

### Logs and Debugging

```bash
# View all service logs
./scripts/deploy.sh logs -e production

# View specific service logs
docker compose logs plausible
docker compose logs plausible_db
docker compose logs plausible_events_db
```

## 📚 Additional Resources

- [Plausible Community Edition Wiki](https://github.com/plausible/community-edition/wiki)
- [Configuration Guide](https://github.com/plausible/community-edition/wiki/configuration)
- [Reverse Proxy Setup](https://github.com/plausible/community-edition/wiki/reverse-proxy)
- [Backup and Restore](https://github.com/plausible/community-edition/wiki/backup-restore)

## 🆘 Support

For deployment issues:

1. Check the troubleshooting section
2. Review service logs
3. Run health checks
4. Consult the Plausible Community Edition documentation

---

**Production URL**: https://plausible.windifi.com  
**Last Updated**: August 2025  
**Version**: Plausible Community Edition v3.0.1
