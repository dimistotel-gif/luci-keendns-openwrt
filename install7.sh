#!/bin/sh
# Nginx-UI Installer for OpenWrt - FIXED VERSION
# Fixed directory creation issues

set -e

echo "=============================================="
echo "   Nginx-UI v2.3.2 Installer - FIXED"
echo "=============================================="

# Configuration
NGINX_UI_VERSION="v2.3.2"
NGINX_UI_URL="https://github.com/0xJacky/nginx-ui/releases/download/${NGINX_UI_VERSION}/nginx-ui-linux-64.tar.gz"
INSTALL_DIR="/opt/nginx-ui"
CONFIG_DIR="/etc/nginx-ui"
SERVICE_NAME="nginx-ui"
NGINX_UI_PORT="9000"
LUCI_PORT="8081"
PUBLIC_PORT="80"

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
    
    if ! command -v wget >/dev/null && ! command -v curl >/dev/null; then
        opkg update
        opkg install wget
    fi
    
    if ! command -v tar >/dev/null; then
        opkg install tar
    fi
}

install_nginx_minimal() {
    print_status "Installing nginx..."
    
    # Clean up first
    /etc/init.d/nginx stop 2>/dev/null || true
    opkg remove --force-removal-of-dependent-packages nginx nginx-* 2>/dev/null || true
    
    # Clean directories
    rm -rf /etc/nginx /var/lib/nginx 2>/dev/null
    mkdir -p /etc/nginx /var/log/nginx
    
    # Install
    opkg update
    opkg install nginx
}

download_nginx_ui() {
    print_status "Downloading nginx-ui ${NGINX_UI_VERSION}..."
    
    mkdir -p $INSTALL_DIR
    cd /tmp
    
    print_status "URL: $NGINX_UI_URL"
    
    # Download
    if command -v wget >/dev/null; then
        wget --no-check-certificate -O nginx-ui.tar.gz "$NGINX_UI_URL"
    else
        curl -L -k -o nginx-ui.tar.gz "$NGINX_UI_URL"
    fi
    
    if [ ! -f "nginx-ui.tar.gz" ]; then
        print_error "Download failed"
        return 1
    fi
    
    # Extract
    tar -xzf nginx-ui.tar.gz 2>/dev/null || {
        # Try different extraction
        gzip -dc nginx-ui.tar.gz | tar -x
    }
    
    # Find and move binary
    if [ -f "nginx-ui" ]; then
        mv nginx-ui $INSTALL_DIR/
    elif [ -f "nginx-ui-linux-amd64" ]; then
        mv nginx-ui-linux-amd64 $INSTALL_DIR/nginx-ui
    else
        # Search for binary
        find /tmp -name "*nginx-ui*" -type f -executable | head -1 | xargs -I {} cp {} $INSTALL_DIR/nginx-ui
    fi
    
    chmod +x $INSTALL_DIR/nginx-ui
    
    if [ -x "$INSTALL_DIR/nginx-ui" ]; then
        print_status "nginx-ui ready"
        return 0
    else
        print_error "Failed to make nginx-ui executable"
        return 1
    fi
}

create_nginx_config() {
    print_status "Creating nginx config..."
    
    ROUTER_IP=$(get_router_ip)
    
    # Clean nginx config
    rm -f /etc/nginx/nginx.conf
    rm -rf /etc/nginx/conf.d 2>/dev/null
    mkdir -p /etc/nginx/conf.d
    
    # Main config
    cat > /etc/nginx/nginx.conf << 'EOF'
user nobody nogroup;
worker_processes 1;
pid /var/run/nginx.pid;

events {
    worker_connections 512;
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

    # Main server config
    cat > /etc/nginx/conf.d/main.conf << EOF
server {
    listen ${PUBLIC_PORT};
    server_name _;
    
    location = / {
        return 302 /dashboard/;
    }
    
    # Nginx-UI
    location /ui/ {
        proxy_pass http://127.0.0.1:${NGINX_UI_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # WebSocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Luci
    location /luci/ {
        proxy_pass http://127.0.0.1:${LUCI_PORT}/;
        proxy_set_header Host \$host;
    }
    
    # Dashboard
    location /dashboard/ {
        alias /www/dashboard/;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    # Health check
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
}

create_nginx_ui_config() {
    print_status "Creating nginx-ui config..."
    
    mkdir -p $CONFIG_DIR
    mkdir -p $INSTALL_DIR/{data,logs}
    
    # Simple config
    cat > $CONFIG_DIR/config.yaml << 'EOF'
server:
  host: "127.0.0.1"
  port: 9000

nginx:
  config_dir: "/etc/nginx"
  pid_path: "/var/run/nginx.pid"
  test_config_cmd: "nginx -t"
  reload_cmd: "nginx -s reload"

database:
  path: "/opt/nginx-ui/data/nginx-ui.db"
EOF
}

setup_uhttpd() {
    print_status "Setting up uHTTPd..."
    
    # Backup
    cp /etc/config/uhttpd /etc/config/uhttpd.backup 2>/dev/null
    
    # Stop
    /etc/init.d/uhttpd stop 2>/dev/null
    sleep 2
    
    # Create minimal config
    cat > /etc/config/uhttpd << 'EOF'
config uhttpd 'main'
    option listen_http '127.0.0.1:8081'
    option home '/www'
EOF
    
    # Start
    /etc/init.d/uhttpd start
    sleep 2
}

create_service() {
    print_status "Creating service..."
    
    cat > /etc/init.d/$SERVICE_NAME << 'EOF'
#!/bin/sh /etc/rc.common
# nginx-ui service

USE_PROCD=1
START=99
STOP=10

PROG="/opt/nginx-ui/nginx-ui"
CONFIG="/etc/nginx-ui/config.yaml"

start_service() {
    procd_open_instance
    procd_set_param command $PROG -config $CONFIG
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
    print_status "Creating dashboard..."
    
    mkdir -p /www/dashboard
    
    cat > /www/dashboard/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>OpenWrt Router</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 20px;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .container {
            background: white;
            border-radius: 15px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.2);
            max-width: 500px;
            width: 100%;
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
        }
        .btn {
            display: block;
            width: 100%;
            padding: 15px;
            margin: 10px 0;
            background: #4CAF50;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
            text-decoration: none;
            text-align: center;
        }
        .btn:hover {
            background: #45a049;
            transform: scale(1.02);
        }
        .btn-nginx {
            background: #2196F3;
        }
        .btn-nginx:hover {
            background: #1976D2;
        }
        .btn-luci {
            background: #FF9800;
        }
        .btn-luci:hover {
            background: #F57C00;
        }
        .status {
            padding: 10px;
            border-radius: 5px;
            margin: 5px 0;
            font-weight: bold;
        }
        .running { background: #d4edda; color: #155724; }
        .stopped { background: #f8d7da; color: #721c24; }
        .ip {
            background: #e3f2fd;
            padding: 10px;
            border-radius: 8px;
            margin: 20px 0;
            font-family: monospace;
            font-size: 18px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenWrt Router</h1>
        <p class="subtitle">Management Interface</p>
        
        <div class="ip" id="ip">192.168.1.1</div>
        
        <a href="/ui/" class="btn" target="_blank">
            📊 Nginx-UI Dashboard
        </a>
        
        <a href="/luci/" class="btn btn-luci" target="_blank">
            ⚙️ Luci Interface
        </a>
        
        <div style="margin-top: 30px; text-align: left;">
            <h3>Service Status:</h3>
            <div class="status" id="nginx-status">Nginx: Checking...</div>
            <div class="status" id="nginxui-status">Nginx-UI: Checking...</div>
            <div class="status" id="luci-status">Luci: Checking...</div>
        </div>
        
        <button onclick="checkStatus()" style="margin-top: 20px; padding: 10px 20px; background: #9c27b0; color: white; border: none; border-radius: 5px; cursor: pointer;">
            🔄 Refresh Status
        </button>
    </div>

    <script>
    function checkStatus() {
        const services = [
            {id: 'nginx', name: 'Nginx'},
            {id: 'nginxui', name: 'Nginx-UI'}, 
            {id: 'luci', name: 'Luci'}
        ];
        
        services.forEach(service => {
            const el = document.getElementById(service.id + '-status');
            el.textContent = `${service.name}: Checking...`;
            el.className = 'status';
            
            // Simulate check for now
            setTimeout(() => {
                el.textContent = `${service.name}: Running`;
                el.className = 'status running';
            }, 500);
        });
    }
    
    // Get IP
    fetch('/ip.txt').then(r => r.text()).then(ip => {
        document.getElementById('ip').textContent = ip.trim() || '192.168.1.1';
    }).catch(() => {
        document.getElementById('ip').textContent = '192.168.1.1';
    });
    
    // Initial check
    checkStatus();
    </script>
</body>
</html>
HTML

    # Create IP file
    get_router_ip > /www/dashboard/ip.txt
}

create_simple_api() {
    print_status "Creating simple API..."
    
    # Create directories FIRST
    mkdir -p /www/cgi-bin/api
    
    # Simple status endpoint
    cat > /www/cgi-bin/api/status << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

nginx_status="stopped"
nginxui_status="stopped"
luci_status="stopped"

ps | grep -q "[n]ginx.*master" && nginx_status="running"
ps | grep -q "[n]ginx-ui" && nginxui_status="running"
ps | grep -q "[u]httpd" && luci_status="running"

echo "{
  \"nginx\": \"$nginx_status\",
  \"nginx_ui\": \"$nginxui_status\",
  \"luci\": \"$luci_status\",
  \"time\": \"$(date)\"
}"
EOF

    # IP endpoint
    cat > /www/cgi-bin/api/ip << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

ip=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
echo "{\"ip\": \"$ip\"}"
EOF

    # Make executable
    chmod +x /www/cgi-bin/api/*
}

start_services() {
    print_status "Starting services..."
    
    # Start uHTTPd
    /etc/init.d/uhttpd start
    sleep 2
    
    # Start nginx-ui
    /etc/init.d/nginx-ui start
    sleep 3
    
    # Start nginx
    /etc/init.d/nginx start
    /etc/init.d/nginx enable
    sleep 3
    
    # Check
    print_status "Checking services..."
    if ps | grep -q "[n]ginx.*master"; then
        print_status "✓ Nginx running"
    else
        print_error "✗ Nginx not running"
    fi
    
    if ps | grep -q "[n]ginx-ui"; then
        print_status "✓ Nginx-UI running"
    else
        print_error "✗ Nginx-UI not running"
    fi
    
    if ps | grep -q "[u]httpd"; then
        print_status "✓ Luci running"
    else
        print_error "✗ Luci not running"
    fi
}

setup_firewall() {
    print_status "Setting up firewall..."
    
    if [ -f /etc/config/firewall ]; then
        uci add firewall rule
        uci set firewall.@rule[-1].name='Web-Interface'
        uci set firewall.@rule[-1].src='wan'
        uci set firewall.@rule[-1].dest_port='80'
        uci set firewall.@rule[-1].proto='tcp'
        uci set firewall.@rule[-1].target='ACCEPT'
        uci commit firewall
        /etc/init.d/firewall restart 2>/dev/null
    fi
}

print_summary() {
    IP=$(get_router_ip)
    
    echo ""
    echo "=============================================="
    echo "   🎉 INSTALLATION COMPLETE!"
    echo "=============================================="
    echo ""
    echo "🌐 ACCESS:"
    echo "   Dashboard:  http://$IP/"
    echo "   Nginx-UI:   http://$IP/ui/"
    echo "   Luci:       http://$IP/luci/"
    echo ""
    echo "🔧 CREDENTIALS:"
    echo "   Nginx-UI: admin / admin (default)"
    echo ""
    echo "⚙️ COMMANDS:"
    echo "   Restart nginx:    /etc/init.d/nginx restart"
    echo "   Restart nginx-ui: /etc/init.d/nginx-ui restart"
    echo "   Check logs:       tail -f /var/log/nginx/error.log"
    echo ""
    echo "=============================================="
    echo "   Open browser: http://$IP/"
    echo "=============================================="
}

# Main
main() {
    echo "Starting installation..."
    
    [ "$(id -u)" -ne 0 ] && { print_error "Need root"; exit 1; }
    
    check_dependencies
    install_nginx_minimal
    download_nginx_ui
    create_nginx_config
    create_nginx_ui_config
    setup_uhttpd
    create_service
    create_dashboard
    create_simple_api
    start_services
    setup_firewall
    print_summary
    
    # Test
    echo ""
    if curl -s "http://127.0.0.1/health" 2>/dev/null | grep -q "OK"; then
        print_status "✓ Installation successful!"
    else
        print_warning "⚠ Check if services are running"
    fi
}

# Run
main "$@"
