# Plausible Analytics Deployment Summary

## ✅ Current Server Configuration (72.18.214.233)

**User Setup:**
- **Current User**: `tuanbt` (UID: 1000)
- **Groups**: `tuanbt`, `sudo`, `users`, `docker`
- **Repository Location**: `/home/tuanbt/analytics`
- **Backup Directory**: `/home/tuanbt/backups`
- **Deploy User**: `deploy` exists but not used for repository

## 🚀 Quick Setup Guide

### 1. ✅ Prerequisites (Already Met)

Your server has:
- ✅ Docker and Docker Compose installed
- ✅ Git installed
- ✅ User `tuanbt` with Docker and sudo permissions
- ✅ Repository cloned at `/home/tuanbt/analytics`
- ✅ Firewall configured (ports 22, 80, 443, 8000)

### 2. ✅ Repository Setup (Already Done)

```bash
# Repository is already at the correct location
cd /home/tuanbt/analytics

# Scripts are already executable
# Environment has been set up with ./setup-production-env.sh
```

### 3. Environment Configuration

```bash
# Edit the environment file with your specific values
nano .env
```

**Required changes in .env:**
```bash
BASE_URL=https://your-domain.com  # Replace with your actual domain
# SECRET_KEY_BASE and TOTP_VAULT_KEY are already generated
```

### 4. GitHub Secrets Configuration

In your GitHub repository (https://github.com/tuanpep/analytics), configure these secrets:

**Settings → Secrets and variables → Actions → New repository secret:**

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `VPS_HOST` | `72.18.214.233` | Your server IP |
| `VPS_USER` | `tuanbt` | SSH username |
| `VPS_SSH_KEY` | `<private-key>` | SSH private key for tuanbt user |
| `SECRET_KEY_BASE` | `<from .env>` | Application secret (auto-generated) |
| `TOTP_VAULT_KEY` | `<from .env>` | 2FA vault key (auto-generated) |
| `SLACK_WEBHOOK_URL` | `<optional>` | Slack notifications |

### 5. SSH Key Setup

**Option A: Use existing deploy user keys (if accessible):**
```bash
# Check if you can access deploy user's private key
sudo cat /home/deploy/.ssh/id_ed25519
```

**Option B: Create new SSH keys for tuanbt user:**
```bash
# On your local machine
ssh-keygen -t ed25519 -C "github-deploy-tuanbt" -f ~/.ssh/github_deploy_tuanbt

# Add public key to server
ssh-copy-id -i ~/.ssh/github_deploy_tuanbt.pub tuanbt@72.18.214.233

# Copy private key to GitHub secrets (VPS_SSH_KEY)
cat ~/.ssh/github_deploy_tuanbt
```

### 6. Manual Deployment Test

```bash
# On your server as tuanbt user
cd /home/tuanbt/analytics

# Test deployment
./deploy.sh main production

# Check health
./health-check.sh
```

### 7. CI/CD Workflow

The GitHub Actions workflow will automatically:
- **Push to `main`** → Deploy to production
- **Push to `develop`** → Deploy to staging
- **Manual trigger** → Deploy to chosen environment

### 8. Monitoring

- **Health checks**: `./health-check.sh`
- **Logs**: `docker-compose logs -f plausible`
- **Container status**: `docker-compose ps`
- **Deployment logs**: `tail -f /var/log/plausible-deploy.log`

### 9. SSL/TLS Setup (Recommended)

```bash
# Install Nginx and Certbot
sudo apt install nginx certbot python3-certbot-nginx

# Configure Nginx proxy
sudo nano /etc/nginx/sites-available/plausible

# Example Nginx config:
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Get SSL certificate
sudo certbot --nginx -d your-domain.com
```

### 10. Backup and Maintenance

- ✅ Backups are created automatically during deployment
- ✅ Location: `/home/tuanbt/backups/`
- ✅ Retention: 5 most recent backups
- ✅ Existing system backups found in backup directory

## 🔧 Current Status

- ✅ **Repository**: Cloned and up to date
- ✅ **Scripts**: All executable and syntax-validated
- ✅ **Environment**: Production environment configured with generated secrets
- ✅ **Backup Directory**: Created and accessible
- ✅ **User Permissions**: Correct user (tuanbt) with proper groups
- ✅ **Docker**: Available and accessible to user
- ⚠️ **GitHub Secrets**: Need to be configured
- ⚠️ **Domain Configuration**: Need to update BASE_URL in .env

## Troubleshooting

### Common Issues

1. **Containers not starting**:
   ```bash
   docker-compose logs
   docker-compose down && docker-compose up -d
   ```

2. **Permission issues**:
   ```bash
   sudo chown -R tuanbt:tuanbt /home/tuanbt/analytics
   ```

3. **Database connection issues**:
   ```bash
   docker-compose exec postgres pg_isready -U plausible
   docker-compose exec clickhouse clickhouse-client --query "SELECT 1"
   ```

### Getting Help

1. Run health check: `./health-check.sh`
2. Check deployment logs: `tail -f /var/log/plausible-deploy.log`
3. Review application logs: `docker-compose logs -f plausible`

## Next Steps

1. ⚠️ **Configure GitHub Secrets** with your SSH key
2. ⚠️ **Update BASE_URL** in `.env` file with your domain
3. ✅ **Test manual deployment**: `./deploy.sh main production`
4. ⚠️ **Set up SSL/TLS** with Nginx and Let's Encrypt
5. ✅ **Push to `main` branch** to trigger CI/CD

Your Plausible Analytics instance will be available at:
- **Development**: `http://72.18.214.233:8000`
- **Production**: `https://your-domain.com` (after SSL setup)

## Summary

✅ **All deployment scripts updated for user `tuanbt`**  
✅ **Environment configured with generated secrets**  
✅ **GitHub Actions workflow updated for correct paths**  
✅ **Backup system ready**  
⚠️ **Awaiting GitHub secrets configuration and domain setup**