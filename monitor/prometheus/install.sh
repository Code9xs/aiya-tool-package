#! /bin/bash
# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限运行" 
   exit 1
fi
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
# 检查防火墙状态
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active firewalld &> /dev/null; then
        echo "正在配置防火墙规则..."
        # 开放 Prometheus 端口
        firewall-cmd --permanent --add-port=9090/tcp
        # 重新加载防火墙配置
        firewall-cmd --reload
        echo "防火墙规则已配置完成"
    else
        echo "防火墙服务未运行，跳过防火墙配置"
    fi
else
    echo "未检测到 firewalld，跳过防火墙配置"
fi

# 定义变量
INSTALL_DIR="/usr/local/prometheus"
PROMETHEUS_VERSION="2.53.4"
X86_PACKAGE="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
ARM_PACKAGE="prometheus-${PROMETHEUS_VERSION}.linux-arm64.tar.gz"

# 检测系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    PACKAGE=$X86_PACKAGE
elif [ "$ARCH" = "aarch64" ]; then
    PACKAGE=$ARM_PACKAGE
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# 检查安装包是否存在
if [ ! -f "$PACKAGE" ]; then
    echo "错误: 安装包 $PACKAGE 不存在"
    exit 1
fi

# 创建安装目录
echo "创建安装目录 $INSTALL_DIR..."
mkdir -p $INSTALL_DIR

# 解压安装包
echo "解压安装包..."
tar -xzf $PACKAGE -C /tmp
mv /tmp/prometheus-${PROMETHEUS_VERSION}.linux-*/* $INSTALL_DIR/

# 创建 Prometheus 用户和组
echo "创建 Prometheus 用户和组..."
groupadd -r prometheus
useradd -r -g prometheus -s /sbin/nologin prometheus

# 设置目录权限
echo "设置目录权限..."
chown -R prometheus:prometheus $INSTALL_DIR

# 创建系统服务
echo "创建系统服务..."
cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=$INSTALL_DIR/prometheus \\
    --config.file=$INSTALL_DIR/prometheus.yml \\
    --storage.tsdb.path=$INSTALL_DIR/data \\
    --web.console.templates=$INSTALL_DIR/consoles \\
    --web.console.libraries=$INSTALL_DIR/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle

Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd
systemctl daemon-reload

# 启动 Prometheus 服务
echo "启动 Prometheus 服务..."
systemctl enable prometheus
systemctl start prometheus

# 检查服务状态
echo "检查服务状态..."
if systemctl is-active prometheus &> /dev/null; then
    echo "Prometheus 服务已成功启动"
    echo "服务状态: $(systemctl is-active prometheus)"
    echo "服务运行信息:"
    systemctl show prometheus -p ActiveState,SubState,MainPID | cat
else
    echo "警告: Prometheus 服务启动失败"
    echo "请检查日志: journalctl -u prometheus -n 50"
    exit 1
fi

# 获取本机 IP 地址
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo "Prometheus 安装完成！"
echo "访问地址: http://$LOCAL_IP:9090"
