# Ubuntu 部署说明

目标域名：`lmf.hszk365.cn`

这套方案的目标是：
- 不再依赖临时 `trycloudflare` 隧道
- 用你自己的 Ubuntu 服务器长期运行
- 用固定域名 `https://lmf.hszk365.cn`
- 飞书事件回调、OAuth 回调都走这个固定地址

## 1. 服务器准备

建议 Ubuntu 22.04 或 24.04。

先确认：
- 你有一台公网 Ubuntu 服务器
- 域名 `lmf.hszk365.cn` 已解析到这台服务器公网 IP
- 服务器已开放 `80` 和 `443` 端口

## 2. 上传项目到服务器

建议把项目放到：

```bash
/opt/feishu-bot
```

需要上传这些内容：
- `app.py`
- `requirements.txt`
- `.env`
- `data/`
- `deploy/`

如果你在 Windows 本地，可以用 `scp` / `WinSCP` / `FinalShell` 上传。

## 3. 检查 `.env`

服务器上的 `.env` 至少要有：

```env
FEISHU_APP_ID=你的真实值
FEISHU_APP_SECRET=你的真实值
FEISHU_VERIFY_TOKEN=你的真实值
TEACHER_OPEN_ID=你的真实值
PUBLIC_BASE_URL=https://lmf.hszk365.cn
OAUTH_STATE_SECRET=你自己定义的一串随机字符串
```

如果你后面还要接 AI 自动回复，再补：

```env
AI_BASE_URL=
AI_API_KEY=
AI_MODEL=
```

## 4. 执行一键部署脚本

登录 Ubuntu 后执行：

```bash
cd /opt/feishu-bot
chmod +x deploy/bootstrap_ubuntu.sh
APP_DIR=/opt/feishu-bot APP_DOMAIN=lmf.hszk365.cn bash deploy/bootstrap_ubuntu.sh
```

这个脚本会自动完成：
- 安装 Python / nginx
- 创建虚拟环境
- 安装依赖
- 配置 systemd 服务
- 配置 nginx 反向代理

## 5. 检查服务状态

执行：

```bash
sudo systemctl status feishu-bot
curl http://127.0.0.1:8000/healthz
```

如果正常，应该能看到类似：

```json
{"ok":true,...}
```

## 6. 配置 HTTPS

安装证书工具：

```bash
sudo apt install -y certbot python3-certbot-nginx
```

申请证书：

```bash
sudo certbot --nginx -d lmf.hszk365.cn
```

成功后验证：

```bash
curl https://lmf.hszk365.cn/healthz
```

## 7. 飞书后台配置

### 事件与回调

飞书开放平台里把事件模式改成：
- `将事件发送至开发者服务器`

请求地址填：

```text
https://lmf.hszk365.cn/feishu/events
```

### 安全设置 / OAuth

至少配置：
- 重定向 URL：`https://lmf.hszk365.cn/auth/feishu/callback`
- 可信域名：`lmf.hszk365.cn`

如果页面里还有这些，也一起填：
- H5 可信域名：`lmf.hszk365.cn`
- JSAPI 安全域名：`lmf.hszk365.cn`

## 8. 验证 OAuth

浏览器打开：

```text
https://lmf.hszk365.cn/auth/feishu/status
```

再打开：

```text
https://lmf.hszk365.cn/auth/feishu/login
```

老师本人完成授权后，再访问：

```text
https://lmf.hszk365.cn/auth/feishu/status
```

如果返回里有：

```text
authorized: true
```

说明 OAuth 已经通了。

## 9. 常用运维命令

```bash
sudo systemctl restart feishu-bot
sudo systemctl status feishu-bot
sudo journalctl -u feishu-bot -n 100 --no-pager
sudo nginx -t
sudo systemctl reload nginx
```

## 10. 出问题先查哪里

如果飞书不回复，优先检查这 4 个点：

1. 服务是否活着

```bash
curl http://127.0.0.1:8000/healthz
```

2. 域名是否通

```bash
curl https://lmf.hszk365.cn/healthz
```

3. systemd 日志

```bash
sudo journalctl -u feishu-bot -n 100 --no-pager
```

4. 飞书后台事件地址是否还是：

```text
https://lmf.hszk365.cn/feishu/events
```

这样部署完成后，你就不需要再反复改临时隧道地址了。
