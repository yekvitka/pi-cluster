.EXPORT_ALL_VARIABLES:

RUNNER := ansible-runner/ansible-runner.sh
ANSIBLE_DIR := ansible
ANSIBLE_LOCAL_ROLES_DIR := $(HOME)/.ansible/roles
ANSIBLE_LOCAL_COLLECTIONS_DIR := $(HOME)/.ansible/collections

.DEFAULT_GOAL := help

.PHONY: \
	help \
	default \
	prepare-ansible \
	ansible-runner-setup \
	secret-files \
	ansible-local-setup \
	ansible-local-galaxy \
	ansible-local-lint \
	ansible-local-syntax-check-external-services \
	uv-lock-check \
	lint \
	lint-ci \
	syntax-check-external-services \
	lint-fix-whitespace \
	init \
	os-upgrade \
	external-setup \
	nodes-setup \
	dns-setup \
	external-services \
	configure-os-backup \
	k3s-install \
	k3s-bootstrap \
	k3s-bootstrap-dev \
	deploy-vault \
	deploy-rustfs \
	configure-vault \
	configure-minio \
	load-external-services-keys \
	deploy-monitoring-agent \
	configure-cert-renewal \
	openwrt-certbot-tls \
	configure-webui-auth \
	configure-offsite-backup \
	configure-offsite-monitoring \
	os-backup \
	get-pi-status \
	install-local-utils \
	shutdown-k3s-worker \
	shutdown-k3s-master \
	shutdown-picluster \
	clean \
	k3s-reset \
	external-services-reset

help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9][a-zA-Z0-9_.-]*:.*##/ {printf "  %-32s %s\n", $$1, $$2}' $(firstword $(MAKEFILE_LIST))

default: help ## Alias for help

# Setup: the Ansible runner container, or a local uv environment

prepare-ansible: ansible-runner-setup secret-files ## Build the Ansible runner and create the secret files

ansible-runner-setup: ## Build the Ansible runner container
	$(MAKE) -C ansible-runner

secret-files: ## Create the local secret files (IONOS API key)
	$(RUNNER) ansible-playbook create_secret_files.yml

ansible-local-setup: ## Local uv environment with the Galaxy roles and collections
	cd $(ANSIBLE_DIR) && uv sync --frozen
	$(MAKE) ansible-local-galaxy

ansible-local-galaxy: ## Install the Galaxy roles and collections into the local uv environment
	cd $(ANSIBLE_DIR) && mkdir -p $(ANSIBLE_LOCAL_ROLES_DIR) $(ANSIBLE_LOCAL_COLLECTIONS_DIR)
	cd $(ANSIBLE_DIR) && uv run ansible-galaxy role install -r requirements.yml --roles-path "$(ANSIBLE_LOCAL_ROLES_DIR)" --timeout 600
	cd $(ANSIBLE_DIR) && uv run ansible-galaxy collection install -r requirements.yml --collections-path "$(ANSIBLE_LOCAL_COLLECTIONS_DIR)"

ansible-local-lint: ansible-local-setup ## yamllint with the local uv environment
	cd $(ANSIBLE_DIR) && uv run yamllint .

ansible-local-syntax-check-external-services: ansible-local-galaxy ## Syntax-check external_services.yml with the local uv environment
	cd $(ANSIBLE_DIR) && uv run ansible-playbook --syntax-check external_services.yml

uv-lock-check: ## Check that uv.lock matches pyproject.toml
	cd $(ANSIBLE_DIR) && uv lock --check

# Lint

lint: ## yamllint in the runner: Ansible and the Kubernetes manifests
	$(RUNNER) yamllint .
	$(RUNNER) bash -lc 'cd /kubernetes && yamllint .'

lint-ci: lint ## The lint CI runs

syntax-check-external-services: ansible-runner-setup ## Syntax-check external_services.yml in the runner
	cd ansible && ../$(RUNNER) ansible-playbook --syntax-check external_services.yml

lint-fix-whitespace: ## Trim trailing spaces and add final newlines in YAML files
	$(RUNNER) /bin/bash -lc 'cd /runner && find . -type f \( -name "*.yml" -o -name "*.yaml" \) ! -path "./.ansible/*" -print0 | xargs -0 sed -i -E "s/[[:space:]]+$$//"'
	$(RUNNER) /bin/bash -lc 'cd /runner && python3 -c "from pathlib import Path\nfor p in Path(\".\").rglob(\"*.yml\"):\n    if str(p).startswith(\".ansible/\"):\n        continue\n    b = p.read_bytes()\n    if b and not b.endswith(b\"\\n\"):\n        p.write_bytes(b + b\"\\n\")\nfor p in Path(\".\").rglob(\"*.yaml\"):\n    if str(p).startswith(\".ansible/\"):\n        continue\n    b = p.read_bytes()\n    if b and not b.endswith(b\"\\n\"):\n        p.write_bytes(b + b\"\\n\")"'

# Build from scratch (docs/build.md)

init: os-upgrade external-setup nodes-setup dns-setup external-services configure-os-backup deploy-monitoring-agent k3s-install k3s-bootstrap ## Build everything from scratch

os-upgrade: ## Upgrade the OS packages on every node
	$(RUNNER) ansible-playbook update.yml

external-setup: ## Prepare node1 for the external services
	$(RUNNER) ansible-playbook setup_picluster.yml --tags "external"

nodes-setup: ## Prepare the k3s nodes
	$(RUNNER) ansible-playbook setup_picluster.yml --tags "node"

dns-setup: ## Authoritative DNS (bind9) on node1
	$(RUNNER) ansible-playbook configure_dns_authoritative.yml

external-services: ## Vault and RustFS on node1, installed and configured
	$(RUNNER) ansible-playbook external_services.yml

configure-os-backup: ## Restic backups of every node to RustFS
	$(RUNNER) ansible-playbook backup_configuration.yml

k3s-install: ## Install k3s
	$(RUNNER) ansible-playbook k3s_install.yml

k3s-bootstrap: ## Install Flux and bootstrap the prod cluster
	$(RUNNER) ansible-playbook k3s_bootstrap.yml

k3s-bootstrap-dev: ## Install Flux and bootstrap the dev overlay
	$(RUNNER) ansible-playbook k3s_bootstrap.yml -e overlay=dev

# External services on node1, one step at a time

deploy-vault: ## Install Vault
	$(RUNNER) ansible-playbook deploy_vault.yml

deploy-rustfs: ## Install RustFS
	$(RUNNER) ansible-playbook deploy_rustfs.yml

configure-vault: ## Vault policies, Kubernetes auth and secrets (Terraform)
	$(RUNNER) ansible-playbook configure_vault.yml -e enable_kubernetes_auth=true

configure-minio: ## RustFS buckets, users and policies (Terraform)
	$(RUNNER) ansible-playbook configure_minio.yml

load-external-services-keys: ## Load the IONOS, DNS update, GitHub and basic-auth keys into Vault
	$(RUNNER) ansible-playbook load_external_services_keys.yml

deploy-monitoring-agent: ## Node and bind exporters on node1
	$(RUNNER) ansible-playbook deploy_monitoring_agent.yml

# Certificates, web UIs and offsite

configure-cert-renewal: ## Automatic Let's Encrypt renewal on node1 for Vault, RustFS and LuCI
	$(RUNNER) ansible-playbook cert_renewal.yml
	ssh root@10.0.0.1 "LUCI_CERT_PUBKEY='$$(ssh root@10.0.0.11 cat /root/.ssh/luci_cert_ed25519.pub)' sh -s" < metal/openwrt/script/luci-cert-receiver.sh
	ssh root@10.0.0.11 RENEWED_LINEAGE=/etc/letsencrypt/live/gateway.homelab.yekvitka.net /etc/letsencrypt/renewal-hooks/deploy/homelab-certs.sh

openwrt-certbot-tls: ## Issue the gateway (LuCI) certificate and deploy it
	$(RUNNER) ansible-playbook generate_gateway_tls_certificate.yml
	./metal/openwrt/script/openwrt-deploy-tls.sh

configure-webui-auth: ## Basic auth credentials (Vault) for Longhorn, Prometheus and Alertmanager UIs
	$(RUNNER) ansible-playbook configure_webui_auth.yml

configure-offsite-backup: ## Nightly restic copy of the RustFS backups to the Oracle Cloud VM
	$(RUNNER) ansible-playbook offsite_backup.yml

configure-offsite-monitoring: ## Gatus on the Oracle Cloud VM: checks the cluster from outside
	$(RUNNER) ansible-playbook offsite_monitoring.yml

# Operations

os-backup: ## Run the restic backup on every node now
	$(RUNNER) ansible -b -m shell -a 'systemctl start restic-backup' picluster

get-pi-status: ## Throttling and power status of every Pi
	$(RUNNER) ansible -b -m shell -a "pi_throttling" raspberrypi

install-local-utils: ## Install the CLI tools on this host (asks for sudo)
	cd ansible; ansible-playbook install_utilities_localhost.yml --ask-become-pass

shutdown-k3s-worker: ## Shut down the workers in 1 minute
	$(RUNNER) ansible -b -m shell -a "shutdown -h 1 min" k3s_worker

shutdown-k3s-master: ## Shut down the servers in 1 minute
	$(RUNNER) ansible -b -m shell -a "shutdown -h 1 min" k3s_master

shutdown-picluster: ## Shut down every node in 1 minute
	$(RUNNER) ansible -b -m shell -a "shutdown -h 1 min" picluster

# Destructive: only on purpose

clean: k3s-reset external-services-reset ## Destructive: remove k3s and the external services

k3s-reset: ## Destructive: remove k3s from every node
	$(RUNNER) ansible-playbook k3s_reset.yml

external-services-reset: ## Destructive: remove Vault and RustFS
	$(RUNNER) ansible-playbook reset_external_services.yml
