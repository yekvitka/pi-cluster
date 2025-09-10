#!/bin/bash

# Script to help access the Rancher UI

# Function to show a menu of options
show_menu() {
    echo -e "\n================= RANCHER ACCESS MENU =================="
    echo "1. Test Rancher connectivity"
    echo "2. View HTML diagnostic test page"
    echo "3. Try HTTP access (instead of HTTPS)"
    echo "4. Try direct IP access (bypass hostname)"
    echo "5. Check Rancher logs"
    echo "6. Restart Rancher pods"
    echo "7. Add rancher.picluster.local to hosts file"
    echo "8. Show macOS access instructions"
    echo "9. Exit"
    echo "========================================================"
    echo -n "Enter your choice [1-9]: "
}

# Check if rancher.picluster.local is in the hosts file
update_hosts_file() {
    if ! grep -q "rancher.picluster.local" /etc/hosts; then
        echo "Adding rancher.picluster.local to /etc/hosts..."
        sudo sh -c 'echo "10.0.0.13 rancher.picluster.local" >> /etc/hosts'
        echo "Done! Hosts file updated."
    else
        echo "Entry already exists in hosts file."
    fi
}

# Test connectivity
test_connectivity() {
    echo -e "\n====================== RANCHER UI ACCESS ======================"
    echo "Rancher UI is available at: https://rancher.picluster.local/dashboard/"
    echo ""
    echo "IMPORTANT: When opening in browser, you may need to:"
    echo "1. Accept the security risk for the self-signed certificate"
    echo "2. Use the default password 'admin' (or retrieve it with the command below)"
    echo ""
    echo "To get the bootstrap password if 'admin' doesn't work:"
    echo "  ssh node2 \"kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}'\""
    echo "=============================================================="

    # Test the connection
    echo -e "\nTesting connection to Rancher UI..."
    HTTPS_TEST=$(curl -k -s -o /dev/null -w "%{http_code}" https://rancher.picluster.local/dashboard/)
    HTTP_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://rancher.picluster.local/dashboard/)
    
    echo "HTTPS test: $HTTPS_TEST"
    echo "HTTP test: $HTTP_TEST"

    # Check if JavaScript files are accessible
    echo -e "\nVerifying JavaScript resources..."
    JS_VENDOR=$(curl -k -s -o /dev/null -w "%{http_code}" https://rancher.picluster.local/dashboard/js/chunk-vendors.*.js)
    JS_INDEX=$(curl -k -s -o /dev/null -w "%{http_code}" https://rancher.picluster.local/dashboard/js/index.*.js)

    if [ "$JS_VENDOR" = "200" ] && [ "$JS_INDEX" = "200" ]; then
        echo "JavaScript resources: OK"
    else
        echo "JavaScript resources: FAIL - This may cause a white screen in the browser"
        echo "Vendor JS: $JS_VENDOR, Index JS: $JS_INDEX"
    fi
    
    # Check certificate
    echo -e "\nChecking SSL Certificate..."
    echo | openssl s_client -connect rancher.picluster.local:443 -servername rancher.picluster.local 2>/dev/null | grep "subject\|issuer"

    # Recommend browser options
    echo -e "\n====================== BROWSER TIPS ======================"
    echo "If you see a white screen when accessing Rancher:"
    echo "1. Try using a different browser (Firefox or Chrome recommended)"
    echo "2. Use Incognito/Private mode to avoid cache issues"
    echo "3. Enable JavaScript in your browser settings"
    echo "4. Try accessing with http instead: http://rancher.picluster.local/dashboard/"
    echo "5. Check browser console for JavaScript errors (F12 > Console)"
    echo "6. Try accessing via direct IP: https://10.0.0.13/dashboard/"
    echo "============================================================"
}

# View HTML diagnostic test page
view_diagnostic_page() {
    HTML_FILE="/home/pimaster/pi-cluster/scripts/rancher_test.html"
    
    if [ -f "$HTML_FILE" ]; then
        echo "Opening HTML diagnostic page..."
        if [ -n "$DISPLAY" ]; then
            xdg-open "file://$HTML_FILE" &>/dev/null || true
        else
            echo "Cannot open browser - no display detected."
            echo "HTML file is located at: $HTML_FILE"
        fi
    else
        echo "HTML diagnostic file not found at $HTML_FILE"
    fi
}

# Try HTTP access
try_http_access() {
    echo "Opening Rancher UI via HTTP..."
    if [ -n "$DISPLAY" ]; then
        xdg-open http://rancher.picluster.local/dashboard/ &>/dev/null || true
    else
        echo "Cannot open browser - no display detected."
        echo "Please open http://rancher.picluster.local/dashboard/ in your browser"
    fi
}

# Try direct IP access
try_ip_access() {
    echo "Opening Rancher UI via direct IP..."
    if [ -n "$DISPLAY" ]; then
        xdg-open https://10.0.0.13/dashboard/ &>/dev/null || true
    else
        echo "Cannot open browser - no display detected."
        echo "Please open https://10.0.0.13/dashboard/ in your browser"
    fi
}

# Check Rancher logs
check_rancher_logs() {
    echo "Retrieving Rancher logs..."
    ssh node2 "kubectl -n cattle-system logs deployment/rancher --tail=30" || echo "Failed to retrieve logs"
}

# Restart Rancher pods
restart_rancher() {
    echo "Restarting Rancher pods..."
    ssh node2 "kubectl -n cattle-system rollout restart deployment rancher" || echo "Failed to restart Rancher"
    
    echo "Waiting for pods to restart..."
    sleep 5
    ssh node2 "kubectl -n cattle-system get pods" || echo "Failed to get pod status"
}

# Add hosts entry and run basic tests
update_hosts_file

# Show macOS access instructions
show_mac_instructions() {
    echo -e "\n================= MACOS ACCESS INSTRUCTIONS =================\n"
    echo "To access Rancher from your Mac, follow these steps:"
    echo ""
    echo "1. Open Terminal on your Mac"
    echo "2. Edit the hosts file with sudo privileges:"
    echo "   sudo nano /etc/hosts"
    echo ""
    echo "3. Add the following line to the file:"
    echo "   10.0.0.13 rancher.picluster.local"
    echo ""
    echo "4. Save the file (Ctrl+O, Enter, Ctrl+X)"
    echo ""
    echo "5. Open your browser (Chrome or Firefox recommended)"
    echo "6. Navigate to: https://rancher.picluster.local/dashboard/"
    echo "7. Accept any security warnings about the certificate"
    echo ""
    echo "NOTE: Direct IP access (https://10.0.0.13/dashboard/) will NOT work"
    echo "      because the Ingress is configured to only respond to the hostname."
    echo ""
    echo "If you're still having issues, see the full guide at:"
    echo "/home/pimaster/pi-cluster/docs/mac_rancher_access.md"
    echo "================================================================="
}

# Main loop
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    test_connectivity
    exit 0
fi

if [ "$1" == "--auto" ] || [ "$1" == "-a" ]; then
    test_connectivity
    if [ -n "$DISPLAY" ]; then
        xdg-open https://rancher.picluster.local/dashboard/ &>/dev/null || true
    fi
    exit 0
fi

if [ "$1" == "--mac" ]; then
    show_mac_instructions
    exit 0
fi

# Interactive menu
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) test_connectivity ;;
        2) view_diagnostic_page ;;
        3) try_http_access ;;
        4) try_ip_access ;;
        5) check_rancher_logs ;;
        6) restart_rancher ;;
        7) update_hosts_file ;;
        8) show_mac_instructions ;;
        9) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
    
    echo -e "\nPress Enter to continue..."
    read -r
done
