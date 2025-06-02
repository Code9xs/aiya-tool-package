# aiya-tool-package

哎呀工具包 - 针对 RHEL 系列操作系统的自动化安装脚本集合

## 项目简介

本项目是一个针对 RHEL 系列操作系统（如 CentOS、RHEL 等）的自动化运维工具包，包含了服务器初始化、监控系统部署等多个实用工具集合。旨在简化运维工作，提高工作效率。

## 目录结构

```
aiya-tool-package/
├── ServerInitShell/          # 服务器初始化脚本
│   ├── install_jdk.sh       # JDK 安装脚本
│   ├── set_network.sh       # 网络配置脚本
│   ├── set-hostname.sh      # 主机名设置脚本
│   ├── dns_register.sh      # DNS 注册脚本
│   ├── os_init.sh           # 系统初始化脚本
│   └── centos9stream_ali_yum.sh  # CentOS Stream 阿里云源配置
│
├── monitor/                  # 监控系统相关组件
│   ├── prometheus/          # Prometheus 监控系统
│   ├── grafana/             # Grafana 可视化面板
│   ├── alertmanager/        # 告警管理器
│   ├── node-exporter/       # 节点监控导出器
│   └── nginx-prometheus-exporter/  # Nginx 监控导出器
│
└── XiaoYuPaper/             # 小宇论文相关工具
    └── Server/              # 服务器相关配置
```

## 功能特性


### 监控系统 (monitor)
- Prometheus 监控系统部署
- Grafana 可视化面板配置
- AlertManager 告警管理
- Node Exporter 节点监控
- Nginx 监控导出器

## 使用说明

### 监控系统部署
1. 进入 monitor 目录
2. 按照以下顺序部署各个组件：
   - Prometheus
   - Node Exporter
   - AlertManager
   - Grafana
   - Nginx Exporter（如需要）

## 注意事项
1. 所有脚本默认针对 RHEL 系列操作系统优化
2. 执行脚本前请确保具有 root 权限
3. 建议在执行脚本前备份重要数据
4. 部分脚本可能需要根据实际环境修改配置参数

## 贡献指南
欢迎提交 Issue 和 Pull Request 来帮助改进项目。

## 许可证
本项目采用 MIT 许可证，详见 [LICENSE](LICENSE) 文件。
