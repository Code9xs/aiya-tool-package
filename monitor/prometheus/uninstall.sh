#! /bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限运行" 
   exit 1
fi

# 定义变量
INSTALL_DIR="/usr/local/prometheus"

echo "开始卸载 Prometheus..."

# 停止并禁用服务
echo "停止 Prometheus 服务..."
if systemctl is-active prometheus &> /dev/null; then
    systemctl stop prometheus
    systemctl disable prometheus
    echo "Prometheus 服务已停止并禁用"
fi

# 删除服务文件
echo "删除服务文件..."
if [ -f "/etc/systemd/system/prometheus.service" ]; then
    rm -f /etc/systemd/system/prometheus.service
    systemctl daemon-reload
    echo "服务文件已删除"
fi

# 删除安装目录
echo "删除安装目录..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf $INSTALL_DIR
    echo "安装目录已删除"
fi

# 删除用户和用户组
echo "删除 Prometheus 用户和用户组..."
if id "prometheus" &>/dev/null; then
    userdel -r prometheus
    echo "Prometheus 用户已删除"
fi

if getent group "prometheus" &>/dev/null; then
    groupdel prometheus
    echo "Prometheus 用户组已删除"
fi

# 移除防火墙规则
echo "移除防火墙规则..."
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active firewalld &> /dev/null; then
        firewall-cmd --permanent --remove-port=9090/tcp
        firewall-cmd --reload
        echo "防火墙规则已移除"
    else
        echo "防火墙服务未运行，跳过防火墙规则移除"
    fi
else
    echo "未检测到 firewalld，跳过防火墙规则移除"
fi

echo "Prometheus 卸载完成！" 