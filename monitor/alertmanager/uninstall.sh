 #! /bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限运行" 
   exit 1
fi

# 定义变量
INSTALL_DIR="/usr/local/prometheus/alertmanager"
PROMETHEUS_CONFIG="/usr/local/prometheus/prometheus.yml"

echo "开始卸载 Alertmanager..."

# 停止并禁用服务
echo "停止 Alertmanager 服务..."
if systemctl is-active alertmanager &> /dev/null; then
    systemctl stop alertmanager
    systemctl disable alertmanager
    echo "Alertmanager 服务已停止并禁用"
fi

# 删除服务文件
echo "删除服务文件..."
if [ -f "/etc/systemd/system/alertmanager.service" ]; then
    rm -f /etc/systemd/system/alertmanager.service
    systemctl daemon-reload
    echo "服务文件已删除"
fi

# 删除安装目录
echo "删除安装目录..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf $INSTALL_DIR
    echo "安装目录已删除"
fi

# 更新 Prometheus 配置
echo "更新 Prometheus 配置..."
if [ -f "$PROMETHEUS_CONFIG" ]; then
    # 备份原配置文件
    cp $PROMETHEUS_CONFIG ${PROMETHEUS_CONFIG}.bak.uninstall
    
    # 删除 alerting 配置部分
    sed -i '/^alerting:/,/^[a-zA-Z]/d' $PROMETHEUS_CONFIG
    
    # 设置配置文件权限
    chown prometheus:prometheus $PROMETHEUS_CONFIG
    echo "Prometheus 配置已更新"
fi

# 移除防火墙规则
echo "移除防火墙规则..."
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active firewalld &> /dev/null; then
        firewall-cmd --permanent --remove-port=9093/tcp
        firewall-cmd --reload
        echo "防火墙规则已移除"
    else
        echo "防火墙服务未运行，跳过防火墙规则移除"
    fi
else
    echo "未检测到 firewalld，跳过防火墙规则移除"
fi

# 重启 Prometheus 服务以应用新配置
echo "重启 Prometheus 服务以应用新配置..."
if systemctl is-active prometheus &> /dev/null; then
    systemctl restart prometheus
    echo "Prometheus 服务已重启"
fi

echo "Alertmanager 卸载完成！"