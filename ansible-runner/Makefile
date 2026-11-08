.PHONY: default create-local-directories start-ansible-runner
LOCAL_DIRS := ${HOME}/.ansible ${HOME}/.ansible/collections ${HOME}/.ansible/roles ${HOME}/.secrets ${HOME}/.ssh ${HOME}/.kube ${HOME}/.certbot/log ${HOME}/.certbot/config ${HOME}/.certbot/work

default: start-ansible-runner

create-local-directories:
	mkdir -p ${LOCAL_DIRS}
	# Mounted as a file: Docker would create a directory if it were missing
	touch ${HOME}/.ssh/known_hosts

${HOME}/.ssh/id_rsa:
	ssh-keygen -t rsa -P '' -f ${HOME}/.ssh/id_rsa

start-ansible-runner: create-local-directories ${HOME}/.ssh/id_rsa
	docker compose up --detach