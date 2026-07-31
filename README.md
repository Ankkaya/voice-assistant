# 儿童 AI 角色语音电话 MVP

这是一个供内部验证使用的 Flutter Android + FastAPI 语音对话项目。孩子从两个角色中选择一个进入通话页；Flutter 本地 VAD 自动检测说话和静音，通过 WebSocket 上传 PCM；后端依次调用 MiMo ASR、LangChain Agent 和 MiMo TTS，再把 PCM 音频流返回 App。

> “莱德”仅用于内部原型验证。仓库不包含受保护角色形象或演员克隆音色，默认使用中性 “R” 头像和 MiMo 预置音色。

## 项目结构

```text
mobile/   Flutter Android App
server/   FastAPI WebSocket 服务
docs/     设计规格与实施计划
```

## 前置条件

- Flutter 3.44 或更高（Dart 3.12 或更高）
- Android Studio/Android SDK 和一台 Android 真机
- Docker Compose；或者 Python 3.11+
- MiMo API Key
- 一个由 LangChain `ChatOpenAI` 可连接的 OpenAI 兼容模型接口

## 配置后端

```bash
cp .env.example .env
```

编辑 `.env`：

```env
# 在等号后填入 MiMo Key
MIMO_API_KEY=
MIMO_BASE_URL=https://token-plan-cn.xiaomimimo.com/v1

LLM_PROVIDER=openai_compatible
# 当前 MVP 的 LangChain Agent 也使用 MiMo OpenAI 兼容接口
LLM_MODEL=mimo-v2.5
LLM_BASE_URL=https://token-plan-cn.xiaomimimo.com/v1
LLM_API_KEY=
```

同一个 MiMo Token 可以同时填写到 `MIMO_API_KEY` 和 `LLM_API_KEY`。当前实现使用 OpenAI 兼容协议，不需要 `https://token-plan-cn.xiaomimimo.com/anthropic`。

密钥只允许放在 `.env`，不要写入 Flutter、角色 JSON 或提交到 Git。

## 启动后端

### Docker Compose

```bash
docker compose up --build
```

### 本机 Python

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r server/requirements.txt
cd server
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

检查服务：

```bash
curl http://127.0.0.1:8000/health
curl -i http://127.0.0.1:8000/ready
```

`/health` 表示进程存活；只有 MiMo 与 LLM 配置齐全时，`/ready` 才返回 200。接口不会返回任何密钥内容。

## 运行 Android App

手机和电脑连接同一个局域网。先查询电脑局域网 IP，例如：

```bash
ip route get 1.1.1.1
```

然后运行：

```bash
cd mobile
flutter pub get
flutter run --dart-define=VOICE_SERVER_URL=ws://192.168.1.10:8000/ws/voice
```

将 `192.168.1.10` 替换成电脑地址。Android Debug 构建允许局域网明文 `ws://`；未来公网部署必须使用 TLS 和 `wss://`。

首次进入通话页时允许麦克风权限。AI 说话期间麦克风关闭；AI 播放结束后，本地 VAD 自动开始聆听。孩子无需按住或点击说话按钮。

## 角色配置

Flutter 显示配置：

```text
mobile/assets/characters.json
```

服务端 Prompt 与音色配置：

```text
server/app/config/characters.json
```

默认音色：

- 拉布拉多队长：`白桦`
- 莱德：`苏打`

预置音色配置：

```json
{
  "mode": "preset",
  "model": "mimo-v2.5-tts",
  "voice": "白桦"
}
```

Voice Design 配置：

```json
{
  "mode": "voice_design",
  "model": "mimo-v2.5-tts-voicedesign",
  "voiceDescription": "温暖活泼的年轻男声，普通话清晰，语速适中"
}
```

Voice Clone 配置：

```json
{
  "mode": "voice_clone",
  "model": "mimo-v2.5-tts-voiceclone",
  "referenceAudioPath": "voices/authorized.wav"
}
```

参考音频路径相对于 `server/app/config/`。只允许使用获得明确授权的 MP3/WAV，严禁克隆演员或其他未经授权的声音。Voice Design 和 Voice Clone 当前不是低延迟真流式，首音频会比预置音色慢。

## 测试

后端：

```bash
cd server
pytest -q
```

Flutter：

```bash
cd mobile
flutter test
flutter analyze
flutter build apk --debug
```

真实供应商烟测：

```bash
cd server
PYTHONPATH=. python scripts/smoke_providers.py
```

烟测先使用 MiMo 预置 TTS 生成一小段无隐私语音，再调用 MiMo ASR 和 LangChain Agent。输出只包含字节数和字符数，不打印识别文本或模型回答。

## 通话协议

- JSON 文本帧：会话、状态、错误、心跳事件
- App → 服务端二进制帧：16kHz、单声道、PCM16LE
- 服务端 → App 二进制帧：24kHz、单声道、PCM16LE
- VAD：200ms 预录、300ms 最短语音、800ms 结束静音、15 秒单轮上限
- 单次通话上限：10 分钟

完整协议和安全边界见 [设计规格](docs/superpowers/specs/2026-07-30-child-voice-call-mvp-design.md)。

## 当前 MVP 边界

- Android 真机优先；未验收 iOS。
- 半双工，不支持孩子在 AI 播放时自动插话。
- MiMo ASR 接收一轮完整 WAV，因此识别从本地 VAD 提交后开始。
- 无账号、数据库、历史记录或长期记忆。
- 断线后重新拨打，不恢复旧会话。
- 内部安全规则不是公开儿童产品所需的完整审核与合规系统。
