IMG=ubuntu-24.04.5-preinstalled-server-arm64+raspi.img.xz
URL_IMG=https://cdimage.ubuntu.com/releases/24.04/release/${IMG}
# REPLACE WITH YOUR SD CARD (`lsblk`). OS boots from SD card on all nodes
USB=/dev/sda
SYSTEM_BOOT_MOUNT=/tmp/pi-disk
# node1: SD card OS, SSD1 formatted and mounted at /storage (RustFS, Vault)
USER_DATA_NODE1=user-data-node1
# node1 SSD1 name in /dev/disk/by-id (e.g. usb-Samsung_SSD_...-0:0), without partition suffix
SSD1_ID=
# k3s nodes: /storage is an iSCSI LUN served by node1 (centralized SAN)
USER_DATA_NODES=user-data
NETWORK_CONFIG_NODES=network-config
# root SSH public key (pimaster ~/.ssh/id_rsa.pub), inserted into every node user-data
PUB_KEY_FILE=cloud-init/root.pub

.EXPORT_ALL_VARIABLES:

.PHONY: check-key
check-key:
	@grep -q '^ssh-' ${PUB_KEY_FILE} 2>/dev/null || { echo "Paste root SSH public key into metal/rpi/${PUB_KEY_FILE}"; exit 1; }

img/${IMG}:
	wget ${URL_IMG} -O img/${IMG}

.PHONY: wipe-disk
wipe-disk:
	sudo wipefs -a -f ${USB}

.PHONY: burn-image
burn-image:
	# `-d` decompress `<` redirect $FILE contents to expand `|` sending the output to `dd` to copy directly to $USB
	xz -d < img/${IMG} - | sudo dd bs=100M of=${USB}

.PHONY: mount-system-boot
mount-system-boot:
	sudo mkdir ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node1
prepare-node1: check-key
	@test -n "${SSD1_ID}" || { echo "Set SSD1_ID (ls -l /dev/disk/by-id/ on node1)"; exit 1; }
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node1/g' -e "s|SSH_PUB_KEY|$$(cat ${PUB_KEY_FILE})|g" -e 's|SSD1_ID|${SSD1_ID}|g' cloud-init/nodes/${USER_DATA_NODE1} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sed 's/X/11/g' cloud-init/nodes/${NETWORK_CONFIG_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/network-config
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node2
prepare-node2: check-key
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node2/g' -e "s|SSH_PUB_KEY|$$(cat ${PUB_KEY_FILE})|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sed 's/X/12/g' cloud-init/nodes/${NETWORK_CONFIG_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/network-config
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node3
prepare-node3: check-key
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node3/g' -e "s|SSH_PUB_KEY|$$(cat ${PUB_KEY_FILE})|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sed 's/X/13/g' cloud-init/nodes/${NETWORK_CONFIG_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/network-config
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node4
prepare-node4: check-key
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node4/g' -e "s|SSH_PUB_KEY|$$(cat ${PUB_KEY_FILE})|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sed 's/X/14/g' cloud-init/nodes/${NETWORK_CONFIG_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/network-config
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node5
prepare-node5: check-key
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node5/g' -e "s|SSH_PUB_KEY|$$(cat ${PUB_KEY_FILE})|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sed 's/X/15/g' cloud-init/nodes/${NETWORK_CONFIG_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/network-config
	sudo umount ${SYSTEM_BOOT_MOUNT}
