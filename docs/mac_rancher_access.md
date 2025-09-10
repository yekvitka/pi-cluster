# Accessing Rancher UI from macOS

When accessing the Rancher UI from a Mac, you need to ensure your Mac can resolve the hostname `rancher.picluster.local` to the correct IP address.

## Add Hosts File Entry on Mac

1. Open Terminal on your Mac
2. Edit the hosts file with sudo privileges:
   ```bash
   sudo nano /etc/hosts
   ```

3. Add the following line to the file:
   ```
   10.0.0.13 rancher.picluster.local
   ```

4. Save the file:
   - Press `Control + O` to write the file
   - Press `Enter` to confirm
   - Press `Control + X` to exit

## Access Rancher UI

After adding the hosts entry, you can access Rancher in your browser:

1. Open your browser (Chrome or Firefox recommended)
2. Navigate to: https://rancher.picluster.local/dashboard/
3. If you see a security warning, click "Advanced" and "Accept Risk and Continue"
4. Log in with username `admin` and password `admin` (or use the password retrieval command if this doesn't work)

## Troubleshooting

If you still see a white screen or 404 error:

1. **Verify hosts file entry**:
   ```bash
   cat /etc/hosts | grep rancher
   ```

2. **Test connectivity**:
   ```bash
   ping rancher.picluster.local
   ```

3. **Test with curl**:
   ```bash
   curl -k -I https://rancher.picluster.local/dashboard/
   ```

4. **Try with different browsers** - Safari, Chrome, and Firefox may behave differently

5. **Try using Incognito/Private browsing mode** to avoid cache issues

6. **Clear DNS cache**:
   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```

## Network Requirements

Ensure your Mac is:
1. Connected to the same network as the Pi cluster
2. Can reach the 10.0.0.x subnet
3. Has no firewall rules blocking access to 10.0.0.13

If you're still having issues, check your network configuration to ensure you can reach the 10.0.0.x network from your Mac.
