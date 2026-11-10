.PHONY: default check-user create-local-directories start-ansible-runner
LOCAL_DIRS := ${HOME}/.ansible ${HOME}/.ansible/collections ${HOME}/.ansible/roles ${HOME}/.secrets ${HOME}/.ssh ${HOME}/.kube ${HOME}/.certbot/log ${HOME}/.certbot/config ${HOME}/.certbot/work

default: start-ansible-runner

# The runner mounts $HOME/.ssh, .secrets and .kube: run it as the user who owns
# them, never as root
check-user:
	@if [ "$$(id -u)" = 0 ]; then echo "Run as your user, not root (HOME=${HOME}). From a root shell: sudo -u <user> -H make ansible-runner-setup"; exit 1; fi

create-local-directories: check-user
	mkdir -p ${LOCAL_DIRS}
	# Mounted as a file: Docker would create a directory if it were missing
	touch ${HOME}/.ssh/known_hosts

${HOME}/.ssh/id_rsa:
	ssh-keygen -t rsa -P '' -f ${HOME}/.ssh/id_rsa

start-ansible-runner: create-local-directories ${HOME}/.ssh/id_rsa
	# --build: a changed Dockerfile reaches the running container (layer cache)
	docker compose up --detach --build