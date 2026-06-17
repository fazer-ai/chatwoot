# Quick Chatwoot Backup Installation

Using your `ssh coolify-vm` alias.

## Step 1: Copy backup script to server

From your local machine (in the chatwoot project directory):

```bash
scp deployment/backup-chatwoot.sh coolify-vm:/tmp/backup-chatwoot.sh
```

## Step 2: Install on server

```bash
# SSH into your server
ssh coolify-vm

# Install the backup script
sudo cp /tmp/backup-chatwoot.sh /usr/local/bin/backup-chatwoot.sh
sudo chmod +x /usr/local/bin/backup-chatwoot.sh

# Create backup directory
sudo mkdir -p /var/backups/chatwoot
sudo chmod 755 /var/backups/chatwoot

# Create log file
sudo touch /var/log/backup-chatwoot.log
sudo chmod 644 /var/log/backup-chatwoot.log
```

## Step 3: Add cron job

```bash
# Edit crontab
crontab -e

# Add this line (same pattern as backup-n8n.sh):
5 2 * * * /usr/local/bin/backup-chatwoot.sh >> /var/log/backup-chatwoot.log 2>&1
```

## Step 4: Test it

```bash
# Test the backup script
sudo /usr/local/bin/backup-chatwoot.sh

# Verify it worked
ls -lh /var/backups/chatwoot/
tail /var/log/backup-chatwoot.log
```

## Step 5: Verify cron job

```bash
# Check your cron jobs
crontab -l | grep -i backup
```

You should see:
```
5 2 * * * /usr/local/bin/backup-n8n.sh >> /var/log/backup-n8n.log 2>&1
5 2 * * * /usr/local/bin/backup-chatwoot.sh >> /var/log/backup-chatwoot.log 2>&1
```

---

## One-liner installation (alternative)

If you prefer to do it all at once:

```bash
# Copy script
scp deployment/backup-chatwoot.sh coolify-vm:/tmp/backup-chatwoot.sh

# Install (run on server)
ssh coolify-vm "sudo bash -c '
  cp /tmp/backup-chatwoot.sh /usr/local/bin/backup-chatwoot.sh && \
  chmod +x /usr/local/bin/backup-chatwoot.sh && \
  mkdir -p /var/backups/chatwoot && \
  touch /var/log/backup-chatwoot.log && \
  chmod 755 /var/backups/chatwoot && \
  chmod 644 /var/log/backup-chatwoot.log
' && (crontab -l 2>/dev/null; echo \"5 2 * * * /usr/local/bin/backup-chatwoot.sh >> /var/log/backup-chatwoot.log 2>&1\") | crontab -"
```

---

## Before deploying

1. ✅ Test backup: `ssh coolify-vm "sudo /usr/local/bin/backup-chatwoot.sh"`
2. ✅ Verify backup: `ssh coolify-vm "ls -lh /var/backups/chatwoot/"`
3. ✅ Check cron: `ssh coolify-vm "crontab -l | grep backup-chatwoot"`
4. ✅ **Ready to deploy!** 🚀

