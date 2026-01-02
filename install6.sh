#!/bin/sh
# Nginx-UI Installer for OpenWrt with v2.3.2
# Simple and working version

set -e

echo "=============================================="
echo "   Nginx-UI v2.3.2 Installer for OpenWrt"
echo "=============================================="

# Configuration
NGINX_UI_VERSION="v2.3.2"
NGINX_UI_URL="https://github.com/0xJacky/nginx-ui/releases/download/${NGINX_UI_VERSION}/nginx-ui-linux-64.tar.gz"
INSTALL_DIR="/opt/nginx-ui"
CONFIG_DIR="/etc/nginx-ui"
SERVICE_NAME="nginx-ui"
NGINX_UI_PORT="9000"    # Internal port for nginx-ui
LUCI_PORT="8081"        # Luci port
PUBLIC_PORT="80"        # Public port

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

get_router_ip() {
    uci get network.lan.ipaddr 2>/dev/null || echo "192.168.100.1"
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check for wget/curl
    if ! command -v wget >/dev/null && ! command -v curl >/dev/null; then
        opkg update
        opkg install wget
    fi
    
    # Check for tar
    if ! command -v tar >/dev/null; then
        opkg install tar
    fi
}

install_nginx_minimal() {
    print_status "Installing nginx (minimal)..."
    
    # Remove any existing nginx
    opkg remove --force-removal-of-dependent-packages nginx nginx-* 2>/dev/null || true
    
    # Clean directories
    rm -rf /etc/nginx /var/lib/nginx 2>/dev/null
    mkdir -p /etc/nginx /var/log/nginx
    
    # Install basic nginx
    opkg update
    opkg install nginx
    
    # Stop nginx
    /etc/init.d/nginx stop 2>/dev/null || true
}

download_nginx_ui() {
    print_status "Downloading nginx-ui ${NGINX_UI_VERSION}..."
    
    mkdir -p $INSTALL_DIR
    cd /tmp
    
    print_status "Download URL: $NGINX_UI_URL"
    
    # Download using wget or curl
    if command -v wget >/dev/null; then
        wget -O nginx-ui.tar.gz "$NGINX_UI_URL"
    else
        curl -L -o nginx-ui.tar.gz "$NGINX_UI_URL"
    fi
    
    if [ ! -f "nginx-ui.tar.gz" ]; then
        print_error "Failed to download nginx-ui"
        return 1
    fi
    
    # Extract
    tar -xzf nginx-ui.tar.gz
    
    # Move binary
    if [ -f "nginx-ui" ]; then
        mv nginx-ui $INSTALL_DIR/
    else
        # Find the binary
        find . -name "nginx-ui*" -type f -executable | head -1 | xargs -I {} cp {} $INSTALL_DIR/nginx-ui
    fi
    
    chmod +x $INSTALL_DIR/nginx-ui
    
    # Verify
    if [ -x "$INSTALL_DIR/nginx-ui" ]; then
        print_status "nginx-ui binary downloaded successfully"
    else
        print_error "nginx-ui binary not found or not executable"
        return 1
    fi
}

create_nginx_config() {
    print_status "Creating nginx configuration..."
    
    ROUTER_IP=$(get_router_ip)
    
    # Create minimal nginx.conf
    cat > /etc/nginx/nginx.conf << 'EOF'
user nobody nogroup;
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    keepalive_timeout 65;
    
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Create conf.d directory
    mkdir -p /etc/nginx/conf.d
    
    # Main configuration
    cat > /etc/nginx/conf.d/main.conf << EOF
# Main server block
server {
    listen ${PUBLIC_PORT};
    server_name _;
    
    # Root - redirect to nginx-ui
    location = / {
        return 302 /ui/;
    }
    
    # Nginx-UI
    location /ui/ {
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
    
    # Luci interface (keep original)
    location /luci/ {
        proxy_pass http://127.0.0.1:${LUCI_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    
    # API
    location /api/ {
        proxy_pass http://127.0.0.1:${NGINX_UI_PORT}/api/;
        proxy_set_header Host \$host;
    }
    
    # Dashboard
    location /dashboard/ {
        alias /www/dashboard/;
        index index.html;
    }
}
EOF

    # Simple proxy template
    cat > /etc/nginx/conf.d/proxy-template.conf << 'EOF'
# Proxy template - copy and modify
# server {
#     listen 80;
#     server_name example.com;
#     
#     location / {
#         proxy_pass http://backend:port;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#     }
# }
EOF
}

create_nginx_ui_config() {
    print_status "Creating nginx-ui configuration..."
    
    mkdir -p $CONFIG_DIR
    mkdir -p $INSTALL_DIR/data
    mkdir -p $INSTALL_DIR/logs
    
    cat > $CONFIG_DIR/config.yaml << 'EOF'
# Nginx-UI Configuration
server:
  host: "127.0.0.1"
  port: 9000
  log_path: "/opt/nginx-ui/logs/nginx-ui.log"
  ssl:
    enabled: false

nginx:
  config_dir: "/etc/nginx"
  pid_path: "/var/run/nginx.pid"
  test_config_cmd: "nginx -t"
  reload_cmd: "nginx -s reload"
  restart_cmd: "/etc/init.d/nginx restart"

database:
  path: "/opt/nginx-ui/data/nginx-ui.db"

auth:
  enabled: true
  username: "admin"
  password_hash: "$2a$10$L7jGmH3nLpVv9v6qYkQj7eT5sR8wN2cX4vB7yH6gF5dR3vC2xZ4qW" # password: admin

logging:
  level: "info"
  max_size: 100
  max_backups: 10
  max_age: 30
EOF

    # Create simple config.json for compatibility
    cat > $CONFIG_DIR/config.json << EOF
{
    "server": {
        "host": "127.0.0.1",
        "port": ${NGINX_UI_PORT},
        "log_path": "${INSTALL_DIR}/logs/nginx-ui.log"
    },
    "nginx": {
        "config_path": "/etc/nginx/nginx.conf",
        "config_dir": "/etc/nginx",
        "pid_path": "/var/run/nginx.pid",
        "test_config_cmd": "nginx -t",
        "reload_cmd": "nginx -s reload",
        "restart_cmd": "/etc/init.d/nginx restart"
    }
}
EOF
}

setup_uhttpd() {
    print_status "Setting up uHTTPd for Luci..."
    
    # Backup
    cp /etc/config/uhttpd /etc/config/uhttpd.backup
    
    # Stop uHTTPd
    /etc/init.d/uhttpd stop 2>/dev/null
    
    # Configure for internal port
    uci set uhttpd.main.listen_http="127.0.0.1:${LUCI_PORT}"
    uci set uhttpd.main.listen_https="127.0.0.1:${LUCI_PORT}"
    uci commit uhttpd
    
    # Start
    /etc/init.d/uhttpd start
}

create_service() {
    print_status "Creating nginx-ui service..."
    
    cat > /etc/init.d/$SERVICE_NAME << EOF
#!/bin/sh /etc/rc.common
# nginx-ui service

USE_PROCD=1
START=99
STOP=10

PROG="$INSTALL_DIR/nginx-ui"
CONFIG="$CONFIG_DIR/config.yaml"

start_service() {
    procd_open_instance
    procd_set_param command \$PROG -config \$CONFIG
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 300 5 0
    procd_close_instance
}

stop_service() {
    killall nginx-ui 2>/dev/null
}
EOF

    chmod +x /etc/init.d/$SERVICE_NAME
    /etc/init.d/$SERVICE_NAME enable
}

create_dashboard() {
    print_status "Creating simple dashboard..."
    
    mkdir -p /www/dashboard
    
    cat > /www/dashboard/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenWrt Router</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 500px;
            width: 100%;
            text-align: center;
        }
        .logo {
            font-size: 60px;
            margin-bottom: 20px;
            color: #667eea;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 16px;
        }
        .card {
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 20px;
            transition: transform 0.3s;
        }
        .card:hover {
            transform: translateY(-5px);
        }
        .btn {
            display: block;
            width: 100%;
            padding: 15px;
            margin: 10px 0;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            text-align: center;
            transition: all 0.3s;
        }
        .btn-primary {
            background: #4CAF50;
            color: white;
        }
        .btn-primary:hover {
            background: #45a049;
            transform: scale(1.02);
        }
        .btn-secondary {
            background: #2196F3;
            color: white;
        }
        .btn-secondary:hover {
            background: #1976D2;
        }
        .btn-warning {
            background: #ff9800;
            color: white;
        }
        .status {
            display: inline-block;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 500;
            margin: 10px 0;
        }
        .status-running { background: #d4edda; color: #155724; }
        .status-stopped { background: #f8d7da; color: #721c24; }
        .ip-address {
            background: #e3f2fd;
            padding: 10px;
            border-radius: 10px;
            margin: 20px 0;
            font-family: monospace;
            font-size: 18px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🚀</div>
        <h1>OpenWrt Router</h1>
        <p class="subtitle">Management Interface</p>
        
        <div class="card">
            <h3>Quick Access</h3>
            <div class="ip-address" id="router-ip">192.168.1.1</div>
            
            <a href="/ui/" class="btn btn-primary" target="_blank">
                📊 Nginx-UI Dashboard
            </a>
            
            <a href="/luci/" class="btn btn-secondary" target="_blank">
                ⚙️ Luci Interface
            </a>
            
            <a href="/api/health" class="btn btn-warning" target="_blank">
                🩺 Health Check
            </a>
        </div>
        
        <div class="card">
            <h3>Service Status</h3>
            <div style="text-align: left; padding: 15px;">
                <p><strong>Nginx:</strong> <span id="nginx-status" class="status">Checking...</span></p>
                <p><strong>Nginx-UI:</strong> <span id="nginxui-status" class="status">Checking...</span></p>
                <p><strong>Luci:</strong> <span id="luci-status" class="status">Checking...</span></p>
            </div>
            <button onclick="refreshStatus()" style="background: #9c27b0; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin-top: 10px;">
                🔄 Refresh Status
            </button>
        </div>
        
        <div style="margin-top: 30px; color: #666; font-size: 14px;">
            <p>Nginx-UI v2.3.2 | OpenWrt Router</p>
        </div>
    </div>

    <script>
    async function refreshStatus() {
        const services = ['nginx', 'nginx-ui', 'uhttpd'];
        
        for (const service of services) {
            const element = document.getElementById(`${service}-status`);
            element.textContent = 'Checking...';
            element.className = 'status';
            
            try {
                const response = await fetch(`/api/${service}/status`);
                const status = await response.text();
                
                element.textContent = status;
                element.className = `status status-${status}`;
            } catch {
                element.textContent = 'Unknown';
                element.className = 'status status-stopped';
            }
        }
    }
    
    // Get router IP
    async function getRouterIP() {
        try {
            const response = await fetch('/api/ip');
            const data = await response.json();
            document.getElementById('router-ip').textContent = data.ip;
        } catch {
            document.getElementById('router-ip').textContent = '192.168.1.1';
        }
    }
    
    // Initialize
    getRouterIP();
    refreshStatus();
    
    // Auto-refresh every 30 seconds
    setInterval(refreshStatus, 30000);
    </script>
</body>
</html>
HTML
}

create_api() {
    print_status "Creating API endpoints..."
    
    mkdir -p /www/cgi-bin/api
    
    # Service status
    cat > /www/cgi-bin/api/nginx/status << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""

if ps | grep -q "[n]ginx.*master"; then
    echo "running"
else
    echo "stopped"
fi
EOF

    cat > /www/cgi-bin/api/nginx-ui/status << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""

if ps | grep -q "[n]ginx-ui"; then
    echo "running"
else
    echo "stopped"
fi
EOF

    cat > /www/cgi-bin/api/uhttpd/status << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""

if ps | grep -q "[u]httpd"; then
    echo "running"
else
    echo "stopped"
fi
EOF

    # Router IP
    cat > /www/cgi-bin/api/ip << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
echo "{\"ip\": \"$IP\"}"
EOF

    # Health check
    cat > /www/cgi-bin/api/health << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

NGINX=$(ps | grep -q "[n]ginx.*master" && echo "ok" || echo "down")
NGINX_UI=$(ps | grep -q "[n]ginx-ui" && echo "ok" || echo "down")
UHTTPD=$(ps | grep -q "[u]httpd" && echo "ok" || echo "down")

echo "{
  \"nginx\": \"$NGINX\",
  \"nginx-ui\": \"$NGINX_UI\",
  \"uhttpd\": \"$UHTTPD\",
  \"timestamp\": \"$(date)\"
}"
EOF

    # Make executable
    chmod +x /www/cgi-bin/api/* /www/cgi-bin/api/nginx/* /www/cgi-bin/api/nginx-ui/* 2>/dev/null
}

setup_firewall() {
    print_status "Configuring firewall..."
    
    if [ -f /etc/config/firewall ]; then
        # Allow port 80
        uci add firewall rule
        uci set firewall.@rule[-1].name='Web-Interface'
        uci set firewall.@rule[-1].src='wan'
        uci set firewall.@rule[-1].dest_port='80'
        uci set firewall.@rule[-1].proto='tcp'
        uci set firewall.@rule[-1].target='ACCEPT'
        uci commit firewall
        /etc/init.d/firewall reload
    fi
}

start_services() {
    print_status "Starting services..."
    
    # Start uHTTPd (Luci)
    /etc/init.d/uhttpd start
    sleep 2
    
    # Start nginx-ui
    /etc/init.d/nginx-ui start
    sleep 3
    
    # Start nginx
    /etc/init.d/nginx start
    /etc/init.d/nginx enable
    sleep 3
    
    # Check status
    print_status "Service status:"
    
    if ps | grep -q "[n]ginx.*master"; then
        print_status "  Nginx: ✓ Running"
    else
        print_error "  Nginx: ✗ Not running"
    fi
    
    if ps | grep -q "[n]ginx-ui"; then
        print_status "  Nginx-UI: ✓ Running"
    else
        print_error "  Nginx-UI: ✗ Not running"
    fi
    
    if ps | grep -q "[u]httpd"; then
        print_status "  Luci: ✓ Running"
    else
        print_error "  Luci: ✗ Not running"
    fi
}

print_summary() {
    ROUTER_IP=$(get_router_ip)
    
    echo ""
    echo "=============================================="
    echo "   🎉 INSTALLATION COMPLETE! 🎉"
    echo "=============================================="
    echo ""
    echo "🌐 ACCESS INFORMATION:"
    echo "   Dashboard:      http://${ROUTER_IP}/"
    echo "   Nginx-UI:       http://${ROUTER_IP}/ui/"
    echo "   Luci:           http://${ROUTER_IP}/luci/"
    echo ""
    echo "🔧 DEFAULT CREDENTIALS:"
    echo "   Nginx-UI: admin / admin"
    echo "   Luci:     Your OpenWrt credentials"
    echo ""
    echo "📁 DIRECTORIES:"
    echo "   Nginx configs:   /etc/nginx/"
    echo "   Nginx-UI:        ${INSTALL_DIR}"
    echo "   Dashboard:       /www/dashboard/"
    echo ""
    echo "⚙️ MANAGEMENT:"
    echo "   Start nginx:     /etc/init.d/nginx start"
    echo "   Stop nginx:      /etc/init.d/nginx stop"
    echo "   Start nginx-ui:  /etc/init.d/nginx-ui start"
    echo "   Stop nginx-ui:   /etc/init.d/nginx-ui stop"
    echo ""
    echo "📊 LOGS:"
    echo "   Nginx:           /var/log/nginx/error.log"
    echo "   Nginx-UI:        ${INSTALL_DIR}/logs/nginx-ui.log"
    echo ""
    echo "=============================================="
    echo "   Open your browser and visit:"
    echo "          http://${ROUTER_IP}/"
    echo "=============================================="
}

# Main function
main() {
    echo "Starting installation of nginx-ui v${NGINX_UI_VERSION}"
    echo ""
    
    # Check root
    [ "$(id -u)" -ne 0 ] && { print_error "Run as root"; exit 1; }
    
    # Installation steps
    check_dependencies
    install_nginx_minimal
    download_nginx_ui
    create_nginx_config
    create_nginx_ui_config
    setup_uhttpd
    create_service
    create_dashboard
    create_api
    setup_firewall
    start_services
    print_summary
    
    # Final test
    echo ""
    print_status "Testing installation..."
    if curl -s "http://127.0.0.1/" >/dev/null; then
        print_status "✓ Installation successful!"
    else
        print_warning "⚠ Installation may have issues, check logs"
    fi
}

# Run
main "$@"
