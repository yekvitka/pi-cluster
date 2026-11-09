.EXPORT_ALL_VARIABLES:

.PHONY: load-kernel-modules
load-kernel-modules:
	sudo modprobe -v iptable_filter
	sudo modprobe -v ip_tables
	sudo modprobe -v iptable_mangle
	sudo modprobe -v iptable_raw
	sudo modprobe -v iptable_nat
	sudo modprobe -v xt_socket

.PHONY: create-k3d
create-k3d:
	./create_cluster.sh

.PHONY: delete-k3d
delete-k3d:
	k3d cluster delete picluster
	docker network rm picluster
	rm -f kubeconfig
