# Dante SOCKS5 Proxy (Docker)

基于 `debian:trixie-slim` 从源码编译 [Dante](https://www.inet.no/dante/) SOCKS5 服务端的 Docker 镜像。

- 多阶段构建：编译工具只在构建阶段使用，运行镜像里只有 `sockd` 和 `libpam0g`
- Dante 版本通过构建参数指定，源码包下载后会校验 SHA-256
- 默认启用用户名/密码认证，容器启动时根据环境变量创建登录用户

## 快速开始

```bash
git clone git@github.com:Showfom/dante.git
cd dante
cp .env.example .env    # 修改 PROXY_USER 和 PROXY_PASSWORD
docker compose up -d --build
```

测试：

```bash
curl -x socks5h://proxy_user:change-me@你的服务器IP:1080 https://ifconfig.me
```

## 文件说明

| 文件                   | 说明                                              |
| ---------------------- | ------------------------------------------------- |
| `Dockerfile`           | 多阶段构建，编译并打包 `sockd`                    |
| `docker-entrypoint.sh` | 启动时根据环境变量创建或更新代理用户              |
| `compose.yaml`         | Docker Compose 配置                               |
| `sockd.conf`           | 实际使用的配置，Compose 以只读方式挂载进容器      |
| `sockd.conf.example`   | Dante 官方示例配置（来自 Debian 包），带完整注释  |
| `.env.example`         | 环境变量模板                                      |

## 配置

### 环境变量

| 变量             | 说明                                         |
| ---------------- | -------------------------------------------- |
| `PROXY_USER`     | 代理用户名，容器启动时自动创建               |
| `PROXY_PASSWORD` | `PROXY_USER` 的密码，每次启动都会重新设置    |

两个变量有一个为空就不会创建用户。默认配置是 `socksmethod: username`，此时没人能用这个代理。

需要多个用户时，可以在运行中的容器里手动添加：

```bash
docker exec -it dante sh -c 'useradd -M -s /usr/sbin/nologin bob && passwd bob'
```

这样加的用户在容器重建后会丢失。要长期保留，请修改 `docker-entrypoint.sh`。

### 构建参数

| 参数             | 默认值             | 说明                                  |
| ---------------- | ------------------ | ------------------------------------- |
| `DANTE_VERSION`  | `1.4.4`            | 要编译的 Dante 版本                   |
| `DANTE_SHA256`   | 1.4.4 源码包的校验值 | `dante-<版本>.tar.gz` 的 SHA-256     |
| `DEBIAN_VERSION` | `trixie-slim`      | Debian 基础镜像标签                   |

升级 Dante 时先算出新源码包的校验值：

```bash
curl -fsSL https://www.inet.no/dante/files/dante-1.4.x.tar.gz | sha256sum
```

把 `DANTE_VERSION` 和 `DANTE_SHA256` 写进 `.env`，再执行 `docker compose build`。校验值对不上会直接构建失败。

不用 Compose 的话：

```bash
docker build \
  --build-arg DANTE_VERSION=1.4.4 \
  --build-arg DANTE_SHA256=1973c7732f1f9f0a4c0ccf2c1ce462c7c25060b25643ea90f9b98f53a813faec \
  -t dante:1.4.4 .

docker run -d --name dante --init -p 1080:1080 \
  -e PROXY_USER=proxy_user -e PROXY_PASSWORD=change-me \
  dante:1.4.4
```

### sockd.conf

Compose 把 `sockd.conf` 只读挂载到 `/etc/sockd.conf`，改完配置重启即可，不用重新构建：

```bash
docker compose restart
```

默认配置：

- 监听 `0.0.0.0:1080`，出口走 `eth0`
- 必须用户名/密码认证（`socksmethod: username`）
- 禁止访问容器自身的回环地址（`127.0.0.0/8`）
- 允许 TCP `connect` 和 UDP `udpassociate`

只允许特定 IP 连接时，修改 `client pass` 规则：

```
client pass {
    from: 203.0.113.0/24 to: 0.0.0.0/0
    log: error
}
```

更多写法参考 `sockd.conf.example` 和官方文档：<https://www.inet.no/dante/doc/1.4.x/config/server.html>

## 安全提示

- 不要在 `socksmethod: none` 的情况下把 1080 端口暴露到公网，开放代理很快会被扫到并滥用。
- SOCKS5 的用户名密码是明文传输的。请使用不和其他服务共用的强密码，并尽量用防火墙或 `client pass` 限制来源 IP。
- 配置里的 `user.privileged: root` 是必需的，Dante 要读取 `/etc/shadow` 来校验密码；转发流量时使用非特权用户 `sockd`。

## 日志

```bash
docker compose logs -f
```
