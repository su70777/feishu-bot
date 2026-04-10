# 飞书招生机器人 MVP

这个子项目实现两个核心能力：

1. 学生画像与风险预警（机器人收到消息后，将分析卡片私聊发给老师）
2. 名单模板复用群发（首次保存名单，后续只改内容直接重发）

## 快速运行

```powershell
cd E:\桌面\VS code\qixiwx\feishu_bot_mvp
python -m pip install -r requirements.txt
python -m uvicorn app:app --host 0.0.0.0 --port 8000
```

健康检查：

```text
http://127.0.0.1:8000/healthz
```

## 参数配置（接飞书真实环境时）

在当前目录创建 `.env` 文件，内容示例：

```env
FEISHU_APP_ID=cli_xxx
FEISHU_APP_SECRET=xxx
FEISHU_VERIFY_TOKEN=xxx
TEACHER_OPEN_ID=ou_xxx
```

不配置时默认 `mock_send=true`，接口可本地演示，不会真的发飞书消息。

## 主要接口

- `POST /feishu/events`：飞书事件入口
- `POST /notify/template/upsert`：创建或更新名单模板
- `POST /notify/send`：使用模板群发
- `GET /notify/templates`：查看模板
- `GET /notify/logs`：查看发送日志

## 演示请求

### 1) 保存名单模板

```json
POST /notify/template/upsert
{
  "template_name": "高三A组",
  "recipient_open_ids": ["ou_xxx1", "ou_xxx2"]
}
```

### 2) 按模板群发

```json
POST /notify/send
{
  "template_name": "高三A组",
  "content": "明晚19:30直播答疑，请提前10分钟入会。"
}
```
