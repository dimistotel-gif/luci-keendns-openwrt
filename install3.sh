#!/bin/sh
# nginx-ui installer for OpenWrt x86_64
# Preserves native Luci interface

set -e

echo "=============================================="
echo "   Nginx-UI Installer for OpenWrt x86_64"
echo "=============================================="

# Configuration
NGINX_UI_VERSION="v2.0.0-beta.8"
INSTALL_DIR="/opt/nginx-ui"
CONFIG_DIR="/etc/nginx-ui"
SERVICE_NAME="nginx-ui"
NGINX_UI_PORT="8080"  # Internal port for nginx-ui
PUBLIC_PORT="80"      # Public port for everything
LUCI_PORT="8081"      # Luci will be on this port temporarily

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
print_status() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }

# Get router IP
get_router_ip() {
    local ip=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
    echo "$ip"
}

backup_luci() {
    print_status "Backing up original Luci configuration..."
    
    # Backup uHTTPd config
    cp /etc/config/uhttpd /etc/config/uhttpd.backup.$(date +%s)
    
    # Stop uHTTPd on port 80
    /etc/init.d/uhttpd stop
    sleep 2
}

install_nginx() {
    print_status "Installing nginx..."
    
    opkg update
    opkg install nginx nginx-mod-luci nginx-ssl nginx-mod-stream
    
    # Stop nginx if running
    /etc/init.d/nginx stop 2>/dev/null
}

download_nginx_ui() {
    print_status "Downloading nginx-ui for x86_64..."
    
    mkdir -p $INSTALL_DIR
    cd /tmp
    
    # Download latest release
    LATEST_URL=$(curl -s https://api.github.com/repos/schenkd/nginx-ui/releases/latest | \
        grep "browser_download_url.*linux-amd64" | \
        cut -d'"' -f4)
    
    if [ -z "$LATEST_URL" ]; then
        print_warning "Could not find latest release, using direct URL..."
        LATEST_URL="https://github.com/schenkd/nginx-ui/releases/latest/download/nginx-ui-linux-amd64.tar.gz"
    fi
    
    print_status "Downloading from: $LATEST_URL"
    wget -O nginx-ui.tar.gz "$LATEST_URL"
    
    # Extract
    tar -xzf nginx-ui.tar.gz
    mv nginx-ui $INSTALL_DIR/
    chmod +x $INSTALL_DIR/nginx-ui
    
    # Test run
    if $INSTALL_DIR/nginx-ui --version 2>&1 | grep -q "nginx-ui"; then
        print_status "nginx-ui binary works!"
    else
        print_error "nginx-ui binary test failed"
        return 1
    fi
}

create_nginx_config() {
    print_status "Creating nginx configuration..."
    
    ROUTER_IP=$(get_router_ip)
    
    # Main nginx config
    cat > /etc/nginx/nginx.conf << 'EOF'
user nobody nogroup;
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
    
    # Virtual hosts
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

    # Create config directory
    mkdir -p /etc/nginx/conf.d
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    # MAIN PROXY CONFIG - Everything through nginx
    cat > /etc/nginx/conf.d/main.conf << EOF
# Main server block - handles everything on port 80
server {
    listen ${PUBLIC_PORT};
    server_name _;
    
    # Luci interface (original OpenWrt web interface)
    location /cgi-bin/luci {
        proxy_pass http://127.0.0.1:${LUCI_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /luci-static/ {
        proxy_pass http://127.0.0.1:${LUCI_PORT};
        proxy_set_header Host \$host;
    }
    
    # Nginx-UI interface
    location /nginx-ui/ {
        proxy_pass http://127.0.0.1:${NGINX_UI_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Redirect root to nginx-ui
    location = / {
        return 302 /nginx-ui/;
    }
    
    # Simple management interface
    location /manage/ {
        alias /www/nginx-simple/;
        index index.html;
    }
    
    # API endpoints for simple interface
    location /api/ {
        proxy_pass http://127.0.0.1:${NGINX_UI_PORT}/api/;
        proxy_set_header Host \$host;
    }
}
EOF

    # Default virtual host template
    cat > /etc/nginx/sites-available/default.conf << 'EOF'
# Template for virtual hosts
# server {
#     listen 80;
#     server_name example.com;
#     
#     location / {
#         proxy_pass http://backend_server:port;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto $scheme;
#     }
# }
EOF

    ln -sf /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/
}

create_nginx_ui_config() {
    print_status "Creating nginx-ui configuration..."
    
    mkdir -p $CONFIG_DIR
    mkdir -p $INSTALL_DIR/data
    mkdir -p $INSTALL_DIR/logs
    
    cat > $CONFIG_DIR/config.json << EOF
{
    "server": {
        "host": "127.0.0.1",
        "port": ${NGINX_UI_PORT},
        "log_path": "${INSTALL_DIR}/logs/nginx-ui.log"
    },
    "nginx": {
        "config_path": "/etc/nginx/nginx.conf",
        "config_dir": "/etc/nginx/conf.d",
        "pid_path": "/var/run/nginx.pid",
        "test_config_cmd": "nginx -t",
        "reload_cmd": "nginx -s reload",
        "restart_cmd": "/etc/init.d/nginx restart"
    },
    "database": {
        "path": "${INSTALL_DIR}/data/nginx-ui.db"
    },
    "openwrt": {
        "luci_port": ${LUCI_PORT},
        "router_ip": "$(get_router_ip)"
    }
}
EOF
}

reconfigure_uhttpd() {
    print_status "Reconfiguring uHTTPd for Luci only..."
    
    # Stop uHTTPd
    /etc/init.d/uhttpd stop
    
    # Change uHTTPd to listen on different port for Luci
    uci set uhttpd.main.listen_http="127.0.0.1:${LUCI_PORT}"
    uci set uhttpd.main.listen_https="127.0.0.1:${LUCI_PORT}"
    uci commit uhttpd
    
    # Remove CGI prefix if set (nginx will handle it)
    uci delete uhttpd.main.cgi_prefix 2>/dev/null
    uci delete uhttpd.main.interpreter 2>/dev/null
    uci commit uhttpd
    
    print_status "uHTTPd will now serve Luci on 127.0.0.1:${LUCI_PORT}"
    print_status "Nginx will proxy it to port ${PUBLIC_PORT}"
}

create_service() {
    print_status "Creating nginx-ui service..."
    
    cat > /etc/init.d/$SERVICE_NAME << EOF
#!/bin/sh /etc/rc.common
# nginx-ui init script

USE_PROCD=1
START=99
STOP=10

PROG="$INSTALL_DIR/nginx-ui"
CONFIG="$CONFIG_DIR/config.json"

start_service() {
    procd_open_instance
    procd_set_param command \$PROG -config \$CONFIG
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 3600 5 0
    procd_set_param env NGINX_UI_DIR="$INSTALL_DIR"
    procd_close_instance
}

stop_service() {
    killall nginx-ui 2>/dev/null
}
EOF

    chmod +x /etc/init.d/$SERVICE_NAME
    
    # Enable on boot
    /etc/init.d/$SERVICE_NAME enable
}

create_simple_interface() {
    print_status "Creating simple web interface..."
    
    mkdir -p /www/nginx-simple
    
    cat > /www/nginx-simple/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenWrt Router Manager</title>
    <style>
        :root {
            --primary: #3498db;
            --secondary: #2c3e50;
            --success: #27ae60;
            --danger: #e74c3c;
            --warning: #f39c12;
            --light: #ecf0f1;
            --dark: #2c3e50;
        }
        
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            transition: transform 0.3s;
        }
        
        .card:hover {
            transform: translateY(-5px);
        }
        
        .card-header {
            display: flex;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid var(--light);
        }
        
        .card-icon {
            font-size: 24px;
            margin-right: 15px;
            color: var(--primary);
        }
        
        .card-title {
            font-size: 1.5rem;
            color: var(--dark);
            font-weight: 600;
        }
        
        .status {
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 0.9rem;
            font-weight: 500;
            display: inline-block;
        }
        
        .status-running { background: #d4edda; color: #155724; }
        .status-stopped { background: #f8d7da; color: #721c24; }
        
        .btn {
            display: inline-block;
            padding: 12px 24px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            cursor: pointer;
            border: none;
            transition: all 0.3s;
            margin: 5px;
        }
        
        .btn-primary { background: var(--primary); color: white; }
        .btn-primary:hover { background: #2980b9; }
        
        .btn-success { background: var(--success); color: white; }
        .btn-danger { background: var(--danger); color: white; }
        .btn-warning { background: var(--warning); color: white; }
        
        .btn-group {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-top: 15px;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        
        .service-item {
            background: var(--light);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
        }
        
        .quick-actions {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
            gap: 10px;
            margin-top: 20px;
        }
        
        .quick-action {
            background: var(--light);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .quick-action:hover {
            background: var(--primary);
            color: white;
        }
        
        @media (max-width: 768px) {
            .dashboard {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <div class="card-header">
                <div class="card-icon">🚀</div>
                <h1 class="card-title">OpenWrt Router Manager</h1>
            </div>
            <p>Centralized management for your OpenWrt router</p>
        </div>

        <div class="dashboard">
            <!-- Status Card -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon">📊</div>
                    <h2 class="card-title">System Status</h2>
                </div>
                <div id="system-status">
                    <p>Loading system status...</p>
                </div>
                <div class="btn-group">
                    <button class="btn btn-primary" onclick="location.reload()">🔄 Refresh</button>
                    <button class="btn btn-warning" onclick="showLogs()">📋 View Logs</button>
                </div>
            </div>

            <!-- Services Card -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon">⚙️</div>
                    <h2 class="card-title">Services</h2>
                </div>
                <div class="services-grid">
                    <div class="service-item">
                        <strong>Nginx</strong>
                        <div id="nginx-status" class="status">Checking...</div>
                    </div>
                    <div class="service-item">
                        <strong>Nginx-UI</strong>
                        <div id="nginxui-status" class="status">Checking...</div>
                    </div>
                    <div class="service-item">
                        <strong>Luci</strong>
                        <div id="luci-status" class="status">Checking...</div>
                    </div>
                </div>
            </div>

            <!-- Quick Access Card -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon">🚪</div>
                    <h2 class="card-title">Quick Access</h2>
                </div>
                <div class="quick-actions">
                    <div class="quick-action" onclick="window.open('/nginx-ui/', '_blank')">
                        <strong>Nginx-UI</strong><br>
                        <small>Advanced Management</small>
                    </div>
                    <div class="quick-action" onclick="window.open('/cgi-bin/luci', '_blank')">
                        <strong>Luci</strong><br>
                        <small>OpenWrt Interface</small>
                    </div>
                    <div class="quick-action" onclick="window.open('/manage/', '_self')">
                        <strong>Simple UI</strong><br>
                        <small>Basic Controls</small>
                    </div>
                    <div class="quick-action" onclick="showProxyManager()">
                        <strong>Proxy Rules</strong><br>
                        <small>Manage Routes</small>
                    </div>
                </div>
            </div>

            <!-- Actions Card -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon">🔧</div>
                    <h2 class="card-title">Quick Actions</h2>
                </div>
                <div class="btn-group">
                    <button class="btn btn-success" onclick="serviceAction('nginx', 'restart')">🔄 Restart Nginx</button>
                    <button class="btn btn-warning" onclick="serviceAction('nginx-ui', 'restart')">🔄 Restart Nginx-UI</button>
                    <button class="btn btn-primary" onclick="serviceAction('uhttpd', 'restart')">🔄 Restart Luci</button>
                </div>
            </div>
        </div>
    </div>

    <script>
    async function checkStatus() {
        try {
            // Check nginx
            const nginxRes = await fetch('/api/nginx/status');
            const nginxText = await nginxRes.text();
            document.getElementById('nginx-status').className = 'status ' + 
                (nginxText.includes('running') ? 'status-running' : 'status-stopped');
            document.getElementById('nginx-status').textContent = 
                nginxText.includes('running') ? 'Running' : 'Stopped';
                
            // Check system
            const sysRes = await fetch('/api/system/status');
            const sysData = await sysRes.json();
            document.getElementById('system-status').innerHTML = `
                <p><strong>Uptime:</strong> ${sysData.uptime || 'N/A'}</p>
                <p><strong>Load:</strong> ${sysData.load || 'N/A'}</p>
                <p><strong>Memory:</strong> ${sysData.memory || 'N/A'}</p>
            `;
        } catch (e) {
            console.error('Status check failed:', e);
        }
    }
    
    async function serviceAction(service, action) {
        const res = await fetch(`/api/service/${service}/${action}`, {method: 'POST'});
        const result = await res.text();
        alert(`${service} ${action}: ${result}`);
        setTimeout(checkStatus, 2000);
    }
    
    function showLogs() {
        window.open('/nginx-ui/#/logs', '_blank');
    }
    
    function showProxyManager() {
        window.open('/nginx-ui/#/config', '_blank');
    }
    
    // Initial load
    checkStatus();
    setInterval(checkStatus, 30000); // Update every 30 seconds
    </script>
</body>
</html>
HTML
}

create_api_endpoints() {
    print_status "Creating API endpoints..."
    
    mkdir -p /www/cgi-bin/api
    
    # Nginx status
    cat > /www/cgi-bin/api/nginx-status << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

if ps | grep -q "[n]ginx.*master"; then
    echo '{"status": "running", "pid": "'$(cat /var/run/nginx.pid 2>/dev/null)'"}'
else
    echo '{"status": "stopped"}'
fi
EOF

    # System status
    cat > /www/cgi-bin/api/system-status << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

uptime=$(uptime | sed 's/.*up //;s/,.*//')
load=$(uptime | grep -o "load average: .*" | cut -d: -f2)
memory=$(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')

echo '{"uptime": "'$uptime'", "load": "'$load'", "memory": "'$memory'"}'
EOF

    # Service control
    cat > /www/cgi-bin/api/service-control << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""

SERVICE=$(echo "$PATH_INFO" | cut -d/ -f3)
ACTION=$(echo "$PATH_INFO" | cut -d/ -f4)

case "$SERVICE" in
    nginx)
        /etc/init.d/nginx $ACTION 2>&1
        ;;
    nginx-ui)
        /etc/init.d/nginx-ui $ACTION 2>&1
        ;;
    uhttpd)
        /etc/init.d/uhttpd $ACTION 2>&1
        ;;
    *)
        echo "Unknown service: $SERVICE"
        ;;
esac
EOF

    chmod +x /www/cgi-bin/api/*
}

setup_firewall() {
    print_status "Configuring firewall..."
    
    # Allow port 80 from WAN
    uci add firewall rule
    uci set firewall.@rule[-1].name='Nginx-Web'
    uci set firewall.@rule[-1].src='wan'
    uci set firewall.@rule[-1].dest_port='80'
    uci set firewall.@rule[-1].proto='tcp'
    uci set firewall.@rule[-1].target='ACCEPT'
    
    uci commit firewall
    /etc/init.d/firewall reload
}

setup_luci_menu() {
    print_status "Setting up Luci menu..."
    
    cat > /usr/lib/lua/luci/controller/nginx-manager.lua << 'EOF'
module("luci.controller.nginx-manager", package.seeall)

function index()
    entry({"admin", "services", "nginx-manager"}, alias("admin", "services", "nginx-manager", "redirect"), _("Nginx Manager"), 90)
    entry({"admin", "services", "nginx-manager", "redirect"}, call("redirect_to_dashboard"), nil)
end

function redirect_to_dashboard()
    local http = require("luci.http")
    http.redirect("/")
end
EOF

    cat > /usr/share/luci/menu.d/luci-app-nginx-manager.json << 'EOF'
{
    "admin/services/nginx-manager": {
        "title": "Router Dashboard",
        "order": 90,
        "action": {
            "type": "firstchild"
        }
    }
}
EOF
}

start_services() {
    print_status "Starting all services..."
    
    # Start uHTTPd on Luci port
    /etc/init.d/uhttpd start
    sleep 2
    
    # Start nginx-ui
    /etc/init.d/nginx-ui start
    sleep 2
    
    # Start nginx (this will take over port 80)
    /etc/init.d/nginx start
    /etc/init.d/nginx enable
    
    # Wait a bit
    sleep 3
    
    # Check if everything is running
    if ps | grep -q "[n]ginx.*master"; then
        print_status "✓ Nginx is running"
    else
        print_error "✗ Nginx failed to start"
    fi
    
    if ps | grep -q "[n]ginx-ui"; then
        print_status "✓ Nginx-UI is running"
    else
        print_warning "⚠ Nginx-UI may not be running"
    fi
    
    if ps | grep -q "[u]httpd"; then
        print_status "✓ Luci/uHTTPd is running"
    else
        print_error "✗ Luci/uHTTPd failed to start"
    fi
}

print_summary() {
    ROUTER_IP=$(get_router_ip)
    
    echo ""
    echo "=============================================="
    echo "   🎉 INSTALLATION COMPLETE! 🎉"
    echo "=============================================="
    echo ""
    echo "📡 NETWORK SETUP:"
    echo "   • Nginx listens on: ALL interfaces, port ${PUBLIC_PORT}"
    echo "   • Luci redirected to: http://${ROUTER_IP}/cgi-bin/luci"
    echo "   • Nginx-UI available at: http://${ROUTER_IP}/nginx-ui/"
    echo "   • Dashboard at: http://${ROUTER_IP}/"
    echo ""
    echo "🔧 SERVICES:"
    echo "   • Nginx: /etc/init.d/nginx {start|stop|restart}"
    echo "   • Nginx-UI: /etc/init.d/nginx-ui {start|stop|restart}"
    echo "   • Luci: /etc/init.d/uhttpd {start|stop|restart}"
    echo ""
    echo "📁 DIRECTORIES:"
    echo "   • Nginx configs: /etc/nginx/conf.d/"
    echo "   • Nginx-UI: ${INSTALL_DIR}"
    echo "   • Virtual hosts: /etc/nginx/sites-available/"
    echo ""
    echo "⚙️ CONFIGURATION:"
    echo "   • Main nginx config: /etc/nginx/nginx.conf"
    echo "   • Nginx-UI config: ${CONFIG_DIR}/config.json"
    echo "   • Luci config: /etc/config/uhttpd"
    echo ""
    echo "🔄 HOW IT WORKS:"
    echo "   1. User visits http://${ROUTER_IP}/"
    echo "   2. Nginx (port 80) receives request"
    echo "   3. Nginx proxies to appropriate service:"
    echo "      - /cgi-bin/luci → Luci (port ${LUCI_PORT})"
    echo "      - /nginx-ui/ → Nginx-UI (port ${NGINX_UI_PORT})"
    echo "      - /manage/ → Simple interface"
    echo ""
    echo "⚠️ IMPORTANT:"
    echo "   • Original Luci is now at http://${ROUTER_IP}:${LUCI_PORT}"
    echo "   • But use http://${ROUTER_IP}/cgi-bin/luci (proxied)"
    echo "   • If something breaks, check: /var/log/nginx/error.log"
    echo ""
    echo "=============================================="
    echo "   Open browser and go to: http://${ROUTER_IP}/"
    echo "=============================================="
}

# Main execution
main() {
    echo "Starting installation for x86_64 OpenWrt..."
    
    # Check root
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Run installation steps
    backup_luci
    install_nginx
    download_nginx_ui
    create_nginx_config
    create_nginx_ui_config
    reconfigure_uhttpd
    create_service
    create_simple_interface
    create_api_endpoints
    setup_firewall
    setup_luci_menu
    start_services
    print_summary
    
    # Final test
    echo ""
    echo "Testing connectivity..."
    if curl -s "http://127.0.0.1/" | grep -q "OpenWrt"; then
        print_status "✓ Installation successful!"
    else
        print_warning "⚠ Something might be wrong, check logs"
    fi
}

# Run main
main "$@"
