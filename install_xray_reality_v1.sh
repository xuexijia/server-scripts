cat > install_xray_reality.sh <<'EOF'
#!/bin/bash
set -e

XRAY_DIR="/usr/local/Xray"
CONFIG_DIR="/usr/local/Xray/config"
INFO_FILE="/root/reality-info.txt"
SNI="www.cloudflare.com"
PORT="443"
NODE_NAME="GCP-Reality"

echo "1. 安装必要工具..."
apt update -y
apt install -y curl unzip wget nano openssl ca-certificates

echo "2. 安装 Xray Core..."
mkdir -p "$CONFIG_DIR"
cd "$XRAY_DIR"

curl -L -o Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip -o Xray-linux-64.zip
chmod +x xray

echo "3. 生成 Reality 参数..."
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$("$XRAY_DIR/xray" x25519)

PRIVATE_KEY=$(echo "$KEYS" | sed -n 's/^PrivateKey:[[:space:]]*//p')
PUBLIC_KEY=$(echo "$KEYS" | sed -n 's/^Password (PublicKey):[[:space:]]*//p')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
  echo "错误：Reality 密钥生成失败。"
  echo "Xray 输出如下："
  echo "$KEYS"
  exit 1
fi

SHORT_ID=$(openssl rand -hex 4)
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || echo "请手动填写服务器公网IP")

VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${NODE_NAME}"

echo "4. 写入 Xray 配置..."
cat > "$CONFIG_DIR/config.json" <<CONFIG
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision",
            "email": "gcp-reality"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
CONFIG

echo "5. 创建 systemd 服务..."
cat > /etc/systemd/system/xray.service <<SERVICE
[Unit]
Description=Xray Reality Service
After=network.target

[Service]
Type=simple
ExecStart=$XRAY_DIR/xray -config $CONFIG_DIR/config.json
Restart=on-failure
RestartSec=5s
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

echo "6. 测试配置..."
"$XRAY_DIR/xray" -test -config "$CONFIG_DIR/config.json"

echo "7. 启动 Xray..."
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo "8. 保存连接信息..."
cat > "$INFO_FILE" <<INFO
Reality 节点信息
==============================

服务器IP:
$SERVER_IP

端口:
$PORT

UUID:
$UUID

PublicKey:
$PUBLIC_KEY

PrivateKey:
$PRIVATE_KEY

ShortID:
$SHORT_ID

ServerName / SNI:
$SNI

Flow:
xtls-rprx-vision

协议:
VLESS

传输:
TCP

安全:
Reality

配置文件:
$CONFIG_DIR/config.json

查看服务状态:
systemctl status xray --no-pager -l

查看配置参数:
cat $INFO_FILE

==============================
客户端一般需要填写：
IP: $SERVER_IP
Port: $PORT
UUID: $UUID
PublicKey: $PUBLIC_KEY
ShortID: $SHORT_ID
SNI: $SNI
Flow: xtls-rprx-vision

==============================
VLESS 分享链接：
$VLESS_LINK

INFO

echo ""
echo "安装完成，请保存下面信息到 KeePassXC："
echo "=============================="
cat "$INFO_FILE"
echo "=============================="
echo ""
systemctl status xray --no-pager -l
EOF

chmod +x install_xray_reality.sh
sudo ./install_xray_reality.sh
