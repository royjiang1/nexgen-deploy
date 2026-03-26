#!/bin/bash
# ====================================================
# NEXGEN AI Infrastructure - Master Autopilot v1.2
# ====================================================
set -e

# --- 自动化配置变量 ---
GH_USER="royjiang1"
GH_REPO="nexgen-deploy"
DOMAIN="nexgen-server.cc"
EMAIL="roy_huaxiang@hotmail.com"
XRAY_PORT=39010
WS_PATH="/download/tools"
# 自动生成 UUID 并保存，防止重复运行脚本导致 ID 变动
if [ -f "/etc/nexgen_uuid" ]; then
    UUID=$(cat /etc/nexgen_uuid)
else
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "$UUID" > /etc/nexgen_uuid
fi

echo "🚀 NEXGEN 正在执行最高等级部署程序..."

# 1. 系统底层优化 (强制 IPv4 优先，解决 Gemini 地域锁定问题)
echo "🛡️ 网络环境净化..."
sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p >/dev/null

# 2. 安装核心组件
echo "📦 安装依赖组件..."
apt update && apt install -y curl nginx uuid-runtime ufw wget
if ! command -v xray &> /dev/null; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# 3. SSL 证书全自动处理 (非通配符模式，提高兼容性)
echo "🔑 证书自动签发..."
if [ ! -d "/root/.acme.sh" ]; then
    curl https://get.acme.sh | sh
fi
# 停止 Nginx 以便占用 80 端口进行验证
systemctl stop nginx || true

# 申请证书 (同时包含主域名和 api 二级域名)
# 注意：这里去掉了 *.DOMAIN，改成了明确的 api.$DOMAIN
~/.acme.sh/acme.sh --issue -d $DOMAIN -d "api.$DOMAIN" --standalone --force --server zerossl

mkdir -p /etc/nginx/ssl/
~/.acme.sh/acme.sh --install-cert -d $DOMAIN --key-file /etc/nginx/ssl/private.key --fullchain-file /etc/nginx/ssl/fullchain.cer

# 4. 部署伪装站与二级 API
echo "🌐 正在从 GitHub 同步 UI 资源..."
mkdir -p /var/www/html/api/v1
# 优先下载 GitHub 仓库里的 index.html
wget -qO /var/www/html/index.html "https://raw.githubusercontent.com/$GH_USER/$GH_REPO/main/index.html" || echo "<h1>NEXGEN Node Active</h1>" > /var/www/html/index.html
# 生成模拟动态 API 数据
echo '{"status":"operational","node":"JP-TK-NEXTGEN","load":"'$(shuf -i 70-90 -n 1)'.2%","engine":"NexGen-v2"}' > /var/www/html/api/v1/status.json

# 5. Nginx 深度分流配置
echo "⚙️ 配置 Nginx 反向代理..."
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80; server_name $DOMAIN *.$DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $DOMAIN *.$DOMAIN;
    ssl_certificate /etc/nginx/ssl/fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/private.key;
    root /var/www/html;
    
    location /api/v1/status { default_type application/json; try_files /api/v1/status.json =404; }
    
    location $WS_PATH {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:$XRAY_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# 6. Xray 核心配置
echo "💎 同步 Xray 转发逻辑..."
cat > /usr/local/etc/xray/config.json <<EOF
{
    "inbounds": [{
        "port": $XRAY_PORT, "listen": "127.0.0.1", "protocol": "vless",
        "settings": {"clients": [{"id": "$UUID"}], "decryption": "none"},
        "streamSettings": {"network": "ws", "wsSettings": {"path": "$WS_PATH"}}
    }],
    "outbounds": [{"protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}}]
}
EOF

# 7. 启动服务并加固
systemctl restart xray nginx
ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable

echo "--------------------------------------------------"
echo "✅ NEXGEN 基础设施已进入完全运行状态！"
echo "🆔 你的专属 UUID: $UUID"
echo "🌐 访问主页: https://$DOMAIN"
echo "📡 API 监控: https://api.$DOMAIN/api/v1/status"
echo "--------------------------------------------------"
