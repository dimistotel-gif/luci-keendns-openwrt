#!/bin/sh
# nginx-ui installer for OpenWrt x86_64 - FIXED VERSION
# No package conflicts, preserves Luci interface

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

install_nginx_properly() {
    print_status "Installing nginx (without conflicts)..."
    
    # First, remove any existing nginx packages to avoid conflicts
    opkg remove --force-removal-of-dependent-packages nginx nginx-full nginx-ssl nginx-mod-* 2>/dev/null || true
    
    # Clean up
    rm -rf /etc/nginx /var/lib/nginx /usr/lib/nginx 2>/dev/null
    
    # Update package list
    opkg update
    
    # Install nginx-full (main package) and basic modules
    print_status "Installing nginx-full..."
    opkg install nginx-full
    
    # Install additional modules we need
    print_status "Installing nginx modules..."
    opkg install nginx-mod-luci
    
    # Note: nginx-ssl is not needed as nginx-full already has SSL support
    # nginx-mod-stream may not be available, skip if not found
    if opkg list | grep -q "nginx-mod-stream"; then
        opkg install nginx-mod-stream
    else
        print_warning "nginx-mod-stream not available, skipping..."
    fi
    
    # Stop nginx if running
    /etc/init.d/nginx stop 2>/dev/null || true
    /etc/init.d/nginx disable 2>/dev/null || true
    
    # Remove any auto-generated configs
    rm -rf /etc/nginx/conf.d/* 2>/dev/null
    rm -f /etc/nginx/uci.conf* 2>/dev/null
    
    print_status "Nginx installed successfully"
}

download_nginx_ui() {
    print_status "Downloading nginx-ui for x86_64..."
    
    mkdir -p $INSTALL_DIR
    cd /tmp
    
    # Download latest release
    print_status "Getting latest release info from GitHub..."
    LATEST_URL=$(curl -s https://api.github.com/repos/schenkd/nginx-ui/releases/latest | \
        grep "browser_download_url.*linux-amd64" | \
        cut -d'"' -f4 | head -1)
    
    if [ -z "$LATEST_URL" ]; then
        print_warning "Could not find latest release, trying alternative..."
        # Try direct download of latest
        LATEST_URL="https://github.com/schenkd/nginx-ui/releases/latest/download/nginx-ui-linux-amd64.tar.gz"
    fi
    
    print_status "Downloading from: $LATEST_URL"
    
    # Download with retry
    if ! wget -O nginx-ui.tar.gz "$LATEST_URL"; then
        print_warning "Download failed, trying backup URL..."
        # Backup URL - specific version
        wget -O nginx-ui.tar.gz "https://github.com/schenkd/nginx-ui/releases/download/${NGINX_UI_VERSION}/nginx-ui-linux-amd64.tar.gz"
    fi
    
    if [ ! -f "nginx-ui.tar.gz" ]; then
        print_error "Failed to download nginx-ui"
        return 1
    fi
    
    # Extract
    tar -xzf nginx-ui.tar.gz 2>/dev/null || {
        print_warning "Tar extraction failed, trying gunzip..."
        gunzip -c nginx-ui.tar.gz | tar -x
    }
    
    # Find and move binary
    if [ -f "nginx-ui" ]; then
        mv nginx-ui $INSTALL_DIR/
    elif [ -f "nginx-ui-linux-amd64" ]; then
        mv nginx-ui-linux-amd64 $INSTALL_DIR/nginx-ui
    else
        # Look for binary in extracted directory
        find . -name "nginx-ui*" -type f -executable | head -1 | xargs -I {} mv {} $INSTALL_DIR/nginx-ui
    fi
    
    chmod +x $INSTALL_DIR/nginx-ui 2>/dev/null || {
        print_warning "Could not set executable permissions, trying chmod 755..."
        chmod 755 $INSTALL_DIR/nginx-ui
    }
    
    # Test run
    if $INSTALL_DIR/nginx-ui --version 2>&1 | grep -q -i "nginx-ui\|version"; then
        print_status "✓ nginx-ui binary works!"
    else
        # Try to run it anyway
        print_warning "⚠ nginx-ui version check failed, but continuing..."
        if [ -x "$INSTALL_DIR/nginx-ui" ]; then
            print_status "Binary is executable, proceeding..."
        else
            print_error "✗ nginx-ui binary is not executable"
            return 1
        fi
    fi
}

create_nginx_config_manual() {
    print_status "Creating clean nginx configuration..."
    
    ROUTER_IP=$(get_router_ip)
    
    # Clean up any existing config
    rm -f /etc/nginx/nginx.conf /etc/nginx/uci.conf* 2>/dev/null
    
    # Create fresh nginx config
    cat > /etc/nginx/nginx.conf << 'EOF'
user nobody nogroup;
worker_processes 2;
pid /var/run/nginx.pid;

error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 100M;
    
    # Buffer sizes
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    output_buffers 1 32k;
    postpone_output 1460;
    
    # Timeouts
    client_body_timeout 60s;
    client_header_timeout 60s;
    send_timeout 60s;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/atom+xml image/svg+xml;
    
    # Include other configs
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Create conf.d directory
    mkdir -p /etc/nginx/conf.d
    
    # MAIN PROXY CONFIG - Everything through nginx
    cat > /etc/nginx/conf.d/main.conf << EOF
# Main server block - handles everything on port 80
server {
    listen ${PUBLIC_PORT};
    server_name _;
    
    # Root redirect to dashboard
    location = / {
        return 302 /dashboard/;
    }
    
    # Dashboard interface
    location /dashboard/ {
        alias /www/nginx-dashboard/;
        index index.html;
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        
        # Cache static files
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 30d;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Luci interface (original OpenWrt web interface)
    location /cgi-bin/luci {
        proxy_pass http://127.0.0.1:${LUCI_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
    
    location /luci-static/ {
        proxy_pass http://127.0.0.1:${LUCI_PORT};
        proxy_set_header Host \$host;
        
        # Cache static files
        expires 30d;
        add_header Cache-Control "public, immutable";
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
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # API endpoints
    location /api/ {
        proxy_pass http://127.0.0.1:${NGINX_UI_PORT}/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # Static files for simple interface
    location /static/ {
        alias /www/nginx-static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    # Default error pages
    error_page 404 /dashboard/404.html;
    error_page 500 502 503 504 /dashboard/50x.html;
}
EOF

    # Create a simple default server for unknown hosts
    cat > /etc/nginx/conf.d/default.conf << EOF
# Default server for unknown hosts
server {
    listen ${PUBLIC_PORT} default_server;
    server_name _;
    
    return 302 http://${ROUTER_IP}/dashboard/;
}
EOF

    # Create sites directories
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    print_status "Nginx configuration created"
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
        "log_path": "${INSTALL_DIR}/logs/nginx-ui.log",
        "read_timeout": 60,
        "write_timeout": 60,
        "idle_timeout": 60
    },
    "nginx": {
        "config_path": "/etc/nginx/nginx.conf",
        "config_dir": "/etc/nginx/conf.d",
        "pid_path": "/var/run/nginx.pid",
        "test_config_cmd": "nginx -t",
        "reload_cmd": "nginx -s reload",
        "restart_cmd": "/etc/init.d/nginx restart",
        "access_log_path": "/var/log/nginx/access.log",
        "error_log_path": "/var/log/nginx/error.log"
    },
    "database": {
        "path": "${INSTALL_DIR}/data/nginx-ui.db",
        "max_open_conns": 10,
        "max_idle_conns": 5
    },
    "openwrt": {
        "luci_port": ${LUCI_PORT},
        "router_ip": "$(get_router_ip)"
    }
}
EOF
    
    chmod 600 $CONFIG_DIR/config.json
}

reconfigure_uhttpd() {
    print_status "Reconfiguring uHTTPd for Luci only..."
    
    # Stop uHTTPd
    /etc/init.d/uhttpd stop 2>/dev/null
    sleep 2
    
    # Backup original config
    if [ ! -f /etc/config/uhttpd.backup.original ]; then
        cp /etc/config/uhttpd /etc/config/uhttpd.backup.original
    fi
    
    # Create clean uHTTPd config for Luci only
    cat > /etc/config/uhttpd << EOF
config uhttpd 'main'
    option listen_http "127.0.0.1:${LUCI_PORT}"
    option listen_https "127.0.0.1:${LUCI_PORT}"
    option home '/www'
    option rfc1918_filter '1'
    option max_requests '3'
    option max_connections '100'
    option network_timeout '60'
    option http_keepalive '20'
    option tcp_keepalive '1'
    option ubus_prefix '/ubus'
    
config uhttpd 'ubus'
    option socket '/var/run/ubus.sock'
EOF
    
    # Remove any cgi_prefix that might interfere
    uci delete uhttpd.main.cgi_prefix 2>/dev/null
    uci delete uhttpd.main.interpreter 2>/dev/null
    uci commit uhttpd
    
    print_status "uHTTPd configured for Luci on 127.0.0.1:${LUCI_PORT}"
}

create_nginx_ui_service() {
    print_status "Creating nginx-ui service..."
    
    cat > /etc/init.d/$SERVICE_NAME << EOF
#!/bin/sh /etc/rc.common
# nginx-ui service for OpenWrt

USE_PROCD=1
START=99
STOP=10

PROG="$INSTALL_DIR/nginx-ui"
CONFIG="$CONFIG_DIR/config.json"
LOG_FILE="$INSTALL_DIR/logs/service.log"

validate_service() {
    if [ ! -x "\$PROG" ]; then
        echo "Error: \$PROG not executable"
        return 1
    fi
    
    if [ ! -f "\$CONFIG" ]; then
        echo "Error: Config file \$CONFIG not found"
        return 1
    fi
    
    return 0
}

start_service() {
    if ! validate_service; then
        return 1
    fi
    
    # Create log directory
    mkdir -p "$(dirname "\$LOG_FILE")"
    
    procd_open_instance
    procd_set_param command "\$PROG" -config "\$CONFIG"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 3600 5 0
    procd_set_param env NGINX_UI_INSTANCE=openwrt
    procd_set_param limits nofile=4096
    procd_close_instance
    
    echo "Starting nginx-ui..."
    sleep 2
    
    # Verify it's running
    if ps | grep -q "[n]ginx-ui"; then
        echo "✓ nginx-ui started successfully"
        return 0
    else
        echo "✗ Failed to start nginx-ui"
        return 1
    fi
}

stop_service() {
    echo "Stopping nginx-ui..."
    killall nginx-ui 2>/dev/null
    sleep 1
}
EOF

    chmod +x /etc/init.d/$SERVICE_NAME
    
    # Enable on boot
    /etc/init.d/$SERVICE_NAME enable
    
    print_status "nginx-ui service created"
}

create_dashboard() {
    print_status "Creating dashboard interface..."
    
    mkdir -p /www/nginx-dashboard
    mkdir -p /www/nginx-static
    
    # Dashboard HTML
    cat > /www/nginx-dashboard/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenWrt Router Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            min-height: 100vh;
            padding: 20px;
            color: #333;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        header {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .logo {
            font-size: 48px;
            margin-bottom: 10px;
        }
        
        h1 {
            color: #2c3e50;
            font-size: 2.5rem;
            margin-bottom: 10px;
        }
        
        .subtitle {
            color: #7f8c8d;
            font-size: 1.2rem;
            margin-bottom: 20px;
        }
        
        .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 25px;
            margin-bottom: 30px;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            transition: transform 0.3s, box-shadow 0.3s;
        }
        
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.15);
        }
        
        .card-header {
            display: flex;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid #f0f0f0;
        }
        
        .card-icon {
            font-size: 28px;
            margin-right: 15px;
            width: 50px;
            height: 50px;
            background: #3498db;
            color: white;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .card-title {
            font-size: 1.5rem;
            color: #2c3e50;
            font-weight: 600;
        }
        
        .status {
            display: inline-block;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 0.9rem;
            font-weight: 500;
            margin: 5px 0;
        }
        
        .status-running { background: #d4edda; color: #155724; }
        .status-stopped { background: #f8d7da; color: #721c24; }
        .status-warning { background: #fff3cd; color: #856404; }
        
        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 12px 24px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            cursor: pointer;
            border: none;
            transition: all 0.3s;
            margin: 5px;
            min-width: 120px;
        }
        
        .btn-primary { background: #3498db; color: white; }
        .btn-primary:hover { background: #2980b9; transform: scale(1.05); }
        
        .btn-success { background: #27ae60; color: white; }
        .btn-danger { background: #e74c3c; color: white; }
        .btn-warning { background: #f39c12; color: white; }
        .btn-info { background: #17a2b8; color: white; }
        
        .btn-group {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-top: 15px;
        }
        
        .services-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        
        .service-item {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            transition: background 0.3s;
        }
        
        .service-item:hover {
            background: #e9ecef;
        }
        
        .quick-actions {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        
        .quick-action {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s;
            border: 2px solid transparent;
        }
        
        .quick-action:hover {
            background: #3498db;
            color: white;
            border-color: #2980b9;
            transform: translateY(-3px);
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        
        .stat-item {
            text-align: center;
            padding: 15px;
            background: #f8f9fa;
            border-radius: 10px;
        }
        
        .stat-value {
            font-size: 2rem;
            font-weight: bold;
            color: #2c3e50;
        }
        
        .stat-label {
            font-size: 0.9rem;
            color: #7f8c8d;
            margin-top: 5px;
        }
        
        footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #7f8c8d;
            font-size: 0.9rem;
        }
        
        @media (max-width: 768px) {
            .dashboard-grid {
                grid-template-columns: 1fr;
            }
            
            .btn {
                width: 100%;
                margin: 5px 0;
            }
            
            header {
                padding: 20px;
            }
            
            h1 {
                font-size: 2rem;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="logo">🚀</div>
            <h1>OpenWrt Router Dashboard</h1>
            <p class="subtitle">Centralized management interface for your router</p>
        </header>

        <div class="dashboard-grid">
            <!-- Status Card -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon">📊</div>
                    <h2 class="card-title">System Status</h2>
                </div>
                <div id="system-status">
                    <p><i class="fas fa-spinner fa-spin"></i> Loading system status...</p>
                </div>
                <div class="btn-group">
                    <button class="btn btn-primary" onclick="refreshStatus()">
                        🔄 Refresh
                    </button>
                    <button class="btn btn-info" onclick="showSystemInfo()">
                        ℹ️ System Info
                    </button>
                </div>
            </div>

            <!-- Services Card -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon">⚙️</div>
                    <h2 class="card-title">Services</h2>
                </div>
                <div class="services-list">
                    <div class="service-item">
                        <strong>Nginx</strong>
                        <div id="nginx-status" class="status">Checking...</div>
                        <div class="btn-group" style="margin-top: 10px;">
                            <button class="btn btn-success btn-sm" onclick="controlService('nginx', 'start')">▶</button>
                            <button class="btn btn-warning btn-sm" onclick="controlService('nginx', 'restart')">↻</button>
                            <button class="btn btn-danger btn-sm" onclick="controlService('nginx', 'stop')">⏹</button>
                        </div>
                    </div>
                    
                    <div class="service-item">
                        <strong>Nginx-UI</strong>
                        <div id="nginxui-status" class="status">Checking...</div>
                        <div style="margin-top: 10px;">
                            <button class="btn btn-info" onclick="window.open('/nginx-ui/', '_blank')">Open</button>
                        </div>
                    </div>
                    
                    <div class="service-item">
                        <strong>Luci</strong>
                        <div id="luci-status" class="status">Checking...</div>
                        <div style="margin-top: 10px;">
                            <button class="btn btn-info" onclick="window.open('/cgi-bin/luci', '_blank')">Open</button>
                        </div>
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
                        <strong>Nginx-UI</strong>
                        <small>Advanced Management</small>
                    </div>
                    
                    <div class="quick-action" onclick="window.open('/cgi-bin/luci', '_blank')">
                        <strong>Luci Interface</strong>
                        <small>OpenWrt Native</small>
                    </div>
                    
                    <div class="quick-action" onclick="showProxyManager()">
                        <strong>Proxy Manager</strong>
                        <small>Reverse Proxies</small>
                    </div>
                    
                    <div class="quick-action" onclick="showLogViewer()">
                        <strong>Log Viewer</strong>
                        <small>System Logs</small>
                    </div>
                    
                    <div class="quick-action" onclick="showNetworkInfo()">
                        <strong>Network Info</strong>
                        <small>IP &amp; Connections</small>
                    </div>
                    
                    <div class="quick-action" onclick="showSettings()">
                        <strong>Settings</strong>
                        <small>Configuration</small>
                    </div>
                </div>
            </div>

            <!-- Statistics Card -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon">📈</div>
                    <h2 class="card-title">Statistics</h2>
                </div>
                <div class="stats-grid">
                    <div class="stat-item">
                        <div class="stat-value" id="cpu-usage">--%</div>
                        <div class="stat-label">CPU Usage</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="memory-usage">--%</div>
                        <div class="stat-label">Memory</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="uptime-days">--</div>
                        <div class="stat-label">Uptime (days)</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value" id="connections">--</div>
                        <div class="stat-label">Connections</div>
                    </div>
                </div>
                <div class="btn-group" style="margin-top: 20px;">
                    <button class="btn btn-warning" onclick="restartAllServices()">
                        🔄 Restart All
                    </button>
                    <button class="btn btn-danger" onclick="rebootRouter()">
                        ⚡ Reboot Router
                    </button>
                </div>
            </div>
        </div>

        <footer>
            <p>OpenWrt Router Dashboard v1.0 | Nginx-UI Integrated</p>
            <p>Router IP: <span id="router-ip">192.168.1.1</span> | Status: <span id="overall-status">Online</span></p>
        </footer>
    </div>

    <script>
    // Global variables
    let updateInterval;
    
    // DOM Elements
    const elements = {
        systemStatus: document.getElementById('system-status'),
        nginxStatus: document.getElementById('nginx-status'),
        nginxuiStatus: document.getElementById('nginxui-status'),
        luciStatus: document.getElementById('luci-status'),
        cpuUsage: document.getElementById('cpu-usage'),
        memoryUsage: document.getElementById('memory-usage'),
        uptimeDays: document.getElementById('uptime-days'),
        connections: document.getElementById('connections'),
        routerIp: document.getElementById('router-ip'),
        overallStatus: document.getElementById('overall-status')
    };
    
    // API Endpoints
    const API = {
        status: '/api/status',
        service: '/api/service',
        system: '/api/system',
        nginx: '/api/nginx'
    };
    
    // Utility functions
    async function fetchJSON(url) {
        try {
            const response = await fetch(url);
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return await response.json();
        } catch (error) {
            console.error('Fetch error:', error);
            return null;
        }
    }
    
    async function postJSON(url, data) {
        try {
            const response = await fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });
            return await response.json();
        } catch (error) {
            console.error('POST error:', error);
            return { success: false, error: error.message };
        }
    }
    
    // Status checking
    async function checkServiceStatus(service) {
        try {
            const response = await fetch(`/api/service/${service}/status`);
            const text = await response.text();
            return text.includes('running') ? 'running' : 'stopped';
        } catch {
            return 'unknown';
        }
    }
    
    async function updateAllStatuses() {
        // Update service statuses
        const services = ['nginx', 'nginx-ui', 'uhttpd'];
        for (const service of services) {
            const status = await checkServiceStatus(service);
            updateStatusDisplay(service, status);
        }
        
        // Update system stats
        updateSystemStats();
    }
    
    function updateStatusDisplay(service, status) {
        const element = document.getElementById(`${service}-status`);
        if (!element) return;
        
        element.textContent = status.charAt(0).toUpperCase() + status.slice(1);
        element.className = 'status';
        
        switch (status) {
            case 'running':
                element.classList.add('status-running');
                break;
            case 'stopped':
                element.classList.add('status-stopped');
                break;
            default:
                element.classList.add('status-warning');
                element.textContent = 'Unknown';
        }
    }
    
    async function updateSystemStats() {
        try {
            // Get system info
            const response = await fetch('/api/system/stats');
            const data = await response.json();
            
            if (data) {
                elements.cpuUsage.textContent = data.cpu || '--%';
                elements.memoryUsage.textContent = data.memory || '--%';
                elements.uptimeDays.textContent = data.uptime_days || '--';
                elements.connections.textContent = data.connections || '--';
                
                // Update overall status
                const allRunning = ['nginx', 'nginx-ui', 'uhttpd'].every(s => 
                    document.getElementById(`${s}-status`).classList.contains('status-running')
                );
                
                elements.overallStatus.textContent = allRunning ? 'Online' : 'Degraded';
                elements.overallStatus.style.color = allRunning ? '#27ae60' : '#f39c12';
            }
        } catch (error) {
            console.error('Failed to update system stats:', error);
        }
    }
    
    // Service control
    async function controlService(service, action) {
        if (!confirm(`${action.charAt(0).toUpperCase() + action.slice(1)} ${service}?`)) {
            return;
        }
        
        try {
            const response = await fetch(`/api/service/${service}/${action}`, {
                method: 'POST'
            });
            const result = await response.text();
            
            alert(`${service} ${action}: ${result}`);
            
            // Refresh status after a delay
            setTimeout(() => {
                updateAllStatuses();
            }, 2000);
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    }
    
    async function restartAllServices() {
        if (!confirm('Restart all services?')) return;
        
        const services = ['nginx', 'nginx-ui', 'uhttpd'];
        for (const service of services) {
            await controlService(service, 'restart');
        }
    }
    
    // UI Actions
    function refreshStatus() {
        updateAllStatuses();
        showNotification('Status refreshed', 'success');
    }
    
    function showSystemInfo() {
        window.open('/cgi-bin/luci/admin/system/system', '_blank');
    }
    
    function showProxyManager() {
        window.open('/nginx-ui/#/config', '_blank');
    }
    
    function showLogViewer() {
        window.open('/nginx-ui/#/logs', '_blank');
    }
    
    function showNetworkInfo() {
        window.open('/cgi-bin/luci/admin/network/network', '_blank');
    }
    
    function showSettings() {
        window.open('/nginx-ui/#/settings', '_blank');
    }
    
    async function rebootRouter() {
        if (!confirm('⚠️ Reboot router? This will disconnect you for about 1 minute.')) {
            return;
        }
        
        try {
            const response = await fetch('/api/system/reboot', { method: 'POST' });
            const result = await response.text();
            
            alert('Router rebooting... Please wait about 1 minute before reconnecting.');
            
            // Countdown and redirect
            let seconds = 60;
            const countdown = setInterval(() => {
                elements.systemStatus.innerHTML = `Rebooting... Reconnect in ${seconds}s`;
                seconds--;
                
                if (seconds <= 0) {
                    clearInterval(countdown);
                    window.location.reload();
                }
            }, 1000);
            
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    }
    
    function showNotification(message, type = 'info') {
        // Simple notification
        alert(message);
    }
    
    // Get router IP
    async function getRouterIP() {
        try {
            const response = await fetch('/api/system/ip');
            const data = await response.json();
            elements.routerIp.textContent = data.ip || '192.168.1.1';
        } catch {
            elements.routerIp.textContent = '192.168.1.1';
        }
    }
    
    // Initialize
    async function init() {
        console.log('Initializing dashboard...');
        
        // Get router IP
        await getRouterIP();
        
        // Initial status update
        await updateAllStatuses();
        
        // Set up periodic updates
        updateInterval = setInterval(updateAllStatuses, 30000); // Every 30 seconds
        
        // Update system stats more frequently
        setInterval(updateSystemStats, 10000); // Every 10 seconds
        
        console.log('Dashboard initialized');
    }
    
    // Start everything when page loads
    document.addEventListener('DOMContentLoaded', init);
    
    // Clean up on page unload
    window.addEventListener('beforeunload', () => {
        if (updateInterval) {
            clearInterval(updateInterval);
        }
    });
    </script>
</body>
</html>
HTML

    # Create error pages
    cat > /www/nginx-dashboard/404.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>404 - Page Not Found</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #e74c3c; }
        a { color: #3498db; text-decoration: none; }
    </style>
</head>
<body>
    <h1>404 - Page Not Found</h1>
    <p>The page you're looking for doesn't exist.</p>
    <p><a href="/dashboard/">Return to Dashboard</a></p>
</body>
</html>
EOF

    cat > /www/nginx-dashboard/50x.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>50x - Server Error</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #e74c3c; }
        a { color: #3498db; text-decoration: none; }
    </style>
</head>
<body>
    <h1>50x - Server Error</h1>
    <p>Something went wrong on our server.</p>
    <p><a href="/dashboard/">Return to Dashboard</a></p>
</body>
</html>
EOF

    print_status "Dashboard created at /www/nginx-dashboard/"
}

create_api_backend() {
    print_status "Creating API backend..."
    
    mkdir -p /www/cgi-bin/api
    
    # System status endpoint
    cat > /www/cgi-bin/api/system/stats << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

# Get CPU usage (simplified)
CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
CPU=${CPU%.*}

# Get memory usage
MEMORY=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')

# Get uptime in days
UPTIME_DAYS=$(awk '{print int($1/86400)}' /proc/uptime)

# Get network connections
CONNECTIONS=$(netstat -an | grep -c ESTABLISHED)

echo "{
  \"cpu\": \"${CPU}%\",
  \"memory\": \"${MEMORY}%\",
  \"uptime_days\": \"${UPTIME_DAYS}\",
  \"connections\": \"${CONNECTIONS}\",
  \"timestamp\": \"$(date +%s)\"
}"
EOF

    # Service status endpoint
    cat > /www/cgi-bin/api/service/status << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""

SERVICE=$(echo "$PATH_INFO" | cut -d/ -f3)

case "$SERVICE" in
    nginx)
        if ps | grep -q "[n]ginx.*master"; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    nginx-ui)
        if ps | grep -q "[n]ginx-ui"; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    uhttpd)
        if ps | grep -q "[u]httpd"; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    *)
        echo "unknown"
        ;;
esac
EOF

    # Service control endpoint
    cat > /www/cgi-bin/api/service/control << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""

SERVICE=$(echo "$PATH_INFO" | cut -d/ -f3)
ACTION=$(echo "$PATH_INFO" | cut -d/ -f4)

case "$SERVICE" in
    nginx)
        /etc/init.d/nginx $ACTION 2>&1
        echo "Nginx $ACTION completed"
        ;;
    nginx-ui)
        /etc/init.d/nginx-ui $ACTION 2>&1
        echo "Nginx-UI $ACTION completed"
        ;;
    uhttpd)
        /etc/init.d/uhttpd $ACTION 2>&1
        echo "Luci/uHTTPd $ACTION completed"
        ;;
    *)
        echo "Unknown service: $SERVICE"
        ;;
esac
EOF

    # System IP endpoint
    cat > /www/cgi-bin/api/system/ip << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")

echo "{\"ip\": \"$IP\"}"
EOF

    # Make all scripts executable
    chmod +x /www/cgi-bin/api/* /www/cgi-bin/api/system/* /www/cgi-bin/api/service/* 2>/dev/null
    
    print_status "API backend created"
}

setup_firewall() {
    print_status "Configuring firewall..."
    
    # Check if firewall is installed
    if [ -f /etc/init.d/firewall ]; then
        # Allow port 80 from WAN
        uci add firewall rule 2>/dev/null
        uci set firewall.@rule[-1].name='Nginx-Web'
        uci set firewall.@rule[-1].src='wan'
        uci set firewall.@rule[-1].dest_port='80'
        uci set firewall.@rule[-1].proto='tcp'
        uci set firewall.@rule[-1].target='ACCEPT'
        uci set firewall.@rule[-1].enabled='1'
        
        uci commit firewall
        /etc/init.d/firewall reload
        
        print_status "Firewall rule added for port 80"
    else
        print_warning "Firewall not found, skipping firewall configuration"
    fi
}

setup_luci_menu() {
    print_status "Setting up Luci menu..."
    
    mkdir -p /usr/lib/lua/luci/controller
    mkdir -p /usr/share/luci/menu.d
    
    # Create controller
    cat > /usr/lib/lua/luci/controller/nginx-dashboard.lua << 'EOF'
module("luci.controller.nginx-dashboard", package.seeall)

function index()
    entry({"admin", "services", "nginx-dashboard"}, alias("admin", "services", "nginx-dashboard", "redirect"), _("Router Dashboard"), 90)
    entry({"admin", "services", "nginx-dashboard", "redirect"}, call("redirect_to_dashboard"), nil)
end

function redirect_to_dashboard()
    local http = require("luci.http")
    http.redirect("/dashboard/")
end
EOF

    # Create menu
    cat > /usr/share/luci/menu.d/luci-app-nginx-dashboard.json << 'EOF'
{
    "admin/services/nginx-dashboard": {
        "title": "Router Dashboard",
        "order": 90,
        "action": {
            "type": "firstchild"
        }
    }
}
EOF
    
    print_status "Luci menu created"
}

start_all_services() {
    print_status "Starting all services..."
    
    # Start Luci first
    print_status "Starting Luci (uHTTPd)..."
    /etc/init.d/uhttpd start
    sleep 3
    
    # Start nginx-ui
    print_status "Starting nginx-ui..."
    /etc/init.d/nginx-ui start
    sleep 3
    
    # Start nginx last (it will take over port 80)
    print_status "Starting nginx..."
    /etc/init.d/nginx start
    /etc/init.d/nginx enable
    sleep 5
    
    # Verify services
    print_status "Verifying services..."
    
    local all_ok=true
    
    if ps | grep -q "[n]ginx.*master"; then
        print_status "✓ Nginx is running"
    else
        print_error "✗ Nginx failed to start"
        all_ok=false
    fi
    
    if ps | grep -q "[n]ginx-ui"; then
        print_status "✓ Nginx-UI is running"
    else
        print_warning "⚠ Nginx-UI may not be running (check logs)"
    fi
    
    if ps | grep -q "[u]httpd"; then
        print_status "✓ Luci/uHTTPd is running"
    else
        print_error "✗ Luci/uHTTPd failed to start"
        all_ok=false
    fi
    
    if $all_ok; then
        print_status "✅ All services started successfully!"
    else
        print_warning "⚠ Some services may have issues, check logs"
    fi
}

print_final_summary() {
    ROUTER_IP=$(get_router_ip)
    
    echo ""
    echo "=============================================="
    echo "   🎉 INSTALLATION COMPLETE! 🎉"
    echo "=============================================="
    echo ""
    echo "🌐 ACCESS INFORMATION:"
    echo "   Dashboard:      http://${ROUTER_IP}/"
    echo "   Nginx-UI:       http://${ROUTER_IP}/nginx-ui/"
    echo "   Luci Interface: http://${ROUTER_IP}/cgi-bin/luci"
    echo ""
    echo "🔧 SERVICE MANAGEMENT:"
    echo "   Nginx:      /etc/init.d/nginx {start|stop|restart|reload}"
    echo "   Nginx-UI:   /etc/init.d/nginx-ui {start|stop|restart}"
    echo "   Luci:       /etc/init.d/uhttpd {start|stop|restart}"
    echo ""
    echo "📁 CONFIGURATION FILES:"
    echo "   Nginx config:    /etc/nginx/nginx.conf"
    echo "   Nginx sites:     /etc/nginx/conf.d/"
    echo "   Nginx-UI config: ${CONFIG_DIR}/config.json"
    echo "   Dashboard:       /www/nginx-dashboard/"
    echo ""
    echo "📊 LOG FILES:"
    echo "   Nginx access:    /var/log/nginx/access.log"
    echo "   Nginx error:     /var/log/nginx/error.log"
    echo "   Nginx-UI log:    ${INSTALL_DIR}/logs/nginx-ui.log"
    echo ""
    echo "⚠️ TROUBLESHOOTING:"
    echo "   If Luci is not accessible:"
    echo "     1. Check: /etc/init.d/uhttpd status"
    echo "     2. Check: netstat -tlnp | grep :${LUCI_PORT}"
    echo ""
    echo "   If Nginx is not working:"
    echo "     1. Check config: nginx -t"
    echo "     2. Check logs: tail -f /var/log/nginx/error.log"
    echo ""
    echo "   To revert to original setup:"
    echo "     1. Stop nginx: /etc/init.d/nginx stop"
    echo "     2. Restore uHTTPd: cp /etc/config/uhttpd.backup.original /etc/config/uhttpd"
    echo "     3. Restart uHTTPd: /etc/init.d/uhttpd restart"
    echo ""
    echo "=============================================="
    echo "   Open your browser and go to:"
    echo "          http://${ROUTER_IP}/"
    echo "=============================================="
    echo ""
}

# Main execution
main() {
    echo "Starting nginx-ui installation for x86_64 OpenWrt..."
    echo "This will install nginx, nginx-ui, and create a unified dashboard."
    echo ""
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Check disk space
    DISK_SPACE=$(df / | tail -1 | awk '{print $4}')
    if [ "$DISK_SPACE" -lt 50000 ]; then
        print_warning "Low disk space (${DISK_SPACE}KB free). Installation may fail."
        if ! confirm "Continue anyway?"; then
            exit 1
        fi
    fi
    
    # Installation steps
    backup_luci
    install_nginx_properly
    download_nginx_ui
    create_nginx_config_manual
    create_nginx_ui_config
    reconfigure_uhttpd
    create_nginx_ui_service
    create_dashboard
    create_api_backend
    setup_firewall
    setup_luci_menu
    start_all_services
    
    # Test the installation
    echo ""
    print_status "Testing installation..."
    
    # Wait a moment for services to stabilize
    sleep 5
    
    # Test nginx
    if nginx -t 2>/dev/null; then
        print_status "✓ Nginx configuration test passed"
    else
        print_error "✗ Nginx configuration test failed"
    fi
    
    # Test dashboard access
    if curl -s "http://127.0.0.1/dashboard/" | grep -q "OpenWrt Router Dashboard"; then
        print_status "✓ Dashboard is accessible"
    else
        print_warning "⚠ Dashboard may not be accessible"
    fi
    
    print_final_summary
    
    # Final message
    echo ""
    print_status "Installation completed at $(date)"
    print_status "Router IP: $(get_router_ip)"
    print_status "Recommended: Reboot the router to ensure all changes take effect"
    echo ""
    echo "To reboot: reboot"
    echo ""
}

# Helper function for confirmation
confirm() {
    read -r -p "${1:-Continue?} [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# Run main
main "$@"
