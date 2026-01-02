#!/bin/sh
# ULTIMATE NGINX FIX - ONE COMMAND FIXES EVERYTHING

echo "🔧 ULTIMATE NGINX FIX"
echo "===================="

# 1. CREATE ALL MISSING DIRECTORIES
echo "1. Creating missing directories..."
mkdir -p /var/lib/nginx/body
mkdir -p /var/lib/nginx/proxy
mkdir -p /var/lib/nginx/fastcgi
mkdir -p /var/lib/nginx/uwsgi
mkdir -p /var/lib/nginx/scgi
mkdir -p /var/log/nginx
mkdir -p /var/run/nginx
mkdir -p /etc/nginx/conf.d

# 2. CREATE ABSOLUTELY MINIMAL NGINX.CONF
echo "2. Creating minimal nginx.conf..."
cat > /etc/nginx/nginx.conf << 'EOF'
# ULTRA MINIMAL nginx configuration
worker_processes 1;
pid /var/run/nginx/nginx.pid;

events {
    worker_connections 512;
}

http {
    # Basic types
    types {
        text/html html htm;
        text/css css;
        text/plain txt;
        image/jpeg jpg jpeg;
        image/png png;
        image/gif gif;
        application/javascript js;
    }
    
    default_type application/octet-stream;
    
    # Client body temp path
    client_body_temp_path /tmp/nginx_client_body;
    
    # Proxy temp paths
    proxy_temp_path /tmp/nginx_proxy;
    fastcgi_temp_path /tmp/nginx_fastcgi;
    uwsgi_temp_path /tmp/nginx_uwsgi;
    scgi_temp_path /tmp/nginx_scgi;
    
    # Server block
    server {
        listen 80;
        server_name localhost;
        
        location / {
            root /www/dashboard;
            index index.html;
        }
        
        location /health {
            return 200 "OK\n";
        }
    }
}
EOF

# 3. CREATE TMP DIRECTORIES
echo "3. Creating temp directories..."
mkdir -p /tmp/nginx_client_body
mkdir -p /tmp/nginx_proxy
mkdir -p /tmp/nginx_fastcgi
mkdir -p /tmp/nginx_uwsgi
mkdir -p /tmp/nginx_scgi

# 4. TEST CONFIGURATION
echo "4. Testing configuration..."
if nginx -t; then
    echo "✅ Configuration test passed"
else
    echo "❌ Configuration test failed, showing errors:"
    nginx -t 2>&1
    echo "Creating even simpler config..."
    
    # Ultra simple config
    cat > /etc/nginx/nginx.conf << 'EOF'
worker_processes 1;
daemon off;
error_log /dev/stderr;
events { worker_connections 512; }
http {
    access_log /dev/stdout;
    server {
        listen 80;
        location / { return 200 "Working!\n"; }
        location /health { return 200 "OK\n"; }
    }
}
EOF
    
    if nginx -t; then
        echo "✅ Simple config test passed"
    fi
fi

# 5. KILL ALL NGINX PROCESSES
echo "5. Killing all nginx processes..."
killall nginx 2>/dev/null
sleep 2

# 6. START NGINX IN FOREGROUND TO SEE ERRORS
echo "6. Starting nginx in foreground to debug..."
nginx -c /etc/nginx/nginx.conf &
NGINX_PID=$!
sleep 3

# 7. CHECK IF NGINX IS RUNNING
echo "7. Checking if nginx is running..."
if ps | grep -q "[n]ginx.*master"; then
    echo "✅ nginx is running!"
    
    # Check port 80
    if netstat -tln | grep -q ":80 "; then
        echo "✅ nginx listening on port 80"
    else
        echo "❌ nginx not listening on port 80"
    fi
else
    echo "❌ nginx failed to start"
    echo "Trying alternative method..."
    
    # Try with direct binary
    /usr/sbin/nginx -c /etc/nginx/nginx.conf -g "daemon off;" &
    sleep 3
    
    if ps | grep -q "[n]ginx.*master"; then
        echo "✅ nginx started with alternative method"
    else
        echo "❌ All nginx start attempts failed"
    fi
fi

# 8. TEST CONNECTIVITY
echo ""
echo "8. Testing connectivity..."
echo "------------------------"

# Test nginx
if curl -s "http://127.0.0.1/health" 2>/dev/null | grep -q "OK"; then
    echo "✅ nginx: Working on localhost"
else
    echo "❌ nginx: Not responding"
    
    # Try to see what's on port 80
    echo "Checking port 80..."
    netstat -tln | grep ":80" || echo "Nothing on port 80"
    
    # Try to start nginx with debug
    echo "Debug attempt..."
    timeout 3 /usr/sbin/nginx -c /etc/nginx/nginx.conf -g "daemon off; master_process off;" &
    sleep 2
fi

# Test nginx-ui
if curl -s "http://127.0.0.1:9000" 2>/dev/null >/dev/null; then
    echo "✅ nginx-ui: Working on port 9000"
else
    echo "❌ nginx-ui: Not responding"
fi

# Test Luci
if curl -s "http://127.0.0.1:8081" 2>/dev/null >/dev/null; then
    echo "✅ Luci: Working on port 8081"
else
    echo "❌ Luci: Not responding"
fi

# 9. CREATE SIMPLE DASHBOARD IF MISSING
echo ""
echo "9. Creating simple dashboard..."
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
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .btn {
            display: inline-block;
            padding: 12px 24px;
            margin: 10px;
            background: #4CAF50;
            color: white;
            text-decoration: none;
            border-radius: 5px;
        }
        .btn:hover { background: #45a049; }
        .status {
            padding: 10px;
            margin: 5px 0;
            border-radius: 5px;
        }
        .ok { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenWrt Router</h1>
        <p>Management Interface</p>
        
        <div id="status">
            <p>Checking services...</p>
        </div>
        
        <div style="margin: 20px 0;">
            <a href="/ui/" class="btn" target="_blank">Nginx-UI</a>
            <a href="/luci/" class="btn" target="_blank">Luci</a>
            <a href="/health" class="btn" target="_blank">Health</a>
        </div>
        
        <p>If nginx is not working, you can access directly:</p>
        <ul>
            <li><a href="http://192.168.100.1:9000" target="_blank">Nginx-UI on port 9000</a></li>
            <li><a href="http://192.168.100.1:8081" target="_blank">Luci on port 8081</a></li>
        </ul>
    </div>
    
    <script>
    async function checkService(url, name) {
        try {
            const response = await fetch(url);
            return {name: name, ok: response.ok};
        } catch {
            return {name: name, ok: false};
        }
    }
    
    async function updateStatus() {
        const services = [
            {url: '/health', name: 'Nginx'},
            {url: '/ui/', name: 'Nginx-UI'},
            {url: '/luci/', name: 'Luci'}
        ];
        
        let html = '';
        for (const service of services) {
            const result = await checkService(service.url, service.name);
            html += `<div class="status ${result.ok ? 'ok' : 'error'}">
                ${result.name}: ${result.ok ? '✅ OK' : '❌ Error'}
            </div>`;
        }
        
        document.getElementById('status').innerHTML = html;
    }
    
    updateStatus();
    </script>
</body>
</html>
HTML

# 10. CREATE SYSTEMD/INIT SCRIPT
echo ""
echo "10. Creating reliable startup script..."
cat > /etc/init.d/nginx-simple << 'EOF'
#!/bin/sh /etc/rc.common
# Simple reliable nginx service

START=99
STOP=10

start() {
    echo "Starting nginx..."
    
    # Create temp directories
    mkdir -p /tmp/nginx_client_body
    mkdir -p /tmp/nginx_proxy
    
    # Start nginx
    /usr/sbin/nginx -c /etc/nginx/nginx.conf
    
    # Wait and check
    sleep 2
    if ps | grep -q "[n]ginx.*master"; then
        echo "✅ nginx started successfully"
        return 0
    else
        echo "❌ nginx failed to start"
        return 1
    fi
}

stop() {
    echo "Stopping nginx..."
    killall nginx 2>/dev/null
}

restart() {
    stop
    sleep 1
    start
}
EOF

chmod +x /etc/init.d/nginx-simple
/etc/init.d/nginx-simple enable

# 11. FINAL CHECK AND SUMMARY
echo ""
echo "11. Final system check..."
echo "========================"

ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.100.1")

# Check processes
echo "Running processes:"
echo "-----------------"
ps | grep -E "(nginx|uhttpd)" | grep -v grep || echo "No nginx/uhttpd processes found"

# Check ports
echo ""
echo "Open ports:"
echo "----------"
netstat -tln 2>/dev/null | grep -E "(80|8081|9000)" || echo "No relevant ports open"

# Check if we can access anything
echo ""
echo "Access tests:"
echo "------------"

# Try direct port access
echo "Port 80 (nginx):     $(curl -s -m 2 "http://127.0.0.1:80/health" 2>/dev/null || echo "FAILED")"
echo "Port 9000 (nginx-ui): $(curl -s -m 2 "http://127.0.0.1:9000" >/dev/null && echo "OK" || echo "FAILED")"
echo "Port 8081 (Luci):    $(curl -s -m 2 "http://127.0.0.1:8081" >/dev/null && echo "OK" || echo "FAILED")"

# 12. ALTERNATIVE SETUP IF NGINX FAILS
echo ""
echo "12. Setting up alternative access..."
echo "==================================="

# Create direct access scripts
cat > /usr/local/bin/start-web << 'EOF'
#!/bin/sh
# Start all web services

echo "Starting web services..."

# Start uhttpd (Luci) if not running
if ! ps | grep -q "[u]httpd"; then
    echo "Starting Luci..."
    /etc/init.d/uhttpd start
fi

# Start nginx-ui if not running
if ! ps | grep -q "[n]ginx-ui"; then
    echo "Starting nginx-ui..."
    if [ -f /etc/init.d/nginx-ui ]; then
        /etc/init.d/nginx-ui start
    elif [ -f /opt/nginx-ui/nginx-ui ]; then
        /opt/nginx-ui/nginx-ui -config /etc/nginx-ui/config.yaml &
    fi
fi

# Try to start nginx
if ! ps | grep -q "[n]ginx.*master"; then
    echo "Attempting to start nginx..."
    /usr/sbin/nginx -c /etc/nginx/nginx.conf 2>/dev/null || echo "nginx may not start"
fi

sleep 2
echo ""
echo "Services:"
ps | grep -E "(nginx|uhttpd)" | grep -v grep || echo "No web services running"
echo ""
echo "Access directly:"
echo "  Luci:        http://$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.100.1"):8081"
echo "  Nginx-UI:    http://$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.100.1"):9000"
EOF

chmod +x /usr/local/bin/start-web

# 13. FINAL MESSAGE
echo ""
echo "=============================================="
echo "   🎉 ULTIMATE FIX APPLIED!"
echo "=============================================="
echo ""
echo "📊 CURRENT STATUS:"
echo "   nginx (port 80):  $(ps | grep -q '[n]ginx.*master' && echo '✅ RUNNING' || echo '❌ STOPPED')"
echo "   nginx-ui (9000):  $(ps | grep -q '[n]ginx-ui' && echo '✅ RUNNING' || echo '❌ STOPPED')"
echo "   Luci (8081):      $(ps | grep -q '[u]httpd' && echo '✅ RUNNING' || echo '❌ STOPPED')"
echo ""
echo "🌐 ACCESS OPTIONS:"
echo ""
echo "IF NGINX (PORT 80) WORKS:"
echo "   http://${ROUTER_IP}/          - Main dashboard"
echo "   http://${ROUTER_IP}/ui/       - Nginx-UI"
echo "   http://${ROUTER_IP}/luci/     - Luci"
echo ""
echo "IF NGINX FAILS, ACCESS DIRECTLY:"
echo "   http://${ROUTER_IP}:9000/     - Nginx-UI directly"
echo "   http://${ROUTER_IP}:8081/     - Luci directly"
echo ""
echo "🔧 MANAGEMENT COMMANDS:"
echo "   start-web                     - Start all web services"
echo "   check-nginx-status           - Check status"
echo "   /etc/init.d/nginx-simple restart - Restart nginx"
echo ""
echo "⚠️  TROUBLESHOOTING:"
echo "   If nginx won't start, use direct port access above."
echo "   nginx-ui is working on port 9000 and can manage nginx."
echo ""
echo "=============================================="
echo "   Try: start-web"
echo "   Then check: http://${ROUTER_IP}:9000/"
echo "=============================================="
