#!/bin/bash

# 检查是否以 root 用户运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以 root 用户运行" 1>&2
   exit 1
fi

# 定义变量
SERVICE_NAME="nginx-prometheus-exporter"
INSTALL_DIR="/usr/local/prometheus/exporter/nginx-exporter"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 停止并禁用服务
echo "正在停止 ${SERVICE_NAME} 服务..."
systemctl stop ${SERVICE_NAME}
systemctl disable ${SERVICE_NAME}

# 清理防火墙规则
echo "清理防火墙规则..."
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active firewalld &> /dev/null; then
        echo "正在移除防火墙规则..."
        firewall-cmd --permanent --remove-port=9113/tcp
        firewall-cmd --reload
        echo "防火墙规则已清理完成"
    else
        echo "防火墙服务未运行，跳过防火墙规则清理"
    fi
else
    echo "未检测到 firewalld，跳过防火墙规则清理"
fi

# 删除服务文件
echo "正在删除服务文件..."
rm -f ${SERVICE_FILE}
systemctl daemon-reload

# 删除安装目录
echo "正在删除安装目录..."
rm -rf ${INSTALL_DIR}

echo "卸载完成！"
echo "所有相关文件和服务已被移除。" 