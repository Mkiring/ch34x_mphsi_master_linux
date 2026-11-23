# DKMS deb 自动构建

本仓库的 `main` 分支在 `driver/` 上游源码之外，增加 Debian 打包、验证和发布配置；**没有修改上游驱动源码**。上游记录见 [`UPSTREAM_COMMIT`](UPSTREAM_COMMIT)。

## 自动更新流程

1. [Sync upstream](.github/workflows/sync-upstream.yml) 每天 UTC 01:17（北京时间 09:17）检查上游 `main`，有变化时更新驱动源码和 `UPSTREAM_COMMIT`，并提交到本仓库 `main`。可在 Actions 中手动触发。
2. [Build and publish DKMS deb](.github/workflows/build-deb.yml) 在每次 push 后，从上游仓库独立获取 `UPSTREAM_COMMIT` 指定的版本；也支持手动指定 branch、tag 或 commit。
3. CI 构建 deb，使用 DKMS 针对 CI 运行中的内核**实际编译**，并运行 `lintian`，然后发布到本仓库 Releases。`SHA256SUMS` 同时发布，下载后可以校验。
4. 包版本形如 `1.7+git20261012.57be7ed01e2a`（上游驱动版本 + 上游提交日期 + 提交短哈希）。已发布版本不会覆盖。

同步 workflow 的提交会触发构建 workflow，无需 Personal Access Token。两个 workflow 都需要 `contents: write`，其中构建只有发布 job 使用写权限。

Workflow 默认写权限已设置为允许；仍需在 fork 的 Actions 页面启用 workflow。公开 fork 的定时任务可能因长期无活动被 GitHub 暂停，需要时在 Actions 页面重新启用。

## 安装

在 Ubuntu/Debian 上运行（首次会请求 sudo 密码）：

```sh
curl -fsSL https://raw.githubusercontent.com/Mkiring/ch34x_mphsi_master_linux/main/scripts/install-latest.sh | bash
```

或先下载最新 Release 中的 deb 和 `SHA256SUMS`，再执行：

```sh
sha256sum -c --ignore-missing SHA256SUMS
curl -fsSLO https://raw.githubusercontent.com/Mkiring/ch34x_mphsi_master_linux/main/scripts/install-deb.sh
bash install-deb.sh ./ch34x-mphsi-master-dkms_*_all.deb
```

安装脚本会：
- 用 APT 安装 DKMS、gcc、make、kmod 以及推荐的内核 headers；
- 如果检测到本仓库此前手动添加的 `ch34x_mphsi_master/V1.7`，先移除该 DKMS 注册项，再安装 deb；已加载模块不会被强制卸载；
- 安装结束后执行 `modprobe`，并显示 DKMS 状态。没有插入支持的 USB 设备时，模块也可能因 `modprobe` 的按需加载规则而不常驻，这是正常的。

也可以不下载安装脚本：

```sh
sudo apt update
sudo apt install ./ch34x-mphsi-master-dkms_*_all.deb
sudo modprobe ch34x_mphsi_master
```

但此方式**不会**自动迁移旧的手动 `V1.7` DKMS 注册项；如果存在，请先运行 `sudo dkms remove -m ch34x_mphsi_master -v V1.7 --all`。

### 定时自动安装

下面是系统级 timer，每天北京时间 10:17 检查并安装最新 Release（比同步检查晚一小时）。它只有在 Release 版本变化时才会升级。

先保存安装脚本，再创建服务与 timer（需要 root）：

```sh
sudo install -Dm755 scripts/install-latest.sh /usr/local/sbin/ch34x-update
sudo install -Dm644 packaging/ch34x-update.service /etc/systemd/system/ch34x-update.service
sudo install -Dm644 packaging/ch34x-update.timer /etc/systemd/system/ch34x-update.timer
sudo systemctl daemon-reload
sudo systemctl enable --now ch34x-update.timer
systemctl list-timers ch34x-update.timer
```

安装服务由 systemd 执行，不要在用户 `crontab` 中重复配置。查看日志：

```sh
journalctl -u ch34x-update.service
dkms status ch34x_mphsi_master
```

### 内核升级与 Secure Boot

- 这是**源码 DKMS 包**，`Architecture: all`；不是只适用于某一台机器内核的 `.ko` 二进制包。目标机器安装时需有匹配的内核 headers、编译器和构建工具。
- 安装或升级内核后，DKMS 会为新内核重新编译。CI 的内核编译验证不能替代目标硬件上的加载测试。
- 如果启用了 Secure Boot，需要配置 DKMS 的 MOK 签名并 enrollment，否则新模块可能被内核拒绝加载。`mokutil --sb-state` 可检查当前状态。

## 本地构建与验证

需要 `debhelper`、`dh-dkms`、`dpkg-dev`、`lintian`、构建工具和当前内核 headers：

```sh
sudo apt install build-essential debhelper dh-dkms dpkg-dev lintian linux-headers-$(uname -r)
scripts/build-deb.sh
scripts/verify-deb.sh build/ch34x-mphsi-master-dkms_*_all.deb
```

`build-deb.sh` 只打包 `driver/` 下的 Makefile、`.c`、`.h` 以及 `dkms.conf`，不会把本地 `.o`、`.ko`、`.cmd` 放入包中。输出在 `build/`。要从另一个上游 checkout 构建：

```sh
scripts/build-deb.sh --source-dir /path/to/upstream
```

`verify-deb.sh` 在临时目录中使用 DKMS add/build，不安装到 `/lib/modules`，不加载模块，也不改动当前系统的 DKMS 注册项。可以用 `KERNEL_VERSION=版本` 验证其他已安装 headers。

## 卸载

```sh
sudo apt remove ch34x-mphsi-master-dkms
```

包的 prerm 会移除对应版本的 DKMS 模块。若要立即停止使用，可先在确认没有程序占用 SPI/I2C/GPIO 后运行 `sudo modprobe -r ch34x_mphsi_master`。
