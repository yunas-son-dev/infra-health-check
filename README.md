# infra-health-check

A toolkit for automated Linux server hardware diagnostics, combining a standalone Bash script for ad-hoc investigation and Ansible playbooks for scheduled, large-scale health checks — with Jenkins pipeline integration for alert-driven automation.

---

## Features

- Diagnoses CPU, RAM, disk, NIC, PSU, CMOS battery, and BIOS settings on remote Linux servers
- Runs all checks in parallel via background jobs for fast results
- Color-coded terminal output with clear PASS / FAIL summary per server
- Ansible roles map directly to alert types (e.g. `alertname:high_mem` → `ram_check.yaml`)
- Jenkins pipeline runs playbooks in parallel across multiple machines and posts results to a Zendesk ticket as an HTML summary

---

## Tech Stack

- Bash, SSH
- Ansible
- Jenkins (declarative pipeline)
- Zendesk API (ticket updates via HTML comment)
- Prometheus (alert source)
- Docker (Ansible execution environment in Jenkins)

---

## Project Structure

```
infra-health-check/
├── bash/
│   └── machine_report.sh          # Standalone script for ad-hoc server diagnostics
├── ansible/
│   ├── playbooks/                 # One playbook per hardware check
│   │   ├── ram_check.yaml
│   │   ├── cpu_diagnosis.yml
│   │   ├── drive_diagnosis.yml
│   │   ├── psu_check.yaml
│   │   ├── fan_speed.yaml
│   │   └── network_logs.yaml
│   ├── roles/                     # Reusable roles consumed by playbooks
│   │   ├── ram_check/
│   │   ├── cpu_diagnosis/
│   │   └── ...
│   ├── deploy/
│   │   └── alert-playbook-automation/  # Jenkinsfile for CI/CD pipeline
│   └── ansible.cfg
├── .gitignore
└── README.md
```

---

## How It Works

### Bash — ad-hoc diagnostics

`machine_report.sh` SSHs into a target server and runs all checks in parallel as background jobs, writing each result to a temp file. Once all jobs finish, it prints a consolidated report and a final PASS / FAIL result.

```bash
./bash/machine_report.sh <server-ip>
```

Checks covered:

| Category | Checks |
|----------|--------|
| CPU | Frequency, temperature, turbo boost, hyper-threading, C-state, load average, high-usage processes |
| RAM | Usage, size, syslog/dmesg error scan |
| Disk | I/O errors, space usage, write speed (1 GB dd test), SMARTctl, SATA cable errors |
| Network | NIC error rate per interface (>1% threshold triggers warning) |
| Hardware | PSU status (ipmitool), CMOS battery |
| Services | Configurable systemd service health check |

Each check prints a colored WARNING in red if it exceeds its threshold. The final line shows either `PASSED` (green) or `FAILED` (red) based on whether any WARNING was found.

---

### Ansible — scheduled / large-scale checks

Playbooks are organized so each one maps to a specific alert type. The alert-to-playbook mapping is defined in the Jenkins pipeline:

| Alert | Playbooks triggered |
|-------|-------------------|
| `alertname:nic_errors` | `network_logs.yaml` |
| `alertname:cpu_freq` | `cpu_diagnosis.yml`, `psu_check.yaml` |
| `alertname:cpu_idle` | `cpu_diagnosis.yml`, `drive_diagnosis.yml` |
| `alertname:cpu_temp` | `drive_diagnosis.yml`, `psu_check.yaml`, `fan_speed.yaml` |
| `alertname:high_mem` | `ram_check.yaml`, `psu_check.yaml` |
| `alertname:mem_error` | `ram_check.yaml` |

Each role encapsulates the tasks for its check and is designed to be reusable across multiple playbooks.

---

### Jenkins pipeline — alert-driven automation

The pipeline in `deploy/alert-playbook-automation/` ties everything together:

```
Prometheus alert fires
        │
        ▼
Jenkins pipeline triggered
  ├── Initialize       clone repo, validate parameters
  ├── Prepare          map alert name → playbooks, fetch server details
  ├── Execute          run playbooks in parallel (one sub-job per machine × playbook)
  └── Final update     post HTML results table to Zendesk ticket
```

The pipeline accepts these parameters: `MachineID` (comma-separated), `ZDTicketID`, `AlertNameTag`, and `Branch`. Each machine-playbook combination runs as an independent sub-job so failures are isolated and logged separately.

---

## Local Development

**Bash script** — requires SSH access to a target Linux server:

```bash
chmod +x bash/machine_report.sh
./bash/machine_report.sh <server-ip>
```

**Ansible** — requires Ansible installed and SSH access configured:

```bash
# Install dependencies
pip install ansible-lint yamllint
ansible-galaxy install -r docker/ansible_requirements.yaml

# Run a playbook manually
ansible-playbook ansible/playbooks/ram_check.yaml -i <inventory>
```

**Linting:**

```bash
ansible-lint ansible/playbooks/
yamllint ansible/
```

---

## To-Do

- Add inventory file example for Ansible
- Add `--dry-run` flag to bash script
- Expand `SERVICES` array in `machine_report.sh` to support custom service lists via argument
- Add GitHub Actions workflow for linting on PR