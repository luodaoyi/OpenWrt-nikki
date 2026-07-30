![GitHub License](https://img.shields.io/github/license/nikkinikki-org/OpenWrt-nikki?style=for-the-badge&logo=github) ![GitHub Tag](https://img.shields.io/github/v/release/nikkinikki-org/OpenWrt-nikki?style=for-the-badge&logo=github) ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/nikkinikki-org/OpenWrt-nikki/total?style=for-the-badge&logo=github) ![GitHub Repo stars](https://img.shields.io/github/stars/nikkinikki-org/OpenWrt-nikki?style=for-the-badge&logo=github) [![Telegram](https://img.shields.io/badge/Telegram-gray?style=for-the-badge&logo=telegram)](https://t.me/nikkinikki_org)

中文 | [English](README.md)

# Nikki

在 OpenWrt 上使用 Mihomo 进行透明代理。

> [!IMPORTANT]
> **QWRT A73 兼容构建（`qwrt-a73` 分支）**
>
> 此分支将 `kmod-dummy` 内核模块从强制软件包依赖改为按需能力。常规
> Redir-Host、IPv4 Fake-IP、TUN 和 TPROXY 配置无需安装 `kmod-dummy` 即可
> 运行。只有启用 IPv6 Fake-IP（例如 `dns.fake-ip-range6`）时，才需要
> dummy 网络接口的内核支持。Mihomo 本身仍然需要，预编译套件中已包含
> `mihomo-meta`。
>
> QWRT A73 的 IPK 与自解压 `.run` 安装包可从本 Fork 的
> [Releases](https://github.com/luodaoyi/OpenWrt-nikki/releases/latest) 下载。

## 环境要求

- OpenWrt >= 24.10
- Linux Kernel >= 5.13
- firewall4

## 功能

- 透明代理 (Redirect/TPROXY/TUN, IPv4 和/或 IPv6)
- 访问控制
- 配置文件混入
- 配置文件编辑器
- 定时重启

## 安装和更新

### A. 从软件源安装（推荐）

1. 添加源

```shell
# 只需运行一次
wget -O - https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash
```

2. 安装

```shell
# 你可以从 shell 执行命令安装或者从 LuCI 的`软件包`菜单安装
# for opkg
opkg install nikki
opkg install luci-app-nikki
opkg install luci-i18n-nikki-zh-cn
# for apk
apk add nikki
apk add luci-app-nikki
apk add luci-i18n-nikki-zh-cn
```

### B. 从发行版安装

```shell
wget -O - https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/install.sh | ash
```

## 卸载并重置

```shell
wget -O - https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/uninstall.sh | ash
```

## 如何使用

查看 [Wiki](https://github.com/nikkinikki-org/OpenWrt-nikki/wiki)

## 如何工作

1. 混入并更新配置文件。
2. 启动 Mihomo。
3. 设置定时重启。
4. 配置 IP 规则/路由。
5. 生成防火墙配置并应用。

注意上述步骤可能因配置而变动。

## 编译

```shell
# 添加源
echo "src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main" >> "feeds.conf.default"
# 更新并安装源
./scripts/feeds update -a
./scripts/feeds install -a
# 编译
make package/luci-app-nikki/compile
```

编译结果可以在`bin/packages/your_architecture/nikki`内找到。

## 依赖

- ca-bundle
- curl
- yq
- firewall4
- ip-full
- kmod-inet-diag
- kmod-nft-socket
- kmod-nft-tproxy
- kmod-tun
- kmod-dummy（可选；仅 IPv6 Fake-IP 的 dummy 接口路径需要）

## 贡献者

[![贡献者](https://contrib.rocks/image?repo=nikkinikki-org/OpenWrt-nikki)](https://github.com/nikkinikki-org/OpenWrt-nikki/graphs/contributors)

## 特别感谢

- [@ApoisL](https://github.com/apoiston)
- [@xishang0128](https://github.com/xishang0128)
