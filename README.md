# 儿童 AI 角色语音电话 MVP

这是一个供内部验证使用的 Flutter Android + FastAPI 语音对话项目。孩子从预置或本地自建角色中选择一个进入通话页；Flutter 本地 VAD 自动检测说话和静音，通过 WebSocket 上传 PCM；后端依次调用 MiMo ASR、LangChain Agent 和 MiMo TTS，再把 PCM 音频流返回 App。

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
LLM_MODEL=mimo-v2.5-pro
LLM_BASE_URL=https://token-plan-cn.xiaomimimo.com/v1
LLM_API_KEY=
AGENT_TIMEOUT_SECONDS=30
```

同一个 MiMo Token 可以同时填写到 `MIMO_API_KEY` 和 `LLM_API_KEY`。当前实现使用 OpenAI 兼容协议，不需要 `https://token-plan-cn.xiaomimimo.com/anthropic`。

密钥只允许放在本机 `.env` 或部署平台的 Secret 存储中，不要写入 Flutter、角色 JSON 或提交到 Git。Flutter 的 `--dart-define` 只配置 `VOICE_SERVER_URL`，不传递任何供应商密钥。

## 启动后端

### Docker Compose

```bash
docker compose up --build
```

Compose 使用宿主机 `.env` 中的 `MIMO_API_KEY` 和 `LLM_API_KEY` 创建 Docker Secrets，并分别挂载为：

```text
/run/secrets/mimo_api_key
/run/secrets/llm_api_key
```

容器环境只有 `MIMO_API_KEY_FILE` 和 `LLM_API_KEY_FILE` 两个文件路径，不包含密钥值；`.env` 不会作为 `env_file` 注入容器，也不会复制进镜像。其余模型、接口和日志配置以普通环境变量传入。

### 本机 Python

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r server/requirements.txt
cd server
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

本机 Python 不经过 Docker，Pydantic Settings 直接读取项目根目录的 `.env`。服务端同时支持 `MIMO_API_KEY_FILE` 和 `LLM_API_KEY_FILE`；直接密钥存在时优先使用直接值，否则读取对应文件。

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

### 新建自定义角色

角色列表末尾的“新建角色”入口可创建仅保存在当前设备上的角色。自建角色显示“我的角色”标记，并可从卡片菜单编辑或删除；预置角色不可编辑或删除。通话前临时切换音色只影响当次通话，返回列表后恢复角色保存的默认音色。

应用使用 Android App 私有存储保存版本化角色元数据、相册头像副本和克隆参考音频副本，不依赖稳定的 Android 绝对路径。应用不提供账号、云同步、分享或云备份功能。删除自建角色时，会先提交元数据变更，再尽力删除该角色的本地头像和参考音频；卸载或清除应用数据也会移除这些本地内容。

字段和素材限制：

- 名称 1–20 字；副标题 0–30 字；开场白 1–120 字；补充描述 0–200 字。
- 必选一个身份和 1–3 个不重复性格；可选 0–3 个不重复兴趣。
- 相册头像会在本机修正方向、居中裁成正方形，最长边不超过 1024 像素，编码后不超过 2 MB。头像不会上传到服务端。
- 音色设计描述为 8–500 字。
- 音色克隆支持麦克风录制或选择非空 WAV/MP3；录音为 24 kHz 单声道 WAV，时长 5–60 秒，参考文件不超过 7.5 MB，并要求用户明确确认拥有声音使用授权。录音与导入文件保存在 App 私有目录，通话时会上传为临时引用，服务端不持久化角色资料，并在会话结束时清理引用。

创建和编辑可离线使用随包或缓存选项。服务端通过以下接口发布权威选项目录，响应只包含 ID 和展示标签，不包含服务端 Prompt 文本：

```http
GET /api/character-options
```

自建角色通话使用结构化、受限的 `session.start` 快照，例如：

```json
{
  "type": "session.start",
  "characterId": "custom_20a8d1b51412447a99abc336e306f25f",
  "customCharacter": {
    "displayName": "星星船长",
    "greeting": "你好呀，我是星星船长！",
    "identityId": "adventure_companion",
    "traitIds": ["brave", "patient"],
    "interestIds": ["space", "science"],
    "description": "喜欢用有趣的小实验解释问题"
  },
  "voiceConfig": {
    "mode": "preset",
    "voice": "白桦"
  }
}
```

客户端不会发送完整系统 Prompt、副标题、头像路径、本地音频路径或授权标记。服务端按权威目录校验快照，仅为当前会话构造角色配置，不写数据库、不加入全局角色注册表；全局儿童安全规则和回复长度限制始终优先。

## 测试

后端：

```bash
cd server
python3 -m compileall -q app tests
python3 -m pytest -q
```

Flutter：

```bash
cd mobile
dart format --output=none --set-exit-if-changed lib test
flutter test
flutter analyze
flutter build apk --debug
```

磁盘受限且验收设备为 arm64 时，可生成仅包含 `arm64-v8a` 的 debug APK；未设置这些环境变量时，项目仍按默认多 ABI 构建：

```bash
cd mobile
env 'ORG_GRADLE_PROJECT_disable-abi-filtering=true' \
  ORG_GRADLE_PROJECT_arm64Only=true \
  flutter build apk --debug --target-platform android-arm64
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
