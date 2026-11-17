# 自建 MetaCubeXD 一体版镜像

上游：<https://github.com/MetaCubeX/metacubexd>

Fork：<https://github.com/GhoulOwl/metacubexd>

Docker Hub：`ghoulowl/metacubexd-server`

## GitHub 设置

在仓库的 Settings → Secrets and variables → Actions 中设置：

| 类型 | 名称 | 值 |
| --- | --- | --- |
| Variable | `DOCKERHUB_USERNAME` | `ghoulowl` |
| Variable | `DOCKERHUB_REPOSITORY` | `metacubexd-server` |
| Secret | `DOCKERHUB_TOKEN` | 具有目标 Docker Hub 仓库写入权限的 Access Token |

当前仓库将 Token 保存在名为 `DOCKERHUB_TOKEN` 的 GitHub Environment 中，发布任务已引用该环境。放在 Repository secrets 中也可读取；如果两处都配置，以 Environment secret 为准。

先在 Docker Hub 创建 `ghoulowl/metacubexd-server` 仓库。使用访问令牌，不填 Docker Hub 登录密码，也不要把令牌写进源码。

Actions → **Sync upstream and publish Docker Hub** → Run workflow：

- `publish=true`：同步、验证，并发布 `latest`、`sha-完整提交号`、`build-运行编号-尝试次数`。
- `publish=false`：不需要 Docker Hub Token，执行同步、构建和启动验证，不发布镜像。

每 6 小时的第 23 分钟自动检查上游 `main`；有自己的提交时正常 merge，有冲突则停止，不 reset、不强推。这个流程跟随上游开发分支，不只跟随 Release。

同步和构建在同一个工作流中执行，因此不依赖 `GITHUB_TOKEN` 推送触发另一个工作流。定时运行会检查提交标签是否存在，未成功发布的提交会重试；手动运行始终重建。`latest` 和提交标签可以被手动重建覆盖，回退请使用独立的 `build-*` 标签或镜像 digest。

使用上游 `apps/server/Dockerfile` 从源码构建，不是转存官方成品镜像。Mihomo 版本遵循该 Dockerfile 的默认值；上游没有更新内核版本时，不会自行追踪 Mihomo 最新版。

发布前会验证 amd64 容器的网页、管理 API 的鉴权、内核 API 和代理监听端口；随后构建并发布 `linux/amd64` 和 `linux/arm64` 镜像。arm64 构建包含内核版本执行检查，完整启动测试目前只在 amd64 执行。

Fork 中上游自带的发布、桌面端和测试工作流在 GitHub 设置中禁用，保留文件以减少同步冲突。仓库长时间没有活动时，GitHub 可能停用定时工作流；需要在 Actions 中重新启用。

## 在目标机器部署

以下示例适用于已安装 Docker Engine 和 Compose v2 的 Linux 主机。先完成第一次镜像发布。

```bash
git clone https://github.com/GhoulOwl/metacubexd.git
sudo mkdir -p /opt/metacubexd
sudo cp -a metacubexd/docker/deploy/. /opt/metacubexd/
cd /opt/metacubexd
sudo cp .env.example .env
sudo chmod 600 .env
```

编辑 `.env`，分别用 `openssl rand -hex 32` 生成两个不同的 Token，填写 `CONTROL_TOKEN` 和 `CLASH_SECRET`。本机使用可保留 `BIND_ADDRESS=127.0.0.1`；局域网使用填写服务器的局域网 IP。网页是上游的管理界面，访问控制依赖受信任网络或额外的反向代理认证。

```bash
sudo ./update.sh
```

打开 `http://绑定的IP:8080` 导入自己的节点订阅。7890 是 HTTP/SOCKS 混合代理端口，9090 是 Mihomo API。订阅、配置和缓存保存在命名卷 `metacubexd-data` 中；不要运行 `docker compose down -v`。

这个配置提供端口代理，不会自动接管整机或整个局域网流量。TUN、旁路由需要根据目标机器另行配置。

## 自动更新容器（Linux/systemd，可选）

部署成功后，在目标机器启用：

```bash
sudo cp metacubexd-update.service metacubexd-update.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now metacubexd-update.timer
systemctl list-timers metacubexd-update.timer
```

每 15 分钟检查镜像；拉取失败时不替换容器，有新镜像才重建。更新可能短暂中断连接；脚本等待容器健康，但不自动回滚配置和镜像。查看日志：

```bash
journalctl -u metacubexd-update.service -n 100 --no-pager
```

手动回退：先停止定时器，将 `.env` 中的 `IMAGE_TAG` 改成以前成功构建的 `build-*` 标签，再运行 `sudo ./update.sh`。新版本可能改变持久化配置，因此升级前应备份数据卷。
