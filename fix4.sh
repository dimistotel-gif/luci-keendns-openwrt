#!/bin/sh
# Fix nginx proxy configuration

echo "🔧 FIXING NGINX PROXY CONFIGURATION"
echo "==================================="

# 1. Backup current config
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# 2. Create proper nginx config with proxy
cat > /etc/nginx/nginx.conf << 'EOF'
worker_processes 1;
pid /tmp/nginx.pid;
error_log /var/log/nginx/error.log;

events {
    worker_connections 512;
}

http {
    # Basic MIME types
    types {
        text/html html htm;
        text/css css;
        text/plain txt;
        image/jpeg jpg jpeg;
        image/png png;
        image/gif gif;
        application/javascript js;
        application/json json;
    }
    default_type application/octet-stream;
    
    # Temp paths
    client_body_temp_path /tmp/nginx_client_body;
    proxy_temp_path /tmp/nginx_proxy;
    
    access_log /var/log/nginx/access.log;
    
    # Main server
    server {
        listen 80;
        server_name _;
        
        # Dashboard root
        location = / {
            root /www/dashboard;
            index index.html;
        }
        
        location / {
            root /www/dashboard;
            try_files $uri $uri/ @proxy;
        }
        
        # Health check
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
        
        # Proxy to nginx-ui (port 9000)
        location @proxy {
            # Check if it's /ui/ request
            if ($request_uri ~ ^/ui/) {
                proxy_pass http://127.0.0.1:9000;
                break;
            }
            
            # Check if it's /luci/ request
            if ($request_uri ~ ^/luci/) {
                proxy_pass http://127.0.0.1:8081;
                break;
            }
            
            # Default to dashboard
            root /www/dashboard;
            index index.html;
        }
        
        # Explicit proxy for /ui/
        location /ui/ {
            proxy_pass http://127.0.0.1:9000/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
        
        # Explicit proxy for /luci/
        location /luci/ {
            proxy_pass http://127.0.0.1:8081/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # API endpoints
        location /api/ {
            proxy_pass http://127.0.0.1:9000/api/;
            proxy_set_header Host $host;
        }
        
        # Static files
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            root /www/dashboard;
            expires 30d;
            add_header Cache-Control "public, immutable";
        }
    }
}
EOF

# 3. Test configuration
echo "Testing configuration..."
if nginx -t; then
    echo "✅ Configuration test passed"
else
    echo "❌ Configuration test failed"
    nginx -t 2>&1
    exit 1
fi

# 4. Restart nginx
echo "Restarting nginx..."
killall nginx 2>/dev/null
sleep 2
nginx -c /etc/nginx/nginx.conf
sleep 2

# 5. Check if running
if ps | grep -q "[n]ginx.*master"; then
    echo "✅ nginx restarted successfully"
else
    echo "❌ nginx failed to restart"
    exit 1
fi

# 6. Create better dashboard with correct URLs
echo "Updating dashboard..."
cat > /www/dashboard/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenWrt Router Manager</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 600px;
            width: 100%;
            text-align: center;
            backdrop-filter: blur(10px);
        }
        .logo {
            font-size: 60px;
            margin-bottom: 20px;
            color: #667eea;
        }
        h1 {
            color: #2c3e50;
            margin-bottom: 10px;
            font-size: 32px;
        }
        .subtitle {
            color: #7f8c8d;
            margin-bottom: 30px;
            font-size: 16px;
        }
        .ip-box {
            background: #e3f2fd;
            padding: 15px;
            border-radius: 10px;
            margin: 20px 0;
            font-family: 'Courier New', monospace;
            font-size: 20px;
            font-weight: bold;
            color: #1976d2;
        }
        .btn {
            display: block;
            width: 100%;
            padding: 16px;
            margin: 12px 0;
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
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        .btn-secondary {
            background: #2196F3;
            color: white;
        }
        .btn-secondary:hover {
            background: #1976D2;
            transform: translateY(-2px);
        }
        .btn-warning {
            background: #FF9800;
            color: white;
        }
        .status-box {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
            text-align: left;
        }
        .status-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 0;
            border-bottom: 1px solid #eee;
        }
        .status-item:last-child {
            border-bottom: none;
        }
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            display: inline-block;
            margin-right: 10px;
        }
        .status-running { background: #4CAF50; }
        .status-stopped { background: #f44336; }
        .warning-box {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-radius: 8px;
            padding: 15px;
            margin: 20px 0;
            text-align: left;
            color: #856404;
        }
        .direct-links {
            margin-top: 20px;
        }
        .direct-links a {
            display: inline-block;
            margin: 5px;
            color: #2196F3;
            text-decoration: none;
        }
        footer {
            margin-top: 30px;
            color: #95a5a6;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🚀</div>
        <h1>OpenWrt Router Manager</h1>
        <p class="subtitle">All services are now running!</p>
        
        <div class="ip-box" id="router-ip">192.168.1.75</div>
        
        <a href="/ui/" class="btn btn-primary" target="_blank">
            📊 Open Nginx-UI Dashboard
        </a>
        
        <a href="/luci/" class="btn btn-secondary" target="_blank">
            ⚙️ Open Luci Interface
        </a>
        
        <a href="/health" class="btn btn-warning" target="_blank">
            🩺 System Health Check
        </a>
        
        <div class="status-box">
            <h3 style="margin-bottom: 15px; color: #2c3e50;">Service Status</h3>
            <div class="status-item">
                <span>Nginx Web Server (port 80)</span>
                <span>
                    <span class="status-dot" id="nginx-dot"></span>
                    <span id="nginx-text">Checking...</span>
                </span>
            </div>
            <div class="status-item">
                <span>Nginx-UI Manager (port 9000)</span>
                <span>
                    <span class="status-dot" id="nginxui-dot"></span>
                    <span id="nginxui-text">Checking...</span>
                </span>
            </div>
            <div class="status-item">
                <span>Luci Interface (port 8081)</span>
                <span>
                    <span class="status-dot" id="luci-dot"></span>
                    <span id="luci-text">Checking...</span>
                </span>
            </div>
        </div>
        
        <div class="warning-box">
            <strong>⚠️ Если ссылки выше не работают:</strong>
            <p>Используйте прямое подключение:</p>
            <div class="direct-links">
                <a href="http://192.168.1.75:9000/" target="_blank">Nginx-UI напрямую (порт 9000)</a><br>
                <a href="http://192.168.1.75:8081/" target="_blank">Luci напрямую (порт 8081)</a>
            </div>
        </div>
        
        <button onclick="checkAllStatus()" style="
            background: #9c27b0;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 14px;
            cursor: pointer;
            margin-top: 10px;
            width: 100%;
        ">
            🔄 Проверить статус
        </button>
        
        <footer>
            <p>OpenWrt Router | Nginx-UI v2.3.2</p>
            <p>Внешний IP: 192.168.1.75 (через Keenetic)</p>
        </footer>
    </div>

    <script>
    // Get current IP from URL
    function getCurrentIP() {
        return window.location.hostname;
    }
    
    // Update IP display
    document.getElementById('router-ip').textContent = getCurrentIP();
    
    // Update direct links
    function updateDirectLinks() {
        const ip = getCurrentIP();
        const links = document.querySelectorAll('.direct-links a');
        links[0].href = `http://${ip}:9000/`;
        links[1].href = `http://${ip}:8081/`;
    }
    
    async function checkService(endpoint, name, elementId, dotId) {
        try {
            const start = Date.now();
            const response = await fetch(endpoint, {
                method: 'GET',
                headers: { 'Cache-Control': 'no-cache' },
                mode: 'no-cors'  // For cross-origin requests
            });
            
            // With no-cors we can't read response, but if no error, it's OK
            document.getElementById(elementId).textContent = 'Работает';
            document.getElementById(dotId).className = 'status-dot status-running';
            return true;
            
        } catch (error) {
            // Try with timeout
            try {
                await Promise.race([
                    fetch(endpoint, { mode: 'no-cors' }),
                    new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout')), 2000))
                ]);
                document.getElementById(elementId).textContent = 'Работает';
                document.getElementById(dotId).className = 'status-dot status-running';
                return true;
            } catch (e) {
                document.getElementById(elementId).textContent = 'Ошибка';
                document.getElementById(dotId).className = 'status-dot status-stopped';
                return false;
            }
        }
    }
    
    async function checkAllStatus() {
        const ip = getCurrentIP();
        
        // Check nginx (port 80)
        await checkService('/health', 'Nginx', 'nginx-text', 'nginx-dot');
        
        // Check nginx-ui (port 9000)
        await checkService(`http://${ip}:9000`, 'Nginx-UI', 'nginxui-text', 'nginxui-dot');
        
        // Check Luci (port 8081)
        await checkService(`http://${ip}:8081`, 'Luci', 'luci-text', 'luci-dot');
    }
    
    // Initial check
    updateDirectLinks();
    checkAllStatus();
    
    // Auto-check every 30 seconds
    setInterval(checkAllStatus, 30000);
    </script>
</body>
</html>
HTML

# 7. Create favicon to avoid 404 errors
echo "Creating favicon..."
echo "data:image/x-icon;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAIGNIUk0AAHolAACAgwAA+f8AAIDpAAB1MAAA6mAAADqYAAAXb5JfxUYAAAEPSURBVHjadJDBSgJhFIXPf2Xq5kz8A4KuoqZBaO4GRDdtXETQD+hR/AtaB24KIqKNG9sIIW6n6TF00QhmZq4HA1d17j33nnvuPZJ8AFABNgFUgAqAknt2AQRxMvzYyQOcAMdA2Zx3gAuQBxByI7sBbAGHAF/9AT6B+91COx9wD9TNvQCYArOx1m/bWgA1oA5MAFxg2IVxDa8c8QJwA8wA3n2g3PIGoNw4Pw1f8gFjYB2gFwFzJ6/dXwEeHeB+ecAIYAw8V4HGZ4BVYOAAHwAuAa6AHnADNIClA3A4M/nM4Z05wI8FuP9qDnCz9J+WBRgALw7Qd4CyGY8zgI8h0DQRcngHtndZgI7lG/wDBj6AAaAKvAKPQG8F4Jh8BFSAP4AP/gYA1tg42M9KpxQAAAAASUVORK5CYII=" | base64 -d > /www/dashboard/favicon.ico 2>/dev/null || true

# 8. Create start-web command
mkdir -p /usr/local/bin
cat > /usr/local/bin/start-web << 'EOF'
#!/bin/sh
echo "Starting all web services..."
echo "============================"

# Start uhttpd (Luci)
if ! ps | grep -q "[u]httpd"; then
    echo "Starting Luci (uHTTPd)..."
    /etc/init.d/uhttpd start
else
    echo "Luci already running"
fi

# Start nginx-ui
if ! ps | grep -q "[n]ginx-ui"; then
    echo "Starting nginx-ui..."
    if [ -f /etc/init.d/nginx-ui ]; then
        /etc/init.d/nginx-ui start
    elif [ -f /opt/nginx-ui/nginx-ui ]; then
        /opt/nginx-ui/nginx-ui -config /etc/nginx-ui/config.yaml &
    fi
else
    echo "nginx-ui already running"
fi

# Start nginx
if ! ps | grep -q "[n]ginx.*master"; then
    echo "Starting nginx..."
    nginx -c /etc/nginx/nginx.conf 2>/dev/null || {
        echo "nginx failed, trying alternative..."
        /usr/sbin/nginx -c /etc/nginx/nginx.conf
    }
else
    echo "nginx already running"
fi

sleep 2

echo ""
echo "Service Status:"
echo "--------------"
ps | grep -E "(nginx|uhttpd)" | grep -v grep || echo "No web services found"

echo ""
echo "Access URLs:"
echo "-----------"
IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.75")
echo "Main Dashboard:    http://$IP/"
echo "Nginx-UI:          http://$IP/ui/"
echo "Lginx-UI Direct:   http://$IP:9000/"
echo "Luci:              http://$IP/luci/"
echo "Luci Direct:       http://$IP:8081/"
EOF

chmod +x /usr/local/bin/start-web

# 9. Create status check command
cat > /usr/local/bin/web-status << 'EOF'
#!/bin/sh
echo "=== Web Services Status ==="
echo ""
echo "1. Processes:"
ps | grep -E "(nginx|uhttpd|nginx-ui)" | grep -v grep || echo "No processes found"
echo ""
echo "2. Listening ports:"
netstat -tln 2>/dev/null | grep -E "(80|8081|9000)" || echo "No relevant ports"
echo ""
echo "3. Connectivity:"
echo "   Local nginx:     $(curl -s -m 2 http://127.0.0.1/health 2>/dev/null || echo "FAILED")"
echo "   nginx-ui:        $(curl -s -m 2 http://127.0.0.1:9000 >/dev/null 2>&1 && echo "OK" || echo "FAILED")"
echo "   Luci:            $(curl -s -m 2 http://127.0.0.1:8081 >/dev/null 2>&1 && echo "OK" || echo "FAILED")"
echo ""
IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.75")
echo "4. External access:"
echo "   Dashboard:       http://$IP/"
echo "   Nginx-UI proxy:  http://$IP/ui/"
echo "   Nginx-UI direct: http://$IP:9000/"
echo "   Luci proxy:      http://$IP/luci/"
echo "   Luci direct:     http://$IP:8081/"
EOF

chmod +x /usr/local/bin/web-status

# 10. Final message
echo ""
echo "=============================================="
echo "   ✅ FIX COMPLETE!"
echo "=============================================="
echo ""
echo "🌐 ВАШ РОУТЕР ДОСТУПЕН ПО АДРЕСУ:"
echo "   http://192.168.1.75/"
echo ""
echo "🔧 КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ:"
echo "   web-status          - Проверить статус"
echo "   start-web           - Запустить все сервисы"
echo "   nginx -t            - Проверить конфиг nginx"
echo ""
echo "📊 СЕРВИСЫ:"
echo "   1. Главная страница - http://192.168.1.75/"
echo "   2. Nginx-UI         - http://192.168.1.75/ui/"
echo "   3. Nginx-UI (прямо) - http://192.168.1.75:9000/"
echo "   4. Luci             - http://192.168.1.75/luci/"
echo "   5. Luci (прямо)     - http://192.168.1.75:8081/"
echo ""
echo "⚠️  Если прокси не работает (/ui/, /luci/):"
echo "   Используйте прямое подключение по портам!"
echo ""
echo "=============================================="
echo "   Откройте браузер: http://192.168.1.75/"
echo "=============================================="

# 11. Quick test
echo ""
echo "Быстрая проверка..."
sleep 2
curl -s "http://127.0.0.1/health" && echo "✅ Nginx работает" || echo "❌ Nginx не отвечает"
curl -s "http://127.0.0.1:9000" >/dev/null && echo "✅ Nginx-UI работает" || echo "❌ Nginx-UI не отвечает"
curl -s "http://127.0.0.1:8081" >/dev/null && echo "✅ Luci работает" || echo "❌ Luci не отвечает"
