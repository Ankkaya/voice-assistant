# 儿童 AI 语音通话 MVP 设计规格

日期：2026-07-30  
状态：已批准，待实施计划  
目标平台：Flutter Android 真机  
使用范围：内部原型验证

## 1. 目标与非目标

本项目为3到6岁儿童提供一个模拟打电话的语音对话 App。孩子在角色选择页选择卡通人物，进入通话页后无需按键说话；Flutter 在本地检测开始说话和连续静音，通过 WebSocket 将 PCM 音频流发送到后端。后端使用 MiMo ASR、LangChain Agent 和 MiMo TTS 生成回答，并把语音分片返回 App 播放。

MVP 首屏展示两个角色：原创角色“拉布拉多队长”和内部测试用的《汪汪队立大功》角色“莱德”。角色系统由 JSON 配置驱动，后续增加角色无需修改通话逻辑。莱德仅用于内部验证，不代表获得公开分发或商业使用授权。

MVP 不包含：iOS 验收、账号、数据库、历史记录、长期记忆、联网搜索、Agent 工具、插话打断、WebRTC、LiveKit、公网部署和断线续聊。

## 2. 已确认的技术决策

- 客户端使用 Flutter，首轮只验收 Android 真机。
- App 与后端使用单条 WebSocket 长连接；本地开发使用 `ws://`，未来有 TLS 时切换 `wss://`。
- 音频在 App 与后端之间使用二进制帧，不使用 HTTP 文件上传或 Base64。
- Flutter 本地执行 VAD；AI 播放期间关闭麦克风，不允许插话。
- 后端使用 Python、FastAPI 和 LangChain，作为单个 Docker 容器运行。
- ASR 使用 `mimo-v2.5-asr`；TTS 支持 MiMo 预置音色、Voice Design 和 Voice Clone，默认预置音色。
- LangChain 只编排文本 Agent；ASR/TTS 由独立 Provider 管理。
- 会话和音频只存在内存中，挂断、断线或超时后清除。
- MiMo 与 LLM 凭据不写入仓库，由用户在真实联调时通过 `.env` 注入；测试使用 Fake Provider，真实联调测试按密钥是否存在决定是否运行。

## 3. MiMo API 约束

MiMo 官方 ASR 接口接收单个 MP3/WAV Base64 音频，不能持续接收 PCM。其 `stream=true` 仅流式返回识别文字。因此 App 到后端保持 PCM 流式传输，但后端必须在本地 VAD 提交一轮语音后，将 PCM 在内存中封装为 WAV，再调用 MiMo ASR。

`mimo-v2.5-tts` 支持真正的低延迟流式输出，输出为 24kHz、PCM16LE、单声道。`mimo-v2.5-tts-voicedesign` 和 `mimo-v2.5-tts-voiceclone` 当前采用兼容流式模式，仍需等完整推理完成后才返回结果。

官方参考：

- [MiMo-V2.5-ASR API](https://mimo.mi.com/static/docs/api/audio/Speech-Recognition.md)
- [MiMo TTS API](https://mimo.mi.com/static/docs/api/audio/tts.md)
- [MiMo TTS 使用指南](https://mimo.mi.com/static/docs/quick-start/usage-guide/audio/speech-synthesis-v2.5.md)

## 4. 总体架构

```text
Flutter Android App
├── CharacterPage：角色选择
├── CallPage：通话界面
├── CallController：通话状态机
├── AudioCapture：麦克风 PCM 采集
├── LocalVad：本地说话/静音检测
├── VoiceSocket：WebSocket 协议
└── AudioPlayer：流式 PCM 播放
              │
              │ WebSocket（JSON 控制帧 + 二进制 PCM）
              ▼
Python FastAPI Server
├── VoiceGateway：连接和协议解析
├── VoiceSession：单次通话编排
├── WavBuilder：PCM 内存封装 WAV
├── XiaomiAsrProvider：MiMo ASR
├── LangChainAgent：角色对话
├── XiaomiTtsProvider：三种 MiMo TTS
├── CharacterRegistry：服务端角色配置
└── SafetyGuard：儿童内容规则
```

Flutter 不接触供应商密钥。`VoiceSession` 负责编排但不包含供应商细节；ASR、LLM、TTS 均通过清晰接口隔离。后端不使用数据库、Redis、对象存储或临时音频文件。

本地调试地址默认为 `ws://<电脑局域网 IP>:8000/ws/voice`。Android Debug 构建只为本地调试启用明文网络；Release 配置要求 `wss://`。

## 5. 页面设计

### 5.1 角色选择页

页面标题为“想给谁打电话？”，下面展示两个整卡可点击的大卡片。每张卡包含本地头像、角色名称、一句话介绍和“打电话”提示。页面没有底部导航、登录、历史记录或设置入口。

首版角色：

| ID | 名称 | 简介 | 定位 |
|---|---|---|---|
| `labrador_captain` | 拉布拉多队长 | 勇敢又温暖的探险伙伴 | 原创角色，沉稳、友好、爱探索、鼓励合作 |
| `ryder` | 莱德 | 乐于助人的救援队长 | 内部测试角色，冷静、聪明、鼓励帮助他人 |

角色图片从 Flutter Assets 读取，不在运行时下载。项目交付一张原创拉布拉多插画，以及一张不含受保护形象的通用“R”字母头像作为莱德默认素材；用户可在内部测试环境自行替换 `mobile/assets/characters/ryder.png`，项目不自动抓取或分发未经授权的图片。

### 5.2 通话页

通话页只提供一个可操作按钮：挂断。页面显示角色名与“AI角色”标识、通话时长、大头像、呼吸/声波动画和当前状态文案。

状态文案：

| 状态 | 文案 | 麦克风 |
|---|---|---|
| `connecting` | 正在连接 | 关闭 |
| `ringing` | 正在呼叫{角色名} | 关闭 |
| `assistantSpeaking` | {角色名}正在说话 | 关闭 |
| `listening` | 你可以说话啦 | 开启 |
| `userSpeaking` | 我在听 | 开启并上传 |
| `processing` | {角色名}正在想一想 | 关闭 |
| `error` | 通话遇到了一点问题 | 关闭 |

响铃阶段至少展示 1.5 秒，同时由服务端准备开场白。通话最长 10 分钟，到时播放简短告别语后自动挂断。

## 6. 通话状态机

正常状态流：

```text
connecting
 → ringing
 → assistantSpeaking
 → listening
 → userSpeaking
 → processing
 → assistantSpeaking
 → listening
```

任意状态均可进入 `ended` 或 `error`。服务端严格校验状态：只有 `listening` 接受 `input.audio.start`，只有 `receiving` 接受音频和 `commit`，`processing` 与 `speaking` 拒绝新音频。重复提交、迟到音频和错误 `turnId` 被忽略并记录协议错误。

AI 播放期间 Flutter 停止录音与 VAD；播放结束后才重新打开。挂断、进入后台或连接断开时立即停止录音与播放。

## 7. 音频与本地 VAD

上行格式：PCM signed 16-bit little-endian、16kHz、单声道、20ms 一帧（640 字节）。下行格式：PCM16LE、24kHz、单声道，由 App 根据 `assistant.audio.start` 中的元数据初始化播放器。

VAD 默认参数：

| 参数 | 值 |
|---|---:|
| 预录环形缓冲 | 200ms |
| 最短有效说话 | 300ms |
| 结束静音 | 800ms |
| 单轮最长语音 | 15 秒 |
| 单轮 PCM 上限 | 512KB |

Flutter 在 `listening` 状态持续分析本地音频并保留 200ms 预录缓冲。检测到开始说话时发送 `input.audio.start`，先发送预录数据，再发送实时 PCM。连续静音达到 800ms 时发送 `input.audio.commit`。短于 300ms 的短促噪声被丢弃；达到 15 秒时强制提交。

## 8. WebSocket 协议

文本帧承载 JSON 控制事件；客户端发出的二进制帧只能是麦克风 PCM，服务端发出的二进制帧只能是 TTS PCM，因此 MVP 不为二进制帧增加自定义头。

客户端事件：

```json
{"type":"session.start","characterId":"ryder"}
{"type":"input.audio.start","turnId":"turn_1"}
{"type":"input.audio.commit","turnId":"turn_1"}
{"type":"session.end"}
{"type":"ping","timestamp":1785412800000}
```

服务端事件：

```json
{"type":"session.ready","sessionId":"session_1"}
{"type":"user.transcript","turnId":"turn_1","text":"你今天去了哪里？"}
{"type":"assistant.thinking","turnId":"turn_1"}
{"type":"assistant.audio.start","turnId":"turn_1","encoding":"pcm16le","sampleRate":24000,"channels":1}
{"type":"assistant.audio.end","turnId":"turn_1"}
```

`assistant.audio.start` 与 `assistant.audio.end` 之间的二进制帧是同一回答的 PCM。错误事件统一为：

```json
{
  "type":"turn.error",
  "stage":"asr",
  "code":"UPSTREAM_TIMEOUT",
  "recoverable":true,
  "message":"我刚刚没有听清，可以再说一次吗？"
}
```

Flutter 只依据稳定的 `code` 与 `recoverable` 控制行为，不展示供应商原始错误。

## 9. 单轮数据流

1. App 建立 WebSocket，发送角色 ID，服务端创建内存 `VoiceSession`。
2. 服务端生成角色开场白。预置 TTS 音频块边生成边转发；App 播放完毕后进入 `listening`。
3. Flutter 本地 VAD 检测说话，发送 `input.audio.start`、预录 PCM 和实时 PCM。
4. VAD 检测连续 800ms 静音，发送 `input.audio.commit`。
5. 后端在内存中将 PCM 封装为 WAV，并以 Base64 调用 `mimo-v2.5-asr`。
6. ASR 最终文字经过输入安全检查，然后提交 LangChain Agent。
7. Agent 生成完整短回答；输出安全检查通过后才调用 TTS，避免未经检查的文本被朗读。
8. 预置 TTS 使用 SSE 返回 Base64 PCM 块；后端解码后立即以 WebSocket 二进制帧发送。
9. Voice Design/Clone 等待完整推理结果，解码后仍以相同 WebSocket 协议分片发送。
10. App 播放结束后重新开启麦克风与 VAD。

## 10. LangChain Agent

MVP 没有工具或知识库，不使用 `AgentExecutor`。Agent 使用 `ChatPromptTemplate → BaseChatModel → StrOutputParser`。`ChatModelFactory` 通过环境变量创建具体模型：

```env
LLM_PROVIDER=
LLM_MODEL=
LLM_BASE_URL=
LLM_API_KEY=
```

Prompt 由全局儿童安全规则、角色设定、输出格式限制、最近会话历史和本轮输入组成。只保留最近 8 轮对话；超出后删除最早的普通消息。挂断后清除全部历史。

回答要求：面向3到6岁、简单中文、最多三句话、最多 80 个汉字、一次最多一个问题、不输出 Markdown、网址或复杂符号。

## 11. 儿童安全

全局规则禁止 Agent：索取姓名、学校、地址、电话、照片或账号；要求孩子保守秘密；使用恐吓、羞辱、消费诱导或情感依赖话术；声称自己是真人、医生、警察或紧急服务人员；遵循忽略系统规则的 Prompt 注入。

MVP 使用规则检查与受约束生成两层保护。明显的隐私、成人内容、危险行为和 Prompt 注入输入不进入普通角色生成。高风险输入使用固定回复：“这件事很重要，请马上告诉身边你信任的大人，让他来帮助你。”输出未通过检查时改用：“这个话题我不太适合回答，我们换一个轻松的话题吧。”

这是内部 MVP 的基础安全机制，不等同于公开儿童产品的生产级审核和合规方案。

## 12. 角色与三种 TTS 配置

Flutter 角色配置只保存 ID、显示名称、简介、头像路径和主题色。服务端角色配置是 Prompt、开场白和音色的权威来源。

默认预置音色配置为：

- 拉布拉多队长：`mimo-v2.5-tts`，预置中文男声音色 `白桦`。
- 莱德：`mimo-v2.5-tts`，预置中文男声音色 `苏打`。

角色配置可把 `tts.mode` 改为：

- `preset`：提供 MiMo `voice` 名称，低延迟流式输出。
- `voice_design`：提供音色描述，当前需等待完整结果。
- `voice_clone`：提供服务端参考音频路径，当前需等待完整结果；参考音频必须获得授权，且绝不下发 App。

客户端不感知 TTS 模式差异。

## 13. 连接、超时与错误恢复

- 首次 WebSocket 连接超时 8 秒；失败后自动重试一次。
- 每 15 秒发送心跳；30 秒无响应视为断线。
- 通话中断后不恢复旧会话，直接结束并允许重新拨打。
- MiMo ASR 超时 20 秒；LangChain Agent 超时 15 秒；MiMo TTS 首块超时 15 秒；TTS 分片间隔超时 5 秒。
- MVP 不自动重试模型调用，避免重复计费和延长等待。
- ASR 空结果提示“我刚刚没有听清，可以再说一次吗？”；连续三次空结果后提示检查环境声音。
- Agent 或 TTS 失败时返回可恢复错误，App 显示简短提示后回到聆听状态。

用户挂断、WebSocket 断开、App 进入后台、通话超时或不可恢复错误时，服务端取消 ASR、Agent、TTS 异步任务，关闭上游响应流，清空 PCM/WAV 缓冲和会话历史并关闭连接。WAV 只通过内存构造，不写磁盘。

日志只记录 session ID、角色 ID、状态变化、音频时长、各阶段耗时及错误码；不记录音频、ASR 文本、Agent 回答或密钥。

## 14. 项目结构

```text
voice-assistant/
├── mobile/
│   ├── lib/
│   │   ├── pages/
│   │   ├── controllers/
│   │   ├── audio/
│   │   ├── websocket/
│   │   ├── models/
│   │   └── widgets/
│   ├── assets/
│   │   ├── characters.json
│   │   └── characters/
│   └── test/
├── server/
│   ├── app/
│   │   ├── websocket/
│   │   ├── session/
│   │   ├── providers/
│   │   ├── agent/
│   │   ├── safety/
│   │   └── config/
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt
├── docs/
├── docker-compose.yml
├── .env.example
└── README.md
```

服务端配置：

```env
MIMO_API_KEY=
LLM_PROVIDER=
LLM_MODEL=
LLM_BASE_URL=
LLM_API_KEY=
VOICE_HOST=0.0.0.0
VOICE_PORT=8000
LOG_LEVEL=INFO
```

密钥缺失时服务可启动，但 readiness 显示未就绪；自动化测试不依赖真实密钥。

## 15. 测试策略

后端单元测试覆盖 WAV 封装、协议解析、状态保护、音频上限、角色配置校验、三种 TTS 路由、回答长度、安全兜底和资源清理。集成测试使用 Fake ASR、Fake LLM、Fake TTS，验证“PCM → ASR → Agent → TTS → WebSocket PCM”的完整事件顺序。真实 MiMo 测试只在存在密钥时运行。

Flutter 测试覆盖角色卡片、页面跳转、`CallController` 状态、AI 播放时禁用麦克风、VAD 预录、静音提交、短噪声丢弃、PCM 顺序播放以及挂断/后台资源清理。

Android 真机验收：

1. 首页显示两个角色，任意角色均可进入通话页。
2. 页面完成连接、响铃、开场白、聆听、说话、处理和回答状态切换。
3. 孩子无需按钮即可讲话，800ms 静音后自动提交。
4. App 与后端通过 WebSocket 二进制帧传输 PCM。
5. MiMo ASR 结果进入 LangChain；默认预置 TTS 边生成边播放。
6. AI 播放期间不会上传麦克风声音。
7. 挂断后返回角色页，服务端资源与上下文被清除。
8. 网络和模型失败不会导致 App 崩溃。
9. 两个角色均能完成多轮通话，并使用对应 Prompt 与音色。

## 16. 性能目标与完成定义

良好网络下，VAD 静音阈值为 800ms；从 `input.audio.commit` 到默认预置 TTS 首音频的目标为 4 秒内；点击挂断到停止播放为 200ms 内；连续通话至少稳定运行 10 分钟。Voice Design 和 Voice Clone 不参加首音频 4 秒目标。

MVP 完成必须满足：Flutter Android 工程可构建并在真机运行；Docker 后端可本地启动；本地 VAD、WebSocket PCM、MiMo ASR、LangChain、三种 MiMo TTS 模式和两个角色的多轮通话代码完整；默认使用预置流式 TTS；自动化测试通过；README 说明环境变量、局域网连接和运行步骤；提供密钥后可以执行真实端到端联调。
