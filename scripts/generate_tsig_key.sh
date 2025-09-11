#!/bin/bash

# This script generates a TSIG key for secure DNS updates

# Generate a TSIG key using dnssec-keygen (part of BIND9 utilities)
KEYNAME="externaldns-key"
ALGORITHM="hmac-sha256"

# Check if BIND utilities are installed
if ! command -v dnssec-keygen &> /dev/null; then
    echo "BIND9 utilities not found. Installing bind9utils..."
    apt-get update && apt-get install -y bind9utils
fi

# Generate the key
echo "Generating TSIG key..."
dnssec-keygen -a "${ALGORITHM}" -n HOST -r /dev/urandom "${KEYNAME}"

# Extract the base64 key from the generated file
KEY_FILE=$(ls K${KEYNAME}*.private)
if [ -f "${KEY_FILE}" ]; then
    # Extract the key
    SECRET=$(grep "Key:" "${KEY_FILE}" | awk '{print $2}')
    
    # Output the key configuration
    echo -e "\n===== TSIG KEY CONFIGURATION ====="
    echo "Key Name: ${KEYNAME}"
    echo "Algorithm: ${ALGORITHM}"
    echo "Secret: ${SECRET}"
    echo -e "===== END CONFIGURATION =====\n"
    
    # Also create a key file for BIND
    echo "Creating BIND key file..."
    cat > "${KEYNAME}.key" << END
key "${KEYNAME}" {
    algorithm ${ALGORITHM};
    secret "${SECRET}";
};
END
    
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
    
    # Cleanup
    echo "Cleaning up temporary files..."
    rm -f K${KEYNAME}*
    
    echo "Done!"
else
    echo "Error: Failed to generate key!"
    exit 1
fi
