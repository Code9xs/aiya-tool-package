#!/bin/bash

# 检查是否以 root 用户运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以 root 用户运行" 1>&2
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
        # 开放 nginx-prometheus-exporter 端口
        firewall-cmd --permanent --add-port=9113/tcp
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
EXPORTER_NAME="nginx-prometheus-exporter"
EXPORTER_VERSION="1.4.1"
INSTALL_DIR="/usr/local/prometheus/exporter/nginx-exporter"
SERVICE_NAME="nginx-prometheus-exporter"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 检测系统架构并选择对应的安装包
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCHIVE_NAME="nginx-prometheus-exporter_${EXPORTER_VERSION}_linux_amd64.tar.gz"
elif [ "$ARCH" = "aarch64" ]; then
    ARCHIVE_NAME="nginx-prometheus-exporter_${EXPORTER_VERSION}_linux_arm64.tar.gz"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# 检查安装包是否存在
if [ ! -f "$ARCHIVE_NAME" ]; then
    echo "错误: 安装包 $ARCHIVE_NAME 不存在"
    exit 1
fi

# 检查 prometheus 用户是否存在
if ! id "prometheus" &>/dev/null; then
    echo "prometheus 用户不存在，正在创建..."
    useradd -r  -s /sbin/nologin prometheus
    echo "prometheus 用户已创建"
fi

# 获取本机 IP 地址
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 创建安装目录
mkdir -p ${INSTALL_DIR}

# 解压安装包
echo "正在解压 ${ARCHIVE_NAME}..."
tar -xzf ${ARCHIVE_NAME} -C ${INSTALL_DIR}

# 移动可执行文件到安装目录
mv ${INSTALL_DIR}/${EXPORTER_NAME} ${INSTALL_DIR}/${EXPORTER_NAME}_${EXPORTER_VERSION}
ln -sf ${INSTALL_DIR}/${EXPORTER_NAME}_${EXPORTER_VERSION} ${INSTALL_DIR}/${EXPORTER_NAME}
chown -R prometheus:prometheus ${INSTALL_DIR}

# 创建 systemd 服务文件
cat > ${SERVICE_FILE} << EOF
[Unit]
Description=NGINX Prometheus Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=${INSTALL_DIR}/${EXPORTER_NAME} \\
    --nginx.scrape-uri=http://${LOCAL_IP}/stub_status \\
    --web.listen-address=:9113
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 配置
systemctl daemon-reload

# 启动服务
echo "正在启动 ${SERVICE_NAME} 服务..."
systemctl enable ${SERVICE_NAME}
systemctl start ${SERVICE_NAME}

# 检查服务状态
echo "检查服务状态..."
if systemctl is-active ${SERVICE_NAME} &> /dev/null; then
    echo "${SERVICE_NAME} 服务已成功启动"
    echo "服务状态: $(systemctl is-active ${SERVICE_NAME})"
    echo "服务运行信息:"
    systemctl show ${SERVICE_NAME} -p ActiveState,SubState,MainPID | cat
else
    echo "警告: ${SERVICE_NAME} 服务启动失败"
    echo "请检查日志: journalctl -u ${SERVICE_NAME} -n 50"
    exit 1
fi

echo "安装完成！"
echo "服务已配置为监听 http://${LOCAL_IP}:9113/metrics"
echo "NGINX stub_status 端点: http://${LOCAL_IP}/stub_status"
echo "使用以下命令查看服务状态："
echo "systemctl status ${SERVICE_NAME}" 