function FindProxyForURL(url, host) {
    // Split tunneling PAC file for OpenVPN
    // Only traffic to specific domains goes through VPN
    
    // Get the protocol
    var protocol = url.split(":")[0];
    
    // VPN-enabled domains and ranges
    // These will route through OpenVPN (10.8.0.1 is the VPN gateway)
    var vpn_hosts = [
        // Internal company domains
        "*.internal.company.com",
        "intranet.company.com",
        "vpn.company.com",
        
        // Specific services
        "service1.example.com",
        "service2.example.com",
        
        // Add your domains here as needed
    ];
    
    // Direct connections (bypass VPN)
    var direct_hosts = [
        "*.cloudflare.com",
        "*.google.com",
        "*.github.com",
        "localhost",
        "127.0.0.1",
        "*.local",
    ];
    
    // Check for direct connections first
    for (var i = 0; i < direct_hosts.length; i++) {
        if (shExpMatch(host, direct_hosts[i])) {
            return "DIRECT";
        }
    }
    
    // Check if host should go through VPN
    for (var i = 0; i < vpn_hosts.length; i++) {
        if (shExpMatch(host, vpn_hosts[i])) {
            // SOCKS5 or HTTP proxy through OpenVPN interface
            // Or simply return SOCKS5 10.8.0.1:1080 if you have local proxy
            return "DIRECT";  // When connected to VPN, internal IPs are accessible
        }
    }
    
    // By default, everything else goes DIRECT (normal internet)
    return "DIRECT";
}

/*
 * SETUP INSTRUCTIONS:
 * 
 * For Linux/Mac (via OpenVPN split tunneling + route-nopull):
 * 1. In your .ovpn config, ensure:
 *    route-nopull                 # Don't add default VPN route
 *    route 10.0.0.0 255.0.0.0     # Route internal networks through VPN
 *    route 192.168.0.0 255.255.0.0
 * 
 * 2. When OpenVPN connects, these routes are automatically added
 *    You don't need a PAC file - just configure OpenVPN to push routes
 * 
 * For Windows (via PAC file):
 * 1. Save this file as "proxy.pac" 
 * 2. In Windows Settings:
 *    Settings > Network > Proxy > Automatic proxy setup
 *    Enable "Use a proxy auto-config (PAC) script"
 *    Enter: file:///C:/path/to/proxy.pac
 *    OR: http://your-server/proxy.pac (serve from web server)
 * 
 * 3. Ensure OpenVPN is connected first
 * 4. Windows will automatically route through VPN as configured
 * 
 * For Browser-based proxy (Chrome, Firefox):
 * 1. Install extension like "Proxy SwitchyOmega"
 * 2. Point to this PAC file
 * 3. Enable proxy when you connect to OpenVPN
 * 
 * ADVANCED: Serve PAC from web server
 * 1. Host this file on a web server with HTTPS
 * 2. Set headers: Content-Type: application/x-ns-proxy-autoconfig
 * 3. Push URL in OpenVPN config: push "dhcp-option WPAD http://vpn.company.com/proxy.pac"
 */
