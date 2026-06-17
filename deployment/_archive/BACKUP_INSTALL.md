# Installing Chatwoot Backup (Following Your Existing Pattern)

Based on your existing backup setup, here's how to install Chatwoot backups:

## Quick Installation

### Step 1: Copy files to your server

```bash
# From your local machine, copy the backup script to your server
scp deployment/backup-chatwoot.sh user@your-server:/tmp/
scp deployment/install_chatwoot_backup.sh user@your-server:/tmp/
```

### Step 2: SSH into your server and run installer

```bash
# SSH into your server
ssh user@your-server

# Run the installation script
sudo bash /tmp/install_chatwoot_backup.sh
```

The installer will:
- ✅ Copy script to `/usr/local/bin/backup-chatwoot.sh` (matching your pattern)
- ✅ Create backup directory at `/var/backups/chatwoot`
- ✅ Create log file at `/var/log/backup-chatwoot.log`
- ✅ Add cron job: `5 2 * * *` (Daily at 2:05 AM, matching your n8n backup time)
- ✅ Test the backup (optional)

---

## Manual Installation (Alternative)

If you prefer to install manually:

### 1. Copy backup script

```bash
sudo cp deployment/backup-chatwoot.sh /usr/local/bin/backup-chatwoot.sh
sudo chmod +x /usr/local/bin/backup-chatwoot.sh
```

### 2. Create directories

```bash
sudo mkdir -p /var/backups/chatwoot
sudo touch /var/log/backup-chatwoot.log
sudo chmod 755 /var/backups/chatwoot
sudo chmod 644 /var/log/backup-chatwoot.log
```

### 3. Add cron job

```bash
# Edit crontab
crontab -e

# Add this line (matches your backup-n8n.sh pattern):
5 2 * * * /usr/local/bin/backup-chatwoot.sh >> /var/log/backup-chatwoot.log 2>&1
```

---

## Configuration

The script will automatically detect your PostgreSQL container. If it can't find it, you can set environment variables:

```bash
# In /etc/environment or ~/.bashrc (if needed)
export POSTGRES_DB=chatwoot_production
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=your_password
export CHATWOOT_BACKUP_DIR=/var/backups/chatwoot
export CHATWOOT_BACKUP_LOG=/var/log/backup-chatwoot.log
```

---

## Verification

After installation, verify everything works:

```bash
# 1. Check cron job was added
crontab -l | grep backup-chatwoot

# 2. Test backup manually
sudo /usr/local/bin/backup-chatwoot.sh

# 3. Check backup was created
ls -lh /var/backups/chatwoot/

# 4. Check logs
tail -f /var/log/backup-chatwoot.log
```

---

## Your Backup Schedule

After installation, your cron jobs will look like:

```bash
$ crontab -l | grep backup
5 2 * * * /usr/local/bin/backup-n8n.sh >> /var/log/backup-n8n.log 2>&1
5 2 * * * /usr/local/bin/backup-chatwoot.sh >> /var/log/backup-chatwoot.log 2>&1
```

Both backups run at 2:05 AM daily.

---

## Backup Retention

- **Backups kept**: Last 30 days
- **Automatic cleanup**: Old backups are automatically deleted
- **Backup location**: `/var/backups/chatwoot/`
- **Backup format**: `chatwoot_backup_YYYYMMDD_HHMMSS.sql.gz`

---

## Restore from Backup

If you need to restore:

```bash
# Find the backup file
ls -lh /var/backups/chatwoot/

# Restore (replace with actual container name and backup file)
gunzip < /var/backups/chatwoot/chatwoot_backup_20231222_020500.sql.gz | \
  docker exec -i <postgres-container-name> \
  psql -U postgres -d chatwoot_production
```

---

## Troubleshooting

### "Could not find PostgreSQL container"
- List all containers: `docker ps`
- The script looks for containers with "postgres" or "chatwoot" in the name
- You may need to adjust the container detection in the script

### "Permission denied"
- Make sure script is executable: `sudo chmod +x /usr/local/bin/backup-chatwoot.sh`
- Check backup directory permissions: `sudo chmod 755 /var/backups/chatwoot`

### "Backup failed"
- Check logs: `tail -f /var/log/backup-chatwoot.log`
- Verify PostgreSQL container is running: `docker ps | grep postgres`
- Test database connection manually

---

## Before Your Next Deployment

1. ✅ Verify backup is working: `sudo /usr/local/bin/backup-chatwoot.sh`
2. ✅ Check backup exists: `ls -lh /var/backups/chatwoot/`
3. ✅ Verify cron job: `crontab -l | grep backup-chatwoot`
4. ✅ **Now you're safe to deploy!** 🚀

