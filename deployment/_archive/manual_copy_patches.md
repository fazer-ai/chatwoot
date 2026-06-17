# Manual Copy Patch Files to Production

## Option 1: Copy via SSH (Recommended)

### Step 1: Connect to Production Server
```bash
ssh azureuser@your-production-server.com
```

### Step 2: Create Directory Structure
```bash
sudo mkdir -p /opt/chatwoot-patches/app/services
sudo mkdir -p /opt/chatwoot-patches/app/views/super_admin/settings
sudo mkdir -p /opt/chatwoot-patches/config/initializers
sudo mkdir -p /opt/chatwoot-patches/enterprise/app/services/llm
```

### Step 3: Copy Files from Local Repository

From your local machine, copy files one by one:

```bash
# Set production server
PROD="azureuser@your-production-server.com"

# Copy filter_service.rb
scp app/services/filter_service.rb $PROD:/opt/chatwoot-patches/app/services/filter_service.rb

# Copy show.html.erb
scp app/views/super_admin/settings/show.html.erb $PROD:/opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb

# Copy initializer
scp config/initializers/99_fix_pricing_plan_quantity.rb $PROD:/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb

# Copy base_open_ai_service.rb (if exists)
scp enterprise/app/services/llm/base_open_ai_service.rb $PROD:/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb
```

### Step 4: Set Permissions
```bash
ssh $PROD "sudo chown -R root:root /opt/chatwoot-patches && sudo chmod -R 755 /opt/chatwoot-patches"
```

---

## Option 2: Copy from Staging Server

If staging already has the files:

```bash
# Set servers
STAGING="azureuser@staging-server.com"
PROD="azureuser@production-server.com"

# Create directories on production
ssh $PROD "sudo mkdir -p /opt/chatwoot-patches/{app/services,app/views/super_admin/settings,config/initializers,enterprise/app/services/llm}"

# Copy from staging to production
ssh $STAGING "cat /opt/chatwoot-patches/app/services/filter_service.rb" | \
  ssh $PROD "sudo tee /opt/chatwoot-patches/app/services/filter_service.rb > /dev/null"

ssh $STAGING "cat /opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb" | \
  ssh $PROD "sudo tee /opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb > /dev/null"

ssh $STAGING "cat /opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb" | \
  ssh $PROD "sudo tee /opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb > /dev/null"

ssh $STAGING "cat /opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb" | \
  ssh $PROD "sudo tee /opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb > /dev/null"
```

---

## Option 3: Manual File Creation

If you need to create files manually, copy content from this repository:

### File 1: `/opt/chatwoot-patches/app/services/filter_service.rb`

Copy from: `app/services/filter_service.rb` in this repo

### File 2: `/opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb`

Copy from: `app/views/super_admin/settings/show.html.erb` in this repo

### File 3: `/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb`

Copy from: `config/initializers/99_fix_pricing_plan_quantity.rb` in this repo

### File 4: `/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb`

Copy from: `enterprise/app/services/llm/base_open_ai_service.rb` in this repo (if exists)  
OR from staging server if it's already there

---

## Verify Files

After copying, verify files exist:

```bash
# On production server
ls -la /opt/chatwoot-patches/app/services/filter_service.rb
ls -la /opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb
ls -la /opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb
ls -la /opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb
```

Or use the check script:
```bash
# Copy check script to production and run
scp deployment/check_production_patches.sh azureuser@production-server:/tmp/
ssh azureuser@production-server "bash /tmp/check_production_patches.sh"
```

---

## Quick Check Script Usage

### From Your Local Machine

```bash
# Check files on production
ssh azureuser@production-server "bash -s" < deployment/check_production_patches.sh
```

### Or Run on Production Server

```bash
# Copy script to production
scp deployment/check_production_patches.sh azureuser@production-server:/tmp/

# SSH to production
ssh azureuser@production-server

# Run check
bash /tmp/check_production_patches.sh
```

---

## Automated Copy Script Usage

### Copy from Local Repository

```bash
# Edit script to set PRODUCTION_HOST, then run:
bash deployment/copy_patches_to_production.sh
# Choose option 1
```

### Copy from Staging

```bash
# Edit script to set PRODUCTION_HOST, then run:
bash deployment/copy_patches_to_production.sh
# Choose option 2
# Enter staging server when prompted
```

---

## Troubleshooting

### Permission Denied
```bash
# Use sudo to create directories
sudo mkdir -p /opt/chatwoot-patches/...

# Or change ownership after creating
sudo chown -R root:root /opt/chatwoot-patches
```

### Files Already Exist
If files already exist and you want to overwrite:
```bash
# Use -f flag with scp
scp -f app/services/filter_service.rb azureuser@prod:/opt/chatwoot-patches/app/services/filter_service.rb
```

### Check File Contents
```bash
# Verify file content matches (first 10 lines)
head -10 /opt/chatwoot-patches/app/services/filter_service.rb
```
