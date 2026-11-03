#!/bin/sh
# Receiver for the LuCI certificate renewed on node1 (ansible/cert_renewal.yml).
# node1 pushes fullchain.pem + privkey.pem (tar.gz on stdin) with its own SSH key;
# dropbear restricts that key to the install script (forced command, no shell,
# no forwarding). The IONOS API key stays on node1.
#
# Run on the gateway as root, safe to re-run (make configure-cert-renewal does it):
#   ssh root@10.0.0.1 "LUCI_CERT_PUBKEY='<node1 /root/.ssh/luci_cert_ed25519.pub>' sh -s" < luci-cert-receiver.sh
set -e
[ -n "$LUCI_CERT_PUBKEY" ] || { echo "set LUCI_CERT_PUBKEY"; exit 1; }
echo "$LUCI_CERT_PUBKEY" | grep -q '^ssh-ed25519 .* luci-cert@node1$' || { echo "unexpected key: $LUCI_CERT_PUBKEY"; exit 1; }

# Under /etc: kept by sysupgrade
mkdir -p /etc/luci-cert
cat > /etc/luci-cert/install.sh <<'EOS'
#!/bin/sh
# Installs the LuCI certificate pushed by node1 (see /etc/dropbear/authorized_keys)
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tar -xzf - -C "$tmp" fullchain.pem privkey.pem
grep -q 'BEGIN CERTIFICATE' "$tmp/fullchain.pem"
grep -q 'PRIVATE KEY' "$tmp/privkey.pem"
sum() { [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1; }
if [ "$(sum "$tmp/fullchain.pem")" = "$(sum /etc/uhttpd.crt)" ] && [ "$(sum "$tmp/privkey.pem")" = "$(sum /etc/uhttpd.key)" ]; then
  echo "luci certificate unchanged"
  exit 0
fi
cp "$tmp/privkey.pem" /etc/uhttpd.key
chmod 600 /etc/uhttpd.key
cp "$tmp/fullchain.pem" /etc/uhttpd.crt
chmod 644 /etc/uhttpd.crt
/etc/init.d/uhttpd restart
echo "luci certificate installed, uhttpd restarted"
EOS
chmod 700 /etc/luci-cert/install.sh

# Replace the node1 entry only, the other keys stay as they are
AK=/etc/dropbear/authorized_keys
touch "$AK"
sed -i '/ luci-cert@node1$/d' "$AK"
echo "command=\"/etc/luci-cert/install.sh\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $LUCI_CERT_PUBKEY" >> "$AK"
chmod 600 "$AK"
echo "luci certificate receiver ready ($(grep -c '' "$AK") authorized keys)"
