# GuardianEye Ansible SOC Stack

Enterprise-grade Ansible automation for deploying a complete Security Operations Center (SOC) stack on Docker. This repository replaces the manual `tools.sh` bash installer with **fully idempotent, version-pinned, non-interactive** Ansible roles.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Docker Network: soc_net                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │    Wazuh     │  │   TheHive    │  │   Shuffle    │          │
│  │  SIEM/EDR    │  │ Case Mgmt    │  │    SOAR      │          │
│  │  :443/:55000 │  │  :8443/:9000 │  │ :3001/:5001  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                      OpenCTI                              │  │
│  │              Cyber Threat Intelligence                    │  │
│  │                      :8090                               │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 📋 Prerequisites

- **OS**: Ubuntu 20.04+ / Debian 11+
- **RAM**: Minimum 16GB (32GB recommended for all services)
- **Disk**: Minimum 100GB free space
- **Ansible**: 2.14.0+
- **Python**: 3.9+

## 🚀 Quick Start

### 1. Install Ansible (if not installed)

```bash
sudo apt update
sudo apt install -y python3-pip
pip3 install ansible
```

### 2. Clone this repository

```bash
git clone https://github.com/your-org/guardianeye-ansible-socstack.git
cd guardianeye-ansible-socstack
```

### 3. Install Ansible Galaxy collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 4. Review and customize configuration

```bash
# Edit group_vars/soc.yml to customize:
# - Ports
# - Directories  
# - Credentials
# - Image versions
nano group_vars/soc.yml
```

### 5. Run the deployment

```bash
# Full deployment (all services)
sudo ansible-playbook playbooks/deploy_socstack.yml

# Dry run (check mode)
sudo ansible-playbook playbooks/deploy_socstack.yml --check

# Verbose output
sudo ansible-playbook playbooks/deploy_socstack.yml -vv
```

## 🏷️ Using Tags

Deploy specific services using tags:

```bash
# Deploy only OpenCTI and Wazuh
sudo ansible-playbook playbooks/deploy_socstack.yml --tags opencti,wazuh

# Deploy only Shuffle
sudo ansible-playbook playbooks/deploy_socstack.yml --tags shuffle

# Deploy only prerequisites (Docker + network)
sudo ansible-playbook playbooks/deploy_socstack.yml --tags prerequisites

# Deploy all security tools (skip prerequisites if already done)
sudo ansible-playbook playbooks/deploy_socstack.yml --tags tools
```

### Available Tags

| Tag | Description |
|-----|-------------|
| `common` | System prerequisites |
| `docker_engine` | Docker CE installation |
| `soc_net` | Docker network creation |
| `opencti` | OpenCTI deployment |
| `shuffle` | Shuffle deployment |
| `thehive` | TheHive deployment |
| `wazuh` | Wazuh deployment |
| `prerequisites` | common + docker_engine + soc_net |
| `tools` | All security tools |

## 📁 Repository Structure

```
guardianeye-ansible-socstack/
├── ansible.cfg                    # Ansible configuration
├── requirements.yml               # Galaxy collection dependencies
├── inventory/
│   └── hosts.yml                  # Inventory (localhost by default)
├── group_vars/
│   └── soc.yml                    # All configuration variables
├── playbooks/
│   └── deploy_socstack.yml        # Main deployment playbook
└── roles/
    ├── common/                    # System prerequisites
    ├── docker_engine/             # Docker installation
    ├── soc_net/                   # Docker network
    ├── opencti/                   # OpenCTI deployment
    ├── shuffle/                   # Shuffle deployment
    ├── thehive/                   # TheHive deployment
    └── wazuh/                     # Wazuh deployment
```

## 🌐 Access URLs (Default Ports)

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| **Wazuh Dashboard** | https://localhost:443 | See config file |
| **Wazuh API** | https://localhost:55000 | See config file |
| **TheHive** | https://localhost:8443 | admin@thehive.local / secret |
| **Shuffle** | http://localhost:3001 | First-time setup required |
| **OpenCTI** | http://localhost:8090 | admin@opencti.local / ChangeMePlease |

## ⚙️ Post-Deployment Manual Steps

### 1. Shuffle Admin Setup (REQUIRED)

Shuffle requires initial admin account creation:

1. Navigate to http://localhost:3001/adminsetup
2. Create your admin username and password
3. Login at http://localhost:3001/login

### 2. Accept Self-Signed Certificates

For HTTPS services (Wazuh, TheHive), your browser will show a certificate warning. This is expected with self-signed certificates.

### 3. Wazuh Credentials

Wazuh generates credentials during installation. Find them at:

```bash
cat /root/wazuh-docker/single-node/config/wazuh_dashboard/wazuh.yml
```

### 4. Generate Wazuh API Token

```bash
# Get credentials from config
USERNAME=$(grep 'username:' /root/wazuh-docker/single-node/config/wazuh_dashboard/wazuh.yml | awk '{print $2}')
PASSWORD=$(grep 'password:' /root/wazuh-docker/single-node/config/wazuh_dashboard/wazuh.yml | awk '{print $2}' | tr -d '"')

# Generate token
TOKEN=$(curl -sk -u "$USERNAME:$PASSWORD" \
  -X POST "https://localhost:55000/security/user/authenticate?raw=true")
echo "Token: $TOKEN"
```

## 🔍 Verification Commands

### Check all containers

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Verify soc_net network

```bash
docker network inspect soc_net | jq '.[0].Containers'
```

### Check service health

```bash
# Wazuh
curl -sk https://localhost:443 | head -20

# TheHive
curl -sk https://localhost:8443

# Shuffle
curl -s http://localhost:3001

# OpenCTI
curl -s http://localhost:8090/health
```

## 🔧 Configuration Reference

All configuration is centralized in `group_vars/soc.yml`:

```yaml
# Key configuration options
timezone: "Asia/Karachi"
soc_network_name: "soc_net"

# Pinned Git Refs (for reproducible deployments)
wazuh_git_ref: "v4.14.0"
thehive_git_ref: "5.5.10"
shuffle_git_ref: "1.4.0"
opencti_git_ref: "6.4.4"

# Wazuh ports
wazuh_dashboard_port: 443
wazuh_api_port: 55000

# TheHive (Pinned image versions)
thehive_image_version: "5.5.10"
cassandra_image_version: "4.1"
elasticsearch_image_version: "8.11.3"

# Shuffle
shuffle_frontend_http_port: 3001
shuffle_frontend_https_port: 3443
shuffle_backend_port: 5001

# OpenCTI
opencti_web_port: 8090
opencti_admin_email: "admin@opencti.local"
opencti_admin_password: "ChangeMePlease"
elastic_memory_size: "4G"
```

## ♻️ Idempotency & Reproducibility

### Pinned Versions

All tool deployments use **pinned git refs** to ensure reproducible deployments:

| Tool | Git Ref | Why Pinned |
|------|---------|------------|
| Wazuh | `v4.14.0` | Matches tested, stable release |
| TheHive | `5.5.10` | Matches image version for consistency |
| Shuffle | `1.4.0` | Tested stable release |
| OpenCTI | `6.4.4` | Tested stable release |

### Non-Interactive Execution

All Ansible tasks run **non-interactively**:
- TheHive's `init.sh` and `check_permissions.sh` are piped with `yes Y |` and `printf`
- No prompts during execution
- Safe for CI/CD pipelines

### Idempotency Proof

Run the playbook twice to verify idempotency:

```bash
# First run - will show many "changed"
sudo ansible-playbook playbooks/deploy_socstack.yml

# Second run - should show mostly "ok" and very few "changed"
sudo ansible-playbook playbooks/deploy_socstack.yml
```

On the 2nd run, you should see:
- `ok` for already-completed tasks
- `changed` only for health checks (which always run)

## 🔒 Security Notes

1. **Change default passwords** in `group_vars/soc.yml` before production deployment
2. **Use strong passwords** for OpenCTI, Shuffle, and TheHive admin accounts
3. **Firewall rules**: Only expose necessary ports to your network
4. **TLS certificates**: Replace self-signed certificates with proper certificates for production

## 🐛 Troubleshooting

### Service won't start

```bash
# Check logs
cd /opt/opencti/docker && docker compose logs -f
cd /opt/shuffle && docker compose logs -f
cd /opt/thehive-docker/prod1-thehive && docker compose logs -f
cd /root/wazuh-docker/single-node && docker compose logs -f
```

### Port conflicts

If ports are already in use, modify the port variables in `group_vars/soc.yml` and re-run the playbook.

### Memory issues with Elasticsearch/OpenSearch

Adjust `elastic_memory_size` in `group_vars/soc.yml`. Minimum 4GB recommended.

### Ansible errors about docker_compose_v2

Ensure you've installed the required collections:

```bash
ansible-galaxy collection install -r requirements.yml --force
pip3 install docker docker-compose
```

## 📄 License

MIT License - See LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📞 Support

For issues and questions, please open a GitHub issue.
