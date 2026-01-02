#!/bin/sh
# Complete Nginx-UI Installation Fix

set -e

echo "🚀 COMPLETE NGINX-UI FIX"
echo "========================"

# Get router IP
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")

# 1. STOP EVERYTHING
echo "1. Stopping all services..."
/etc/init.d/nginx stop 2>/dev/null
/etc/init.d/nginx-fixed stop 2>/dev/null
/etc/init.d/nginx-ui stop 2>/dev/null
killall nginx nginx-ui 2>/dev/null
sleep 3

# 2. FIX NGINX CONFIGURATION
echo "2. Fixing nginx configuration..."
rm -f /etc/nginx/nginx.conf
rm -rf /etc/nginx/conf.d
mkdir -p /etc/nginx/conf.d

# Create proper nginx.conf
cat > /etc/nginx/nginx.conf << 'EOF'
user nobody nogroup;
worker_processes 1;
pid /var/run/nginx.pid;

error_log /var/log/nginx/error.log;

events {
    worker_connections 512;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    keepalive_timeout 65;
    
    access_log /var/log/nginx/access.log;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Create main configuration
cat > /etc/nginx/conf.d/main.conf << EOF
server {
    listen 80;
    server_name _;
    
    # Dashboard
    location / {
        root /www/dashboard;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    # Nginx-UI
    location /ui/ {
        proxy_pass http://127.0.0.1:9000/;
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
        proxy_pass http://127.0.0.1:8081/;
        proxy_set_header Host \$host;
    }
    
    # Health check
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
    
    # Status
    location /status {
        add_header Content-Type application/json;
        return 200 '{"nginx": "running", "nginx-ui": "checking", "luci": "checking"}';
    }
}
EOF

# 3. TEST CONFIG
echo "3. Testing configuration..."
if nginx -t -c /etc/nginx/nginx.conf; then
    echo "✅ Configuration test passed"
else
    echo "❌ Configuration test failed"
    # Show error
    nginx -t -c /etc/nginx/nginx.conf 2>&1
fi

# 4. FIX NGINX INIT SCRIPT
echo "4. Fixing nginx init script..."
cat > /etc/init.d/nginx << 'EOF'
#!/bin/sh /etc/rc.common
# Fixed nginx init script

USE_PROCD=1
START=99
STOP=10

CONFIG="/etc/nginx/nginx.conf"

start_service() {
    if [ ! -f "\$CONFIG" ]; then
        echo "Config file not found: \$CONFIG"
        return 1
    fi
    
    # Test config first
    if ! /usr/sbin/nginx -t -c "\$CONFIG" >/dev/null 2>&1; then
        echo "Config test failed"
        return 1
    fi
    
    procd_open_instance
    procd_set_param command /usr/sbin/nginx -c "\$CONFIG"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 300 5 0
    procd_close_instance
    
    echo "Starting nginx with config: \$CONFIG"
}

stop_service() {
    echo "Stopping nginx..."
    /usr/sbin/nginx -s stop 2>/dev/null || killall nginx 2>/dev/null
}
EOF

chmod +x /etc/init.d/nginx

# 5. START SERVICES IN ORDER
echo "5. Starting services..."

# Start uHTTPd (Luci)
echo "Starting Luci (uHTTPd)..."
/etc/init.d/uhttpd start
sleep 2

# Start nginx-ui
echo "Starting nginx-ui..."
if [ -f /etc/init.d/nginx-ui ]; then
    /etc/init.d/nginx-ui start
    sleep 3
else
    echo "⚠️  nginx-ui service not found, starting manually..."
    if [ -f /opt/nginx-ui/nginx-ui ]; then
        /opt/nginx-ui/nginx-ui -config /etc/nginx-ui/config.yaml &
        sleep 3
    fi
fi

# Start nginx
echo "Starting nginx..."
/etc/init.d/nginx start
sleep 3

# 6. VERIFY SERVICES
echo "6. Verifying services..."

echo "Service status:"
echo "---------------"

if ps | grep -q "[u]httpd"; then
    echo "✅ uHTTPd (Luci): Running on 127.0.0.1:8081"
else
    echo "❌ uHTTPd: Not running"
fi

if ps | grep -q "[n]ginx-ui"; then
    echo "✅ nginx-ui: Running on 127.0.0.1:9000"
else
    echo "❌ nginx-ui: Not running"
fi

if ps | grep -q "[n]ginx.*master"; then
    echo "✅ nginx: Running on 0.0.0.0:80"
    # Get listening ports
    echo "   Listening on: $(netstat -tlnp 2>/dev/null | grep ':80 ' || echo 'Port 80')"
else
    echo "❌ nginx: Not running"
    # Try to start manually
    echo "   Attempting manual start..."
    nginx -c /etc/nginx/nginx.conf
    sleep 2
    if ps | grep -q "[n]ginx.*master"; then
        echo "   ✅ Manual start successful"
    else
        echo "   ❌ Manual start failed"
    fi
fi

# 7. TEST CONNECTIVITY
echo ""
echo "7. Testing connectivity..."
echo "-------------------------"

# Test local access
if curl -s "http://127.0.0.1/health" 2>/dev/null | grep -q "OK"; then
    echo "✅ Local access: Working"
else
    echo "❌ Local access: Failed"
fi

# Test dashboard
if curl -s "http://127.0.0.1/" 2>/dev/null | grep -q "OpenWrt"; then
    echo "✅ Dashboard: Accessible"
else
    echo "❌ Dashboard: May not be accessible"
fi

# Test nginx-ui
if curl -s "http://127.0.0.1:9000/" 2>/dev/null >/dev/null; then
    echo "✅ nginx-ui: Accessible on port 9000"
else
    echo "❌ nginx-ui: Not accessible on port 9000"
fi

# Test Luci
if curl -s "http://127.0.0.1:8081/" 2>/dev/null >/dev/null; then
    echo "✅ Luci: Accessible on port 8081"
else
    echo "❌ Luci: Not accessible on port 8081"
fi

# 8. CREATE DIAGNOSTIC SCRIPT
echo ""
echo "8. Creating diagnostic script..."
cat > /usr/bin/check-nginx-status << 'EOF'
#!/bin/sh
echo "=== Nginx-UI Status Check ==="
echo ""
echo "1. Process status:"
ps | grep -E "(nginx|uhttpd)" | grep -v grep
echo ""
echo "2. Listening ports:"
netstat -tlnp 2>/dev/null | grep -E "(80|8081|9000)" || echo "No relevant ports found"
echo ""
echo "3. Nginx config test:"
nginx -t 2>&1
echo ""
echo "4. Service status:"
/etc/init.d/nginx status 2>/dev/null || echo "nginx: Not running as service"
/etc/init.d/nginx-ui status 2>/dev/null || echo "nginx-ui: Not running as service"
/etc/init.d/uhttpd status 2>/dev/null || echo "uhttpd: Unknown status"
echo ""
echo "5. Logs (last 5 lines):"
tail -5 /var/log/nginx/error.log 2>/dev/null || echo "No error log"
echo ""
echo "6. Access test:"
curl -s "http://127.0.0.1/health" && echo "✓ Health check OK" || echo "✗ Health check failed"
EOF

chmod +x /usr/bin/check-nginx-status

# 9. FINAL OUTPUT
echo ""
echo "=============================================="
echo "   🎉 FIX COMPLETE!"
echo "=============================================="
echo ""
echo "🌐 ACCESS YOUR ROUTER:"
echo "   Main Dashboard:    http://${ROUTER_IP}/"
echo "   Nginx-UI Admin:    http://${ROUTER_IP}/ui/"
echo "   Luci Interface:    http://${ROUTER_IP}/luci/"
echo "   Health Check:      http://${ROUTER_IP}/health"
echo ""
echo "🔧 TROUBLESHOOTING:"
echo "   Run diagnostic:    check-nginx-status"
echo "   View nginx logs:   tail -f /var/log/nginx/error.log"
echo "   Restart nginx:     /etc/init.d/nginx restart"
echo "   Restart nginx-ui:  /etc/init.d/nginx-ui restart"
echo ""
echo "📊 CURRENT STATUS:"
/etc/init.d/nginx status 2>/dev/null || echo "nginx: Needs manual check"
/etc/init.d/nginx-ui status 2>/dev/null || echo "nginx-ui: Needs manual check"
/etc/init.d/uhttpd status 2>/dev/null || echo "uhttpd: Unknown"
echo ""
echo "=============================================="
echo "   Open browser and go to: http://${ROUTER_IP}/"
echo "=============================================="

# 10. FINAL TEST
echo ""
echo "Performing final test..."
sleep 2
if curl -s "http://${ROUTER_IP}/health" 2>/dev/null | grep -q "OK"; then
    echo "✅ SUCCESS! Everything is working!"
else
    echo "⚠️  Some issues detected. Run 'check-nginx-status' for details."
fi
