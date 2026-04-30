# Ubuntu 部署说明

目标：继续使用现有域名 `lmf.hszk365.cn`，只给飞书机器人新增 `/feishu-bot/` 路径，不影响这个域名下已有的其他项目。

最终地址：

```text
事件订阅地址：https://lmf.hszk365.cn/feishu-bot/feishu/events
OAuth 回调地址：https://lmf.hszk365.cn/feishu-bot/auth/feishu/callback
可信域名：lmf.hszk365.cn
```

机器人服务默认只监听服务器本机端口 `18080`，Nginx 再把 `/feishu-bot/` 转发过去。

## 1. 上传项目

建议放到：

```bash
/opt/feishu-bot
```

至少上传：

```text
app.py
requirements.txt
.env
data/
deploy/
```

## 2. 检查 .env

服务器上的 `.env` 至少要有：

```env
FEISHU_APP_ID=你的真实值
FEISHU_APP_SECRET=你的真实值
FEISHU_VERIFY_TOKEN=你的真实值
TEACHER_OPEN_ID=你的真实值
PUBLIC_BASE_URL=https://lmf.hszk365.cn/feishu-bot
OAUTH_STATE_SECRET=你自己定义的一串随机字符串
```

## 3. 部署机器人服务

```bash
cd /opt/feishu-bot
chmod +x deploy/bootstrap_ubuntu.sh

APP_DIR=/opt/feishu-bot \
APP_DOMAIN=lmf.hszk365.cn \
APP_PATH=/feishu-bot \
APP_PORT=18080 \
SERVICE_NAME=feishu-bot \
bash deploy/bootstrap_ubuntu.sh
```

这个脚本会：

- 安装 Python / nginx 依赖
- 创建虚拟环境并安装 Python 包
- 更新 `.env` 里的 `PUBLIC_BASE_URL`
- 创建并启动 `feishu-bot` systemd 服务
- 写入 Nginx location 片段到 `/etc/nginx/snippets/feishu-bot-locations.conf`

注意：脚本不会覆盖现有 `lmf.hszk365.cn` 站点，也不会删除别人的 Nginx 配置。

## 4. 加入 Nginx 路径转发

找到服务器上现有的 `lmf.hszk365.cn` Nginx 配置：

```bash
sudo nginx -T | grep -n "server_name lmf.hszk365.cn" -A30 -B5
```

在这个域名对应的 `server { ... }` 里面加入一行。飞书走 HTTPS，所以如果有多个 `server` 块，至少要加到 `listen 443 ssl` 的 `lmf.hszk365.cn` 配置里；如果你也希望 HTTP 路径可访问，可以 80 和 443 两处都加。

```nginx
include /etc/nginx/snippets/feishu-bot-locations.conf;
```

然后检查并重载：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

如果你想手动粘贴 location，也可以参考仓库里的：

```text
deploy/nginx.lmf.hszk365.cn.conf
```

## 5. 验证

先测本机服务：

```bash
curl http://127.0.0.1:18080/healthz
```

再测公网路径：

```bash
curl https://lmf.hszk365.cn/feishu-bot/healthz
```

正常应返回类似：

```json
{"ok":true,"mock_send":false,"alert_level":"中"}
```

## 6. 飞书后台配置

飞书开放平台里改成：

```text
事件订阅地址：
https://lmf.hszk365.cn/feishu-bot/feishu/events

OAuth 回调地址：
https://lmf.hszk365.cn/feishu-bot/auth/feishu/callback

可信域名：
lmf.hszk365.cn
```

如果页面里还有 H5 可信域名、JSAPI 安全域名，也填：

```text
lmf.hszk365.cn
```

## 7. 常用排查命令

```bash
sudo systemctl status feishu-bot
sudo journalctl -u feishu-bot -n 100 --no-pager
curl http://127.0.0.1:18080/healthz
curl https://lmf.hszk365.cn/feishu-bot/healthz
sudo nginx -t
```
