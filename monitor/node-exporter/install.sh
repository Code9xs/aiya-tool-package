#! /bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限运行" 
   exit 1
fi

# 定义变量
INSTALL_DIR="/usr/local/prometheus/exporter/node_exporter"
NODE_EXPORTER_VERSION="1.9.1"
PACKAGE="node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

# 检查 SELinux 状态
echo "检查 SELinux 状态..."
SELINUX_STATUS=$(getenforce)
if [ "$SELINUX_STATUS" = "Enforcing" ]; then
    echo "SELinux 当前状态为 Enforcing，需要临时关闭..."
    setenforce 0
    echo "SELinux 已临时关闭"
    
    # 永久关闭 SELinux
    if grep -q "SELINUX=enforcing" /etc/selinux/config; then
        echo "正在永久关闭 SELinux..."
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        echo "SELinux 已永久关闭，需要重启系统生效"
    fi
fi

# 配置防火墙
echo "配置防火墙..."
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active firewalld &> /dev/null; then
        echo "正在配置防火墙规则..."
        # 开放 node-exporter 端口
        firewall-cmd --permanent --add-port=9100/tcp
        # 重新加载防火墙配置
        firewall-cmd --reload
        echo "防火墙规则已配置完成"
    else
        echo "防火墙服务未运行，跳过防火墙配置"
    fi
else
    echo "未检测到 firewalld，跳过防火墙配置"
fi

# 检查安装包是否存在
if [ ! -f "$PACKAGE" ]; then
    echo "错误: 安装包 $PACKAGE 不存在"
    exit 1
fi

# 检查 prometheus 用户是否存在
if ! id "prometheus" &>/dev/null; then
    echo "prometheus 用户不存在，即将创建"
    useradd -m prometheus
fi

# 创建安装目录
echo "创建安装目录 $INSTALL_DIR..."
mkdir -p $INSTALL_DIR

# 解压安装包
echo "解压安装包..."
tar -xzf $PACKAGE -C /tmp

# 移动文件到安装目录
echo "移动文件到安装目录..."
mv /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/* $INSTALL_DIR/

# 设置目录权限
echo "设置目录权限..."
chown -R prometheus:prometheus $INSTALL_DIR

# 创建系统服务
echo "创建系统服务..."
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=$INSTALL_DIR/node_exporter \\
    --web.listen-address=:9100 \\
    --collector.systemd \\
    --collector.systemd.unit-whitelist=(docker|sshd|nginx).service \\
    --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd
systemctl daemon-reload

# 启动 node-exporter 服务
echo "启动 node-exporter 服务..."
systemctl enable node_exporter
systemctl start node_exporter

# 获取本机 IP 地址
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 检查服务状态
echo "检查服务状态..."
if systemctl is-active node_exporter &> /dev/null; then
    echo "node-exporter 服务已成功启动"
    echo "服务状态: $(systemctl is-active node_exporter)"
    echo "服务运行信息:"
    systemctl show node_exporter -p ActiveState,SubState,MainPID | cat
else
    echo "警告: node-exporter 服务启动失败"
    echo "请检查日志: journalctl -u node_exporter -n 50"
    exit 1
fi

echo "node-exporter 安装完成！"
echo "访问地址: http://$LOCAL_IP:9100"
echo "指标地址: http://$LOCAL_IP:9100/metrics" 