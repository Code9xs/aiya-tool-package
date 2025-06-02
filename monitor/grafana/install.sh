 #! /bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限运行" 
   exit 1
fi

# 定义变量
INSTALL_DIR="/usr/local/prometheus/grafana"
GRAFANA_VERSION="12.0.1"
PACKAGE="grafana-enterprise-${GRAFANA_VERSION}.linux-amd64.tar.gz"

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
        # 开放 Grafana 端口
        firewall-cmd --permanent --add-port=3000/tcp
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

# 列出 /tmp 目录下的 grafana 相关目录
echo "检查解压后的目录..."
GRAFANA_TMP_DIRS=($(ls -d /tmp/grafana-* 2>/dev/null))

if [ ${#GRAFANA_TMP_DIRS[@]} -eq 0 ]; then
    echo "错误: 无法找到解压后的 Grafana 目录"
    echo "当前 /tmp 目录内容:"
    ls -la /tmp
    exit 1
fi

if [ ${#GRAFANA_TMP_DIRS[@]} -gt 1 ]; then
    echo "警告: 发现多个 Grafana 目录，将使用最新的目录"
    GRAFANA_TMP_DIR=${GRAFANA_TMP_DIRS[-1]}
else
    GRAFANA_TMP_DIR=${GRAFANA_TMP_DIRS[0]}
fi

echo "使用目录: $GRAFANA_TMP_DIR"
echo "移动文件到安装目录..."
mv "$GRAFANA_TMP_DIR"/* "$INSTALL_DIR"/ 2>/dev/null || {
    echo "错误: 移动文件失败"
    echo "源目录内容:"
    ls -la "$GRAFANA_TMP_DIR"
    echo "目标目录内容:"
    ls -la "$INSTALL_DIR"
    exit 1
}

# 清理临时目录
rmdir "$GRAFANA_TMP_DIR" 2>/dev/null || true

# 设置目录权限
echo "设置目录权限..."
chown -R prometheus:prometheus $INSTALL_DIR

# 创建数据目录
echo "创建数据目录..."
mkdir -p $INSTALL_DIR/data
chown -R prometheus:prometheus $INSTALL_DIR/data

# 创建系统服务
echo "创建系统服务..."
cat > /etc/systemd/system/grafana.service << EOF
[Unit]
Description=Grafana Metrics Dashboard
Documentation=https://grafana.com/docs/
After=network.target prometheus.service  # 若依赖 Prometheus 则添加

[Service]
User=prometheus
Group=prometheus
Type=notify
ExecStart=/usr/local/prometheus/grafana/bin/grafana-server \\
  --config=/usr/local/prometheus/grafana/conf/defaults.ini \\
  --homepath=/usr/local/prometheus/grafana \\
  --packaging=rpm \\
  cfg:default.paths.logs=/usr/local/prometheus/grafana/logs \\
  cfg:default.paths.data=/usr/local/prometheus/grafana/data \\
  cfg:default.paths.plugins=/usr/local/prometheus/grafana/plugins
Restart=on-failure
LimitNOFILE=65536  # 文件描述符限制（Grafana 默认要求）

[Install]
WantedBy=multi-user.target
EOF


# 设置配置文件权限
chown prometheus:prometheus $INSTALL_DIR/conf/defaults.ini

# 重新加载 systemd
systemctl daemon-reload

# 启动 Grafana 服务
echo "启动 Grafana 服务..."
systemctl enable grafana
systemctl start grafana

# 获取本机 IP 地址
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 检查服务状态
echo "检查服务状态..."
if systemctl is-active grafana &> /dev/null; then
    echo "Grafana 服务已成功启动"
    echo "服务状态: $(systemctl is-active grafana)"
    echo "服务运行信息:"
    systemctl show grafana -p ActiveState,SubState,MainPID | cat
else
    echo "警告: Grafana 服务启动失败"
    echo "请检查日志: journalctl -u grafana -n 50"
    exit 1
fi

echo "Grafana 安装完成！"
echo "访问地址: http://$LOCAL_IP:3000"
echo "默认用户名: admin"
echo "默认密码: admin"
echo "请登录后立即修改默认密码！"