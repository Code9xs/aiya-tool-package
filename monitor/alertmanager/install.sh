#! /bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限运行" 
   exit 1
fi

# 定义变量
INSTALL_DIR="/usr/local/prometheus/alertmanager"
PROMETHEUS_CONFIG="/usr/local/prometheus/prometheus.yml"
ALERTMANAGER_VERSION="0.28.1"
PACKAGE="alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

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
        # 开放 Alertmanager 端口
        firewall-cmd --permanent --add-port=9093/tcp
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

# 检查 Prometheus 是否已安装
if [ ! -d "/usr/local/prometheus" ]; then
    echo "错误: Prometheus 未安装，请先安装 Prometheus"
    exit 1
fi

# 检查 prometheus 用户是否存在
if ! id "prometheus" &>/dev/null; then
    echo "错误: prometheus 用户不存在，请先安装 Prometheus"
    exit 1
fi

# 创建安装目录
echo "创建安装目录 $INSTALL_DIR..."
mkdir -p $INSTALL_DIR

# 解压安装包
echo "解压安装包..."
tar -xzf $PACKAGE -C /tmp
mv /tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/* $INSTALL_DIR/

# 设置目录权限
echo "设置目录权限..."
chown -R prometheus:prometheus $INSTALL_DIR

# 创建系统服务
echo "创建系统服务..."
cat > /etc/systemd/system/alertmanager.service << EOF
[Unit]
Description=Alertmanager
Documentation=https://prometheus.io/docs/alerting/alertmanager/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=$INSTALL_DIR/alertmanager \\
    --config.file=$INSTALL_DIR/alertmanager.yml \\
    --storage.path=$INSTALL_DIR/data \\
    --web.listen-address=:9093

Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 获取本机 IP 地址
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 更新 Prometheus 配置
echo "更新 Prometheus 配置..."
if [ -f "$PROMETHEUS_CONFIG" ]; then
    # 备份原配置文件
    cp $PROMETHEUS_CONFIG ${PROMETHEUS_CONFIG}.bak
    
    # 删除现有的 alerting 配置（如果存在）
    sed -i '/^alerting:/,/^[a-zA-Z]/d' $PROMETHEUS_CONFIG
    
    # 在文件末尾添加新的配置
    printf "\nalerting:\n  alertmanagers:\n    - static_configs:\n      - targets:\n        - %s:9093\n" "$LOCAL_IP" >> $PROMETHEUS_CONFIG
    
    # 设置配置文件权限
    chown prometheus:prometheus $PROMETHEUS_CONFIG
    echo "Prometheus 配置已更新"
else
    echo "警告: Prometheus 配置文件不存在，请手动配置"
fi

# 重新加载 systemd
systemctl daemon-reload

# 启动 Alertmanager 服务
echo "启动 Alertmanager 服务..."
systemctl enable alertmanager
systemctl start alertmanager

# 检查服务状态
echo "检查服务状态..."
if systemctl is-active alertmanager &> /dev/null; then
    echo "Alertmanager 服务已成功启动"
    echo "服务状态: $(systemctl is-active alertmanager)"
    echo "服务运行信息:"
    systemctl show alertmanager -p ActiveState,SubState,MainPID | cat
else
    echo "警告: Alertmanager 服务启动失败"
    echo "请检查日志: journalctl -u alertmanager -n 50"
    exit 1
fi

# 重启 Prometheus 服务以应用新配置
echo "重启 Prometheus 服务以应用新配置..."
systemctl restart prometheus

echo "Alertmanager 安装完成！"
# 确保有 IP 地址
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
fi

echo "Alertmanager 安装完成！"
echo "访问地址: http://$LOCAL_IP:9093"