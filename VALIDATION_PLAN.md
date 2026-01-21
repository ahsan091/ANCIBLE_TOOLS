# GuardianEye Ansible SOC Stack - Production Validation Plan

## Document Purpose

This document provides a **complete, independent validation plan** to confirm the `guardianeye-ansible-socstack` Ansible repository works correctly on any Ubuntu 22.04 host. It is designed for production readiness validation.

---

# 1. Pre-Flight Checklist

Run these commands on the target Ubuntu 22.04 host **before** deployment. All must pass.

## 1.1 Operating System Verification

```bash
# Check OS version (must be Ubuntu 20.04+ or Debian 11+)
cat /etc/os-release | grep -E "^(NAME|VERSION)="

# Expected output:
# NAME="Ubuntu"
# VERSION="22.04.x LTS ..."
```

## 1.2 Hardware Requirements

```bash
# Check RAM (minimum 16GB, recommended 32GB)
free -h | grep Mem

# Expected: Mem should show >= 16Gi total
# Example: Mem:            31Gi       2.1Gi        28Gi

# Check available disk space (minimum 100GB free)
df -h / | awk 'NR==2 {print "Available: " $4}'

# Expected: Available: >= 100G

# Check CPU cores (minimum 4, recommended 8)
nproc

# Expected: 4 or higher
```

## 1.3 Network Requirements

```bash
# Check internet connectivity (required for git clone and docker pull)
curl -sI https://github.com | head -1

# Expected: HTTP/2 200

# Check DNS resolution
nslookup github.com

# Expected: Shows IP address without errors

# Check if required ports are available (not in use)
for port in 443 3001 3443 5001 8090 8443 9000 9001 9200 9201 55000; do
  if ss -ltn | grep -q ":${port} "; then
    echo "FAIL: Port $port is IN USE"
  else
    echo "OK: Port $port is available"
  fi
done

# Expected: All ports should show "OK: Port X is available"
```

## 1.4 Python and Pip

```bash
# Check Python 3 (required, version 3.9+)
python3 --version

# Expected: Python 3.10.x or higher

# Check pip3
pip3 --version

# Expected: pip 22.x or higher
# If missing: sudo apt install -y python3-pip
```

## 1.5 Ansible (Install if Needed)

```bash
# Check if Ansible is installed
ansible --version 2>/dev/null || echo "Ansible NOT installed"

# PREFERRED: Install via apt (enterprise standard)
sudo apt update
sudo apt install -y ansible

# FALLBACK: If you need Ansible 2.14+ and apt version is older:
# pip3 install --user ansible

# Verify Ansible version (must be 2.14.0+)
ansible --version | head -1

# Expected: ansible [core 2.14.x] or higher
```

## 1.6 Git

```bash
# Check git
git --version

# Expected: git version 2.x.x
# If missing: sudo apt install -y git
```

## 1.7 Docker Status (Optional)

```bash
# Check if Docker is already installed
docker --version 2>/dev/null && echo "INFO: Docker already installed (role will skip installation)" || echo "OK: Docker not installed (role will install it)"

# Note: If Docker is already installed, the playbook detects it and skips installation.
# This is safe - the role is idempotent either way.
```

## 1.8 Root/Sudo Access

```bash
# Verify sudo works
sudo whoami

# Expected: root
```

---

# 2. Step-by-Step Test Execution Plan

Execute these commands **in order** on a clean Ubuntu 22.04 VM.

## 2A. Install Ansible + Git

```bash
# Update packages
sudo apt update

# Install Ansible, Python3, pip, and git (enterprise method)
sudo apt install -y ansible git python3 python3-pip

# Fallback if apt Ansible is too old (< 2.14):
# pip3 install --user ansible

# Verify installation
ansible --version
```

**Expected Output:**
```
ansible [core 2.14.x]
  config file = None
  ...
```

## 2B. Clone Repository

```bash
# ────────────────────────────────────────────────────────────────────
# OPTION A: Clone from GitHub/GitLab (production)
# ────────────────────────────────────────────────────────────────────
git clone https://github.com/your-org/guardianeye-ansible-socstack.git
cd guardianeye-ansible-socstack

# ────────────────────────────────────────────────────────────────────
# OPTION B: Copy local folder (for testing/development)
# ────────────────────────────────────────────────────────────────────
sudo cp -a /home/guardianeye/G/guardianeye-ansible-socstack /opt/
cd /opt/guardianeye-ansible-socstack

# ────────────────────────────────────────────────────────────────────
# OPTION C: Work directly in existing folder (development)
# ────────────────────────────────────────────────────────────────────
cd /home/guardianeye/G/guardianeye-ansible-socstack

# Verify structure
ls -la
```

**Expected Output:**
```
ansible.cfg
group_vars/
inventory/
playbooks/
README.md
requirements.yml
roles/
```

## 2C. Install Galaxy Collections

```bash
# Install required collections
ansible-galaxy collection install -r requirements.yml

# Verify collections installed
ansible-galaxy collection list | grep -E "(community.docker|community.general|ansible.posix)"
```

**Expected Output:**
```
community.docker          3.x.x
community.general         8.x.x
ansible.posix             1.x.x
```

## 2D. Test Ansible Connectivity

```bash
# Test local connection (since we deploy to localhost)
cd /home/guardianeye/G/guardianeye-ansible-socstack
ansible -i inventory/hosts.yml -m ping soc
```

**Expected Output:**
```
localhost | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

## 2E. Run Playbook in Check Mode (Dry Run)

```bash
# Dry run - shows what WOULD change without making changes
sudo ansible-playbook playbooks/deploy_socstack.yml --check
```

**Expected Behavior:**
- Many tasks will show `changed` or `skipping` (normal for check mode)
- Some tasks will FAIL in check mode (e.g., docker_compose_v2 can't run in check mode without Docker)
- **This is informational only - do not expect full success in check mode**

**What to Look For:**
- No syntax errors
- Variable resolution works (no "undefined variable" errors)
- Role execution order is correct

## 2F. Run Full Deployment

```bash
# Full deployment (THIS IS THE REAL TEST)
cd /home/guardianeye/G/guardianeye-ansible-socstack
sudo ansible-playbook playbooks/deploy_socstack.yml

# With verbose output if debugging:
# sudo ansible-playbook playbooks/deploy_socstack.yml -vv
```

**Expected Duration:** 15-30 minutes (depending on internet speed for docker pulls)

**Expected Output (end of run):**
```
PLAY RECAP *********************************************************************
localhost                  : ok=XX   changed=YY   unreachable=0    failed=0    skipped=ZZ   rescued=0    ignored=WW
```

**Success Criteria:**
- `failed=0` ✅
- `unreachable=0` ✅
- Task summary shows deployment complete message with URLs

## 2G. Run Playbook Second Time (Idempotency Proof)

```bash
# Run again - should show mostly "ok", very few "changed"
sudo ansible-playbook playbooks/deploy_socstack.yml
```

**Expected Output:**
```
PLAY RECAP *********************************************************************
localhost                  : ok=XX   changed=<5   unreachable=0    failed=0    ...
```

**Idempotency Criteria:**
- `changed` count should be **less than 5** (only health checks and debug messages)
- Most tasks should show `ok` (already in desired state)
- No `failed` tasks ✅

## 2H. Run Selective Deployment with Tags

```bash
# Deploy only OpenCTI and Wazuh (should skip Shuffle and TheHive)
sudo ansible-playbook playbooks/deploy_socstack.yml --tags opencti,wazuh

# Deploy only prerequisites
sudo ansible-playbook playbooks/deploy_socstack.yml --tags prerequisites

# Skip a specific tool
sudo ansible-playbook playbooks/deploy_socstack.yml --skip-tags shuffle
```

**Expected Behavior:**
- Only selected roles execute
- Skipped roles show no output
- Common role runs (has `always` tag)

## 2I. Stop/Start Each Stack Using Docker Compose

```bash
# WAZUH
cd /root/wazuh-docker/single-node
docker compose ps              # Check status
docker compose stop            # Stop gracefully
docker compose start           # Start again
docker compose down            # Stop and remove containers
docker compose up -d           # Recreate and start

# THEHIVE
cd /opt/thehive-docker/prod1-thehive
docker compose ps
docker compose stop
docker compose start
docker compose down
docker compose up -d

# SHUFFLE
cd /opt/shuffle
docker compose ps
docker compose stop
docker compose start
docker compose down
docker compose up -d

# OPENCTI
cd /opt/opencti/docker
docker compose ps
docker compose stop
docker compose start
docker compose down
docker compose up -d
```

---

# 3. Post-Deploy Verification Commands

## 3.1 Check All Containers

```bash
# List all running containers with names, status, and ports
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Expected Containers Per Tool:**

| Tool | Container Names (partial match) |
|------|--------------------------------|
| **Wazuh** | `wazuh.manager`, `wazuh.indexer`, `wazuh.dashboard` |
| **TheHive** | `thehive`, `cassandra`, `elasticsearch`, `nginx`, `cortex` |
| **Shuffle** | `shuffle-frontend`, `shuffle-backend`, `shuffle-orborus`, `shuffle-opensearch` |
| **OpenCTI** | `opencti`, `redis`, `elasticsearch`, `minio`, `rabbitmq`, `worker`, `connector-*` |

```bash
# Count containers (should be 15-25+ depending on connectors)
docker ps --format "{{.Names}}" | wc -l

# Expected: 15 or more
```

## 3.2 Verify soc_net Network

```bash
# Check network exists
docker network ls | grep soc_net

# Expected: Shows soc_net with bridge driver

# List all containers on soc_net
docker network inspect soc_net --format '{{range .Containers}}{{.Name}} {{end}}'

# OR with JSON output:
docker network inspect soc_net | jq '.[0].Containers | keys'

# Expected: Should list containers from ALL tools
```

## 3.3 Endpoint Health Checks

```bash
# WAZUH DASHBOARD (HTTPS with self-signed cert)
curl -sk https://localhost:443 | head -5
# Expected: HTML content or redirect

# WAZUH API (HTTPS with self-signed cert)
curl -sk https://localhost:55000
# Expected: JSON with "title": "Wazuh API REST" or 401 Unauthorized

# THEHIVE (HTTPS with self-signed cert)
curl -sk https://localhost:8443
# Expected: HTML content or redirect to login

# SHUFFLE (HTTP)
curl -s http://localhost:3001 | head -5
# Expected: HTML content (React app)

# SHUFFLE BACKEND
curl -s http://localhost:5001/api/v1/health 2>/dev/null || echo "Backend may not expose /health"
# Expected: Health status or empty (not all versions expose this)

# OPENCTI
curl -s http://localhost:8090/health
# Expected: {"status":"ok"} or similar

# OPENCTI LOGIN PAGE
curl -s http://localhost:8090 | head -10
# Expected: HTML content
```

## 3.4 Find Credentials

### Wazuh Credentials

```bash
# Dashboard username/password
cat /root/wazuh-docker/single-node/config/wazuh_dashboard/wazuh.yml | grep -E "(username|password)"

# Expected output:
# username: wazuh-wui
# password: <some-password>
```

### TheHive Credentials

```bash
# Default credentials (from playbook)
echo "Email: admin@thehive.local"
echo "Password: secret"

# Check env file
cat /opt/thehive-docker/prod1-thehive/.env
```

### OpenCTI Credentials

```bash
# From env file
cat /opt/opencti/docker/.env | grep -E "(ADMIN_EMAIL|ADMIN_PASSWORD|ADMIN_TOKEN)"

# Expected:
# OPENCTI_ADMIN_EMAIL=admin@opencti.local
# OPENCTI_ADMIN_PASSWORD=ChangeMePlease
# OPENCTI_ADMIN_TOKEN=<uuid>
```

### Shuffle Setup

```bash
# Shuffle requires manual admin setup
echo "╔═══════════════════════════════════════════════════╗"
echo "║  SHUFFLE: Navigate to http://localhost:3001/adminsetup  ║"
echo "║  Create your admin account there                   ║"
echo "╚═══════════════════════════════════════════════════╝"
```

## 3.5 Log Commands (For Troubleshooting)

```bash
# WAZUH logs
cd /root/wazuh-docker/single-node && docker compose logs -f --tail=100

# Specific Wazuh component
docker compose logs -f wazuh.manager
docker compose logs -f wazuh.dashboard

# THEHIVE logs
cd /opt/thehive-docker/prod1-thehive && docker compose logs -f --tail=100

# SHUFFLE logs
cd /opt/shuffle && docker compose logs -f --tail=100

# Specific Shuffle component
docker compose logs -f shuffle-backend

# OPENCTI logs
cd /opt/opencti/docker && docker compose logs -f opencti --tail=100

# All OpenCTI components
docker compose logs -f --tail=50
```

---

# 4. Failure Handling Playbook

## 4.1 Git Clone Fails / Tag Not Found

**Symptom:**
```
fatal: Remote branch 'x.y.z' not found in upstream origin
```

**Diagnosis:**
```bash
# Check what tags exist for the repo
git ls-remote --tags https://github.com/OpenCTI-Platform/docker.git | tail -20
git ls-remote --tags https://github.com/Shuffle/Shuffle.git | tail -20
git ls-remote --tags https://github.com/StrangeBeeCorp/docker.git | tail -20
git ls-remote --tags https://github.com/wazuh/wazuh-docker.git | tail -20
```

**Fix:**
```bash
# Edit group_vars/soc.yml and update to a valid tag
nano /home/guardianeye/G/guardianeye-ansible-socstack/group_vars/soc.yml

# Find and update:
# opencti_git_ref: "6.4.4"  # Change to valid tag
# shuffle_git_ref: "1.4.0"  # Change to valid tag
```

## 4.2 Ports Are In Use

**Symptom:**
```
Error: bind: address already in use
```

**Diagnosis:**
```bash
# Find what's using the port
sudo ss -tlnp | grep ":8090 "
sudo lsof -i :8090

# Example output: Shows PID and process name
```

**Fix Option 1 - Kill the process:**
```bash
sudo kill -9 <PID>
```

**Fix Option 2 - Change port in group_vars:**
```bash
# Edit group_vars/soc.yml
nano /home/guardianeye/G/guardianeye-ansible-socstack/group_vars/soc.yml

# Change the port variable (e.g., opencti_web_port: 8091)
```

**Fix Option 3 - Stop conflicting service:**
```bash
# If it's another docker compose stack
docker compose -f /path/to/other/docker-compose.yml down
```

## 4.3 docker_compose_v2 Fails

**Symptom:**
```
TASK [opencti : Deploy OpenCTI stack] ******************************************
fatal: [localhost]: FAILED! => {"changed": false, "msg": "..."}
```

**Diagnosis:**
```bash
# Check if docker compose works manually
cd /opt/opencti/docker
docker compose config    # Validates compose file
docker compose up -d     # Try manual start
docker compose logs      # Check for errors

# Common issues:
# 1. Missing .env file
# 2. Invalid compose syntax
# 3. Image pull failures
```

**Fix - Missing .env:**
```bash
# Re-run only that role
sudo ansible-playbook playbooks/deploy_socstack.yml --tags opencti -vv
```

**Fix - Docker not running:**
```bash
sudo systemctl status docker
sudo systemctl start docker
```

**Fix - Python docker module missing:**
```bash
pip3 install docker docker-compose
```

## 4.4 Health Check Fails

**Symptom:**
```
TASK [opencti : Wait for OpenCTI to be ready] **********************************
FAILED - RETRYING: Wait for OpenCTI to be ready (29 retries left).
...
fatal: [localhost]: FAILED! => {"msg": "..."}
```

**Diagnosis:**
```bash
# Check if container is running
docker ps | grep opencti

# Check container logs
cd /opt/opencti/docker && docker compose logs opencti --tail=50

# Common causes:
# 1. Container crashed (check logs)
# 2. Not enough memory (check sysctl and docker stats)
# 3. Dependency not ready (Elasticsearch, Redis, etc.)
```

**Fix - Memory issues:**
```bash
# Check memory
free -h
docker stats --no-stream

# If Elasticsearch OOM, increase memory:
echo "vm.max_map_count=1048575" | sudo tee /etc/sysctl.d/99-socstack.conf
sudo sysctl -p /etc/sysctl.d/99-socstack.conf
```

**Fix - Restart the stack:**
```bash
cd /opt/opencti/docker
docker compose down
docker compose up -d
```

## 4.5 Sysctl Fails

**Symptom:**
```
TASK [common : Set vm.max_map_count for Elasticsearch/OpenSearch] **************
fatal: [localhost]: FAILED! => {"msg": "..."}
```

**Diagnosis:**
```bash
# Check current value
sysctl vm.max_map_count

# Check if file exists
cat /etc/sysctl.d/99-socstack.conf
```

**Fix:**
```bash
# Manually set it
sudo sysctl -w vm.max_map_count=1048575
echo "vm.max_map_count=1048575" | sudo tee /etc/sysctl.d/99-socstack.conf
sudo sysctl --system
```

---

# 5. Independence Proof

## 5.1 No GuardianEye Dependencies

The Ansible repository is **completely independent** of any GuardianEye Django/Postgres application.

**Proof:**

```bash
# Search for any Django, Postgres, or GuardianEye app references
cd /home/guardianeye/G/guardianeye-ansible-socstack
grep -rni "django\|postgres\|guardianeye_app\|manage.py\|wsgi\|asgi" .

# Expected: NO OUTPUT (no matches)
# The only "GuardianEye" references are in comments/names, not app dependencies
```

## 5.2 Portable to Any Ubuntu 22.04 Host

**Proof:**

```bash
# Check what the playbook actually requires:
# 1. inventory/hosts.yml - targets localhost or any host you configure
# 2. group_vars/soc.yml - configurable settings, no hardcoded external dependencies
# 3. All roles use: apt, pip, git, docker - standard tools available on any Ubuntu

# The inventory can be changed to target remote hosts:
cat inventory/hosts.yml

# To deploy on a remote host, change to:
# all:
#   children:
#     soc:
#       hosts:
#         remote-vm.example.com:
#           ansible_user: ubuntu
#           ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

## 5.3 Self-Contained Verification

```bash
# Copy the repo to a completely fresh VM
scp -r guardianeye-ansible-socstack user@fresh-vm:/tmp/

# SSH to fresh VM
ssh user@fresh-vm

# Run there
cd /tmp/guardianeye-ansible-socstack
pip3 install ansible
ansible-galaxy collection install -r requirements.yml
sudo ansible-playbook playbooks/deploy_socstack.yml

# It should work identically
```

---

# 6. Final Acceptance Criteria

## Acceptance Checklist

Copy and fill this checklist after validation:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│              GUARDIANEYE ANSIBLE SOC STACK - ACCEPTANCE CHECKLIST            │
├──────────────────────────────────────────────────────────────────────────────┤
│ Date: ____________________  Validator: __________________                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│ PRE-FLIGHT CHECKS                                                            │
│ [ ] Ubuntu 22.04 verified                                                    │
│ [ ] RAM >= 16GB                                                              │
│ [ ] Disk >= 100GB free                                                       │
│ [ ] All required ports available                                             │
│ [ ] Internet connectivity OK                                                 │
│ [ ] Python 3.9+ installed                                                    │
│ [ ] Ansible 2.14+ installed                                                  │
│                                                                              │
│ DEPLOYMENT                                                                   │
│ [ ] Galaxy collections installed successfully                                │
│ [ ] ansible -m ping returns SUCCESS                                          │
│ [ ] Full playbook run completed with failed=0                                │
│                                                                              │
│ IDEMPOTENCY                                                                  │
│ [ ] Second playbook run shows changed < 5                                    │
│ [ ] Third playbook run shows same changed count as second                    │
│                                                                              │
│ PINNED VERSIONS                                                              │
│ [ ] group_vars/soc.yml contains *_git_ref variables with specific versions  │
│ [ ] All role git tasks use version: "{{ *_git_ref }}"                       │
│ [ ] TheHive .env contains pinned image versions                              │
│                                                                              │
│ NON-INTERACTIVE                                                              │
│ [ ] Playbook runs without any user prompts                                   │
│ [ ] TheHive scripts run with yes/printf piping                               │
│ [ ] Safe for CI/CD pipeline execution                                        │
│                                                                              │
│ SERVICES RUNNING                                                             │
│ [ ] docker ps shows 15+ containers                                           │
│ [ ] docker network inspect soc_net shows containers from all 4 tools        │
│                                                                              │
│ HEALTH CHECKS                                                                │
│ [ ] Wazuh Dashboard responds: curl -sk https://localhost:443                 │
│ [ ] Wazuh API responds: curl -sk https://localhost:55000                     │
│ [ ] TheHive responds: curl -sk https://localhost:8443                        │
│ [ ] Shuffle responds: curl -s http://localhost:3001                          │
│ [ ] OpenCTI responds: curl -s http://localhost:8090/health                   │
│                                                                              │
│ TAGS WORK                                                                    │
│ [ ] --tags opencti,wazuh runs only those two roles                          │
│ [ ] --skip-tags shuffle skips Shuffle                                        │
│                                                                              │
│ CREDENTIALS ACCESSIBLE                                                       │
│ [ ] Wazuh: /root/wazuh-docker/single-node/config/wazuh_dashboard/wazuh.yml  │
│ [ ] TheHive: admin@thehive.local / secret                                    │
│ [ ] OpenCTI: /opt/opencti/docker/.env shows credentials                     │
│ [ ] Shuffle: /adminsetup URL accessible                                      │
│                                                                              │
│ INDEPENDENCE                                                                 │
│ [ ] No Django/Postgres/GuardianEye app dependencies in codebase             │
│ [ ] Can be copied and run on any Ubuntu 22.04 host                          │
│                                                                              │
│ DOCKER COMPOSE CONTROL                                                       │
│ [ ] Each tool can be stopped with docker compose stop                        │
│ [ ] Each tool can be restarted with docker compose up -d                     │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ FINAL RESULT: [ ] PASS  [ ] FAIL                                            │
│                                                                              │
│ Notes: _________________________________________________________________     │
│ ________________________________________________________________________     │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

# Quick Reference Card

```bash
# ============== QUICK DEPLOYMENT COMMANDS ==============

# 1. Install prerequisites (enterprise method)
sudo apt update && sudo apt install -y ansible git python3 python3-pip
ansible-galaxy collection install -r requirements.yml

# 2. Full deployment (with audit trail logging)
sudo ansible-playbook playbooks/deploy_socstack.yml 2>&1 | tee /var/log/guardianeye-socstack-deploy.log

# 3. Idempotency test (run second time)
sudo ansible-playbook playbooks/deploy_socstack.yml 2>&1 | tee -a /var/log/guardianeye-socstack-deploy.log

# 4. Check containers
docker ps --format "table {{.Names}}\t{{.Status}}"

# 5. Check network
docker network inspect soc_net | jq '.[0].Containers | keys'

# 6. Health checks
curl -sk https://localhost:443       # Wazuh
curl -sk https://localhost:8443      # TheHive
curl -s http://localhost:3001        # Shuffle
curl -s http://localhost:8090/health # OpenCTI

# 7. View logs (if issues)
cd /opt/opencti/docker && docker compose logs -f
cd /opt/shuffle && docker compose logs -f
cd /opt/thehive-docker/prod1-thehive && docker compose logs -f
cd /root/wazuh-docker/single-node && docker compose logs -f

# 8. Stop/start individual tools
cd /opt/opencti/docker && docker compose down && docker compose up -d

# 9. View audit trail
cat /var/log/guardianeye-socstack-deploy.log
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-01-21  
**Author:** Ansible Automation Team
