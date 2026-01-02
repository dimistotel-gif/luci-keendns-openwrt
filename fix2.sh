#!/bin/sh
# Emergency fix for nginx installation

echo "🚨 EMERGENCY NGINX FIX"
echo "======================"

# 1. INSTALL NGINX PROPERLY
echo "1. Installing nginx with all required files..."
opkg update
opkg install nginx --force-reinstall

# 2. CHECK FOR REQUIRED FILES
echo "2. Checking required files..."
if [ ! -f "/etc/nginx/mime.types" ]; then
    echo "⚠️ mime.types missing, creating..."
    # Create minimal mime.types
    cat > /etc/nginx/mime.types << 'EOF'
types {
    text/html                             html htm shtml;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    application/atom+xml                  atom;
    application/rss+xml                   rss;

    text/mathml                           mml;
    text/plain                            txt;
    text/vnd.sun.j2me.app-descriptor      jad;
    text/vnd.wap.wml                      wml;
    text/x-component                      htc;

    image/png                             png;
    image/svg+xml                         svg svgz;
    image/tiff                            tif tiff;
    image/vnd.wap.wbmp                    wbmp;
    image/webp                            webp;
    image/x-icon                          ico;
    image/x-jng                           jng;
    image/x-ms-bmp                        bmp;

    font/woff                             woff;
    font/woff2                            woff2;

    application/java-archive              jar war ear;
    application/json                      json;
    application/mac-binhex40              hqx;
    application/msword                    doc;
    application/pdf                       pdf;
    application/postscript                ps eps ai;
    application/rtf                       rtf;
    application/vnd.apple.mpegurl         m3u8;
    application/vnd.ms-excel              xls;
    application/vnd.ms-fontobject         eot;
    application/vnd.ms-powerpoint         ppt;
    application/vnd.wap.wmlc              wmlc;
    application/vnd.google-earth.kml+xml  kml;
    application/vnd.google-earth.kmz      kmz;
    application/x-7z-compressed           7z;
    application/x-cocoa                   cco;
    application/x-java-archive-diff       jardiff;
    application/x-java-jnlp-file          jnlp;
    application/x-makeself                run;
    application/x-perl                    pl pm;
    application/x-pilot                   prc pdb;
    application/x-rar-compressed          rar;
    application/x-redhat-package-manager  rpm;
    application/x-sea                     sea;
    application/x-shockwave-flash         swf;
    application/x-stuffit                 sit;
    application/x-tcl                     tcl tk;
    application/x-x509-ca-cert            der pem crt;
    application/x-xpinstall               xpi;
    application/xhtml+xml                 xhtml;
    application/zip                       zip;

    application/octet-stream              bin exe dll;
    application/octet-stream              deb;
    application/octet-stream              dmg;
    application/octet-stream              iso img;
    application/octet-stream              msi msp msm;

    audio/midi                            mid midi kar;
    audio/mpeg                            mp3;
    audio/ogg                             ogg;
    audio/x-m4a                           m4a;
    audio/x-realaudio                     ra;

    video/3gpp                            3gpp 3gp;
    video/mp2t                            ts;
    video/mp4                             mp4;
    video/mpeg                            mpeg mpg;
    video/quicktime                       mov;
    video/webm                            webm;
    video/x-flv                           flv;
    video/x-m4v                           m4v;
    video/x-mng                           mng;
    video/x-ms-asf                        asx asf;
    video/x-ms-wmv                        wmv;
    video/x-msvideo                       avi;
}
EOF
    echo "✅ mime.types created"
fi

# 3. CREATE PROPER NGINX CONFIG
echo "3. Creating proper nginx config..."
cat > /etc/nginx/nginx.conf << 'EOF'
# Minimal nginx configuration for OpenWrt
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
    
    # Virtual hosts
    include /etc/nginx/conf.d/*.conf;
}
EOF

# 4. CREATE CONFIG DIRECTORY
echo "4. Creating config directory..."
mkdir -p /etc/nginx/conf.d

# 5. CREATE MAIN SERVER CONFIG
echo "5. Creating main server config..."
cat > /etc/nginx/conf.d/default.conf << EOF
# Main server configuration
server {
    listen 80;
    server_name _;
    
    # Dashboard
    location / {
        root /www/dashboard;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    # Nginx-UI proxy
    location /ui/ {
        proxy_pass http://127.0.0.1:9000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Luci proxy
    location /luci/ {
        proxy_pass http://127.0.0.1:8081/;
        proxy_set_header Host \$host;
    }
    
    # Health endpoint
    location /health {
        return 200 'healthy\\n';
        add_header Content-Type text/plain;
    }
    
    # Status endpoint
    location /status {
        add_header Content-Type application/json;
        return 200 '{"status": "ok", "services": {"nginx": "running", "nginx-ui": "checking", "luci": "checking"}}';
    }
    
    # Error pages
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
}
EOF

# 6. TEST CONFIGURATION
echo "6. Testing configuration..."
if nginx -t; then
    echo "✅ Configuration test passed"
else
    echo "❌ Configuration test failed, but continuing..."
fi

# 7. FIX NGINX SERVICE
echo "7. Fixing nginx service..."
cat > /etc/init.d/nginx << 'EOF'
#!/bin/sh /etc/rc.common
# nginx init script for OpenWrt

USE_PROCD=1
START=99
STOP=10

start_service() {
    # Test config first
    if ! nginx -t >/dev/null 2>&1; then
        echo "nginx config test failed"
        return 1
    fi
    
    procd_open_instance
    procd_set_param command /usr/sbin/nginx
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 300 5 0
    procd_close_instance
    
    echo "nginx service started"
}

stop_service() {
    nginx -s stop 2>/dev/null || killall nginx 2>/dev/null
    echo "nginx service stopped"
}
EOF

chmod +x /etc/init.d/nginx

# 8. ENABLE AND START NGINX
echo "8. Enabling and starting nginx..."
/etc/init.d/nginx enable
/etc/init.d/nginx start
sleep 3

# 9. CHECK NGINX STATUS
echo "9. Checking nginx status..."
if ps | grep -q "[n]ginx.*master"; then
    echo "✅ nginx is running"
    
    # Test if it's listening on port 80
    if netstat -tln | grep -q ":80 "; then
        echo "✅ nginx is listening on port 80"
    else
        echo "⚠️ nginx is running but not on port 80"
    fi
else
    echo "❌ nginx is not running, trying manual start..."
    nginx
    sleep 2
    if ps | grep -q "[n]ginx.*master"; then
        echo "✅ nginx started manually"
    else
        echo "❌ Failed to start nginx"
    fi
fi

# 10. CHECK UHTTPD (LUCI)
echo "10. Checking uHTTPd (Luci)..."
if ps | grep -q "[u]httpd"; then
    echo "✅ uHTTPd is running"
else
    echo "❌ uHTTPd is not running"
    echo "Starting uHTTPd..."
    /etc/init.d/uhttpd start
    sleep 2
fi

# 11. CHECK NGINX-UI
echo "11. Checking nginx-ui..."
if ps | grep -q "[n]ginx-ui"; then
    echo "✅ nginx-ui is running on port 9000"
else
    echo "❌ nginx-ui is not running"
    if [ -f /etc/init.d/nginx-ui ]; then
        echo "Starting nginx-ui service..."
        /etc/init.d/nginx-ui start
    elif [ -f /opt/nginx-ui/nginx-ui ]; then
        echo "Starting nginx-ui manually..."
        /opt/nginx-ui/nginx-ui -config /etc/nginx-ui/config.yaml &
    fi
    sleep 3
fi

# 12. FINAL TEST
echo ""
echo "12. Final connectivity test..."
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")

echo "Testing connections:"
echo "--------------------"

# Test nginx on localhost
if curl -s "http://127.0.0.1/health" 2>/dev/null | grep -q "healthy"; then
    echo "✅ nginx localhost: OK"
else
    echo "❌ nginx localhost: FAILED"
fi

# Test nginx-ui on port 9000
if curl -s "http://127.0.0.1:9000" 2>/dev/null >/dev/null; then
    echo "✅ nginx-ui port 9000: OK"
else
    echo "❌ nginx-ui port 9000: FAILED"
fi

# Test uhttpd on port 8081
if curl -s "http://127.0.0.1:8081" 2>/dev/null >/dev/null; then
    echo "✅ Luci port 8081: OK"
else
    echo "❌ Luci port 8081: FAILED"
fi

# 13. CREATE DIAGNOSTIC PAGE
echo ""
echo "13. Creating diagnostic page..."
cat > /www/dashboard/status.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Router Status</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .status { padding: 10px; margin: 5px 0; border-radius: 5px; }
        .ok { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
        .warning { background: #fff3cd; color: #856404; }
    </style>
</head>
<body>
    <h1>Router Status Dashboard</h1>
    <div id="status"></div>
    
    <script>
    async function checkService(name, url) {
        try {
            const start = Date.now();
            const response = await fetch(url, { method: 'HEAD', cache: 'no-store' });
            const time = Date.now() - start;
            return {
                name: name,
                status: response.ok ? 'ok' : 'error',
                time: time,
                url: url
            };
        } catch {
            return {
                name: name,
                status: 'error',
                time: 0,
                url: url
            };
        }
    }
    
    async function updateStatus() {
        const services = [
            { name: 'Nginx Web Server', url: '/health' },
            { name: 'Nginx-UI Dashboard', url: '/ui/' },
            { name: 'Luci Interface', url: '/luci/' }
        ];
        
        const container = document.getElementById('status');
        container.innerHTML = '<p>Checking services...</p>';
        
        let allOk = true;
        let html = '';
        
        for (const service of services) {
            const result = await checkService(service.name, service.url);
            const statusClass = result.status === 'ok' ? 'ok' : 'error';
            const statusText = result.status === 'ok' ? '✓ OK' : '✗ ERROR';
            
            html += `
                <div class="status ${statusClass}">
                    <strong>${service.name}</strong><br>
                    Status: ${statusText}<br>
                    Response time: ${result.time}ms<br>
                    URL: <a href="${result.url}" target="_blank">${result.url}</a>
                </div>
            `;
            
            if (result.status !== 'ok') allOk = false;
        }
        
        container.innerHTML = html;
        
        if (allOk) {
            container.innerHTML = '<div class="status ok"><strong>✅ All systems operational!</strong></div>' + html;
        } else {
            container.innerHTML = '<div class="status warning"><strong>⚠️ Some services have issues</strong></div>' + html;
        }
    }
    
    // Initial check
    updateStatus();
    
    // Auto-refresh every 30 seconds
    setInterval(updateStatus, 30000);
    </script>
    
    <p><a href="/">Back to main dashboard</a></p>
</body>
</html>
EOF

# 14. FINAL SUMMARY
echo ""
echo "=============================================="
echo "   🎉 FIX COMPLETE!"
echo "=============================================="
echo ""
echo "📊 SERVICE STATUS:"
echo "   Nginx Web Server:   $(ps | grep -q '[n]ginx.*master' && echo '✅ Running' || echo '❌ Stopped')"
echo "   Nginx-UI Manager:   $(ps | grep -q '[n]ginx-ui' && echo '✅ Running' || echo '❌ Stopped')"
echo "   Luci Interface:     $(ps | grep -q '[u]httpd' && echo '✅ Running' || echo '❌ Stopped')"
echo ""
echo "🌐 ACCESS URLs:"
echo "   Main Dashboard:     http://${ROUTER_IP}/"
echo "   Status Page:        http://${ROUTER_IP}/status.html"
echo "   Nginx-UI:           http://${ROUTER_IP}/ui/"
echo "   Luci:               http://${ROUTER_IP}/luci/"
echo "   Health Check:       http://${ROUTER_IP}/health"
echo ""
echo "🔧 TROUBLESHOOTING:"
echo "   Check logs:         tail -f /var/log/nginx/error.log"
echo "   Test nginx:         nginx -t"
echo "   Restart all:        /etc/init.d/nginx restart && /etc/init.d/nginx-ui restart"
echo ""
echo "=============================================="
echo "   Open browser: http://${ROUTER_IP}/"
echo "=============================================="

# 15. QUICK TEST
echo ""
echo "Quick test:"
curl -s "http://${ROUTER_IP}/health" && echo "✅ Health check successful!" || echo "❌ Health check failed"
