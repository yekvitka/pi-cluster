#!/bin/bash

# This script generates a TSIG key for secure DNS updates

# Generate a TSIG key using tsig-keygen (part of BIND9 utilities)
KEYNAME="externaldns-key"
ALGORITHM="hmac-sha256"

# Check if BIND utilities are installed
if ! command -v tsig-keygen &> /dev/null; then
    echo "BIND9 utilities not found. Installing bind9utils..."
    apt-get update && apt-get install -y bind9utils
fi

# Generate the key using tsig-keygen
echo "Generating TSIG key..."
TSIG_KEY=$(tsig-keygen -a "${ALGORITHM}" "${KEYNAME}")

# Extract the secret from the TSIG key
SECRET=$(echo "$TSIG_KEY" | grep "secret" | awk -F'"' '{print $2}')

if [ -n "${SECRET}" ]; then
    # Output the key configuration
    echo -e "\n===== TSIG KEY CONFIGURATION ====="
    echo "Key Name: ${KEYNAME}"
    echo "Algorithm: ${ALGORITHM}"
    echo "Secret: ${SECRET}"
    echo -e "===== END CONFIGURATION =====\n"
    
    # Create a key file for BIND
    echo "Creating BIND key file..."
    echo "${TSIG_KEY}" > "${KEYNAME}.key"
    echo "Key file created: ${KEYNAME}.key"
    
    # Create a Kubernetes secret for External-DNS
    echo "Creating Kubernetes secret manifest..."
    cat > external-dns-tsig-secret.yaml << END
apiVersion: v1
kind: Secret
metadata:
  name: external-dns-rfc2136-credentials
  namespace: external-dns
type: Opaque
stringData:
  rfc2136_tsig_secret: "${SECRET}"
END
    
    echo "Secret manifest created: external-dns-tsig-secret.yaml"
    
    echo "Done!"
else
    echo "Error: Failed to generate key!"
    exit 1
fi
