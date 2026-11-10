IMG=ubuntu-24.04.5-preinstalled-server-arm64+raspi.img.xz
URL_IMG=https://cdimage.ubuntu.com/releases/24.04/release/${IMG}
# REPLACE WITH YOUR BOOT DISK (`lsblk`). Every node boots from a USB SSD (Cluster 2.0);
# node1 (SSD for data only), node2 and node4 boot from SD cards
USB=/dev/sda
SYSTEM_BOOT_MOUNT=/tmp/pi-disk
# node1: SD card OS, SSD1 formatted and mounted at /storage (RustFS, Vault)
USER_DATA_NODE1=user-data-node1
# node1 SSD1 name in /dev/disk/by-id (e.g. usb-Samsung_SSD_...-0:0), without partition suffix
SSD1_ID=
# k3s nodes: /storage is a directory on the boot disk
USER_DATA_NODES=user-data
NETWORK_CONFIG_NODES=network-config
# SSH public keys of the ansible user, one per line: the control host's
# (pimaster ~/.ssh/id_rsa.pub) and the break-glass key. Every node's user-data
# gets all of them; tasks/ansible_user.yml reads the same file
PUB_KEY_FILE=cloud-init/ansible.pub
# Home Wi-Fi (wlan0 backup uplink, 192.168.50.20N): pass on the command line
#   make prepare-node2 WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>'
WIFI_SSID=
WIFI_KEY=

.EXPORT_ALL_VARIABLES:

.PHONY: check-key
check-key:
	@grep -q '^ssh-' ${PUB_KEY_FILE} 2>/dev/null || { echo "Paste the ansible user's SSH public keys into metal/rpi/${PUB_KEY_FILE}, one per line"; exit 1; }

.PHONY: check-wifi
check-wifi:
	@test -n "$${WIFI_SSID}" -a -n "$${WIFI_KEY}" || { echo "Set WIFI_SSID and WIFI_KEY (home Wi-Fi, wlan0 backup uplink)"; exit 1; }

# Escape a shell variable for a YAML double-quoted string, then for the sed replacement
yaml_sed_escape = $$(printf '%s' "$${$(1)}" | sed -e 's/[\\"]/\\&/g' -e 's/[&|\\]/\\&/g')

# The keys of PUB_KEY_FILE as a YAML flow list of double-quoted strings, escaped
# for the sed replacement
pub_keys = [$$(grep -E '^(ssh-|ecdsa-)' ${PUB_KEY_FILE} | sed -e 's/[\\"]/\\&/g' -e 's/.*/"&"/' -e 's/[&|\\]/\\&/g' | paste -sd, -)]

# Render network-config to the boot partition. $(1): eth0 last octet, $(2): wlan0 last octet
# Not echoed: it contains the Wi-Fi password
define network_config
sed -e 's/NODE_OCTET/$(1)/' -e 's/WLAN_OCTET/$(2)/' \
	-e "s|WIFI_SSID|$(call yaml_sed_escape,WIFI_SSID)|" \
	-e "s|WIFI_KEY|$(call yaml_sed_escape,WIFI_KEY)|" \
	cloud-init/nodes/${NETWORK_CONFIG_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/network-config > /dev/null
endef

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
prepare-node1: check-key check-wifi
	@test -n "${SSD1_ID}" || { echo "Set SSD1_ID (ls -l /dev/disk/by-id/ on node1)"; exit 1; }
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node1/g' -e "s|SSH_PUB_KEYS|$(pub_keys)|g" -e 's|SSD1_ID|${SSD1_ID}|g' cloud-init/nodes/${USER_DATA_NODE1} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	$(call network_config,11,201)
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node2
prepare-node2: check-key check-wifi
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node2/g' -e "s|SSH_PUB_KEYS|$(pub_keys)|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	$(call network_config,12,202)
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node3
prepare-node3: check-key check-wifi
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node3/g' -e "s|SSH_PUB_KEYS|$(pub_keys)|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	$(call network_config,13,203)
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node4
prepare-node4: check-key check-wifi
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node4/g' -e "s|SSH_PUB_KEYS|$(pub_keys)|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	$(call network_config,14,204)
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node5
prepare-node5: check-key check-wifi
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node5/g' -e "s|SSH_PUB_KEYS|$(pub_keys)|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	$(call network_config,15,205)
	sudo umount ${SYSTEM_BOOT_MOUNT}

# Cluster 2.0: Pi 4 8 GB control-plane node (docs/plans/cluster-2.0.md)
.PHONY: prepare-node6
prepare-node6: check-key check-wifi
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed -e 's/nodeX/node6/g' -e "s|SSH_PUB_KEYS|$(pub_keys)|g" cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	$(call network_config,16,206)
	sudo umount ${SYSTEM_BOOT_MOUNT}
