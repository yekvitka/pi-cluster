#!/bin/bash

# This script generates a TSIG key for secure DNS updates

# Generate a TSIG key using dnssec-keygen (part of BIND9 utilities)
KEYNAME="externaldns-key"
ALGORITHM="hmac-sha256"
OUTDIR="/tmp/tsig-keys"

# Create temporary directory
mkdir -p "${OUTDIR}"
cd "${OUTDIR}" || { echo "Failed to change to output directory"; exit 1; }

# Check if BIND utilities are installed
if ! command -v dnssec-keygen &> /dev/null; then
    echo "BIND9 utilities not found. Installing bind9utils..."
    apt-get update && apt-get install -y bind9utils
fi

# Generate the key using dnssec-keygen
echo "Generating TSIG key..."
dnssec-keygen -a "${ALGORITHM}" -n HOST "${KEYNAME}"

# Extract the key from the generated files
KEY_FILE=$(ls K${KEYNAME}*.private 2>/dev/null)

if [ -z "${KEY_FILE}" ]; then
    echo "Error: Failed to generate key files!"
    exit 1
fi

# Extract the secret from the key file
SECRET=$(grep "Key:" "${KEY_FILE}" | awk '{print $2}')

if [ -n "${SECRET}" ]; then
    # Output the key configuration
    echo -e "\n===== TSIG KEY CONFIGURATION ====="
    echo "Key Name: ${KEYNAME}"
    echo "Algorithm: ${ALGORITHM}"
    echo "Secret: ${SECRET}"
    echo -e "===== END CONFIGURATION =====\n"
    
    # Create a key file for BIND
    echo "Creating BIND key file..."
    cat > "${KEYNAME}.key" << END
key "${KEYNAME}" {
    algorithm ${ALGORITHM};
    secret "${SECRET}";
};
END
    cp "${KEYNAME}.key" /home/pimaster/pi-cluster/
    echo "Key file created: ${KEYNAME}.key"
    
    # Create a Kubernetes secret for External-DNS
    echo "Creating Kubernetes secret manifest..."
    cat > /home/pimaster/pi-cluster/external-dns-tsig-secret.yaml << END
apiVersion: v1
kind: Secret
metadata:
  name: external-dns-rfc2136-credentials
  namespace: external-dns
type: Opaque
stringData:
  rfc2136_tsig_secret: "${SECRET}"
END
    
    echo "Secret manifest created: /home/pimaster/pi-cluster/external-dns-tsig-secret.yaml"
    
    # Cleanup
    echo "Cleaning up temporary files..."
    cd /home/pimaster/pi-cluster/
    rm -rf "${OUTDIR}"
    
    echo "Done!"
else
    echo "Error: Failed to extract key from generated files!"
    exit 1
fi
