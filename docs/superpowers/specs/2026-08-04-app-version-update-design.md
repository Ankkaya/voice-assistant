# GitHub Releases 版本更新功能设计

**日期：** 2026-08-04

**状态：** 已实现

## 目标

为 Flutter Android 客户端增加一个简单的版本更新检查：每次冷启动进入角色管理页面后自动检查公开仓库 `Ankkaya/voice-assistant` 的最新 GitHub Release；同时在页面底部显示当前版本号，用户点击版本号也可以手动检查。存在新版本时弹框提示，并允许通过系统浏览器从该 Release 下载 APK。

版本检查不依赖 FastAPI，不阻塞应用启动，也不影响角色管理和语音通话。

## 范围

包含：

- 每次应用冷启动后自动检查一次最新正式 GitHub Release。
- 在角色管理页面底部显示当前应用版本，点击后可以再次手动检查。
- 检测到更新时弹出更新对话框。
- 从 GitHub Release 直接下载 APK。
- 已是最新版、检查失败和打开下载失败的轻量反馈。
- GitHub Release 的版本、资产和签名发布约定。

不包含：

- 家长设置页、关于页面或新的导航入口。
- 从后台返回前台时重复检查、固定周期轮询或系统后台任务。
- 首页更新横幅、红点、“稍后提醒”或本地更新缓存。
- 强制更新、最低可用版本或拨号门禁。
- 后台 APK 下载、安装进度、静默安装和应用内安装器。
- FastAPI 更新接口、数据库或更新清单。
- Google Play、其他应用商店、iOS、预发布渠道和灰度发布。

## Android 应用身份与签名

### `applicationId`

保持现有配置不变：

```text
com.example.childvoice
```

后续正式版本继续使用该 `applicationId`，不在本功能中修改包名。

Debug 构建当前带有 `.dev` 后缀，因此 debug 与 release 可以共存：

```text
Debug:   com.example.childvoice.dev
Release: com.example.childvoice
```

Debug 包不参与正式 GitHub Release 的覆盖更新验证。

### Release 签名

Android 覆盖安装还要求新旧 APK 使用相同签名证书，并且新 APK 的 `versionCode` 不低于已安装版本。

当前 `mobile/android/app/build.gradle.kts` 的 release 构建仍使用 debug signing config。正式发布前必须改为一个长期固定的 release signing key，并通过本机未提交配置或 GitHub Actions Secrets 使用。签名私钥、keystore 和密码不得提交仓库或写入 APK。

首个正式 Release 发布后不得更换 signing key。否则用户只能卸载再安装，而卸载会清除应用私有目录中的自建角色、头像和音色素材。

## 版本与 Release 约定

### 应用版本

`mobile/pubspec.yaml` 使用 Flutter 标准格式：

```yaml
version: 0.2.0+2
```

- `0.2.0` 是展示版本 `versionName`。
- `2` 是本地默认构建版本；正式流水线使用 `GITHUB_RUN_NUMBER` 生成递增的 Android `versionCode`。
- 每次正式发布必须使用更高的语义版本 Tag，Android 构建号也不得低于已发布版本。
- 即使只修复打包问题，也发布新版本，不能覆盖原有 Release 资产。

GitHub Release API 不返回 APK 内的 Android `versionCode`，因此客户端严格按语义版本规则比较本机 `versionName` 与 Release Tag；本机 `versionCode` 只用于页面展示和 Android 覆盖安装校验。

### Git Tag

正式 GitHub Release 使用现有发布流水线接受的语义版本 Tag：

```text
v0.2.0
```

客户端严格按以下格式解析：

```text
^v([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)$
```

Tag 去掉前导 `v` 后必须与 Release APK 的 `versionName` 一致。不接受 `v2`、`latest` 或带 build metadata 的 `v0.2.0+2`。现有流水线支持 `v0.2.0-rc.1` 形式的预发布版本名。

### Release 资产

每个正式 Release 至少包含：

```text
child-voice-v0.2.0.apk
child-voice-v0.2.0.aab
SHA256SUMS
```

本功能发布一个 universal APK，避免用户判断设备 CPU 架构。APK 文件名必须与 tag 精确对应。

客户端只有在最新 Release 中找到唯一一个匹配文件名、资产状态为 `uploaded` 且文件大小为正数的 APK 时，才将其视为可下载更新。缺少 APK、存在重名、tag 不合法或资产未上传完成均视为 Release 配置错误。

Release 必须满足：

- 已正式发布，不是 draft。
- 不是 prerelease。
- 显式设置为 Latest。
- APK、AAB 和 `SHA256SUMS` 已完整上传。
- Release body 包含用户可理解的变更说明。

现有流水线先完成构建、上传工作流制品和服务端健康检查，最后一次性创建 GitHub Release，因此客户端不会看到资产尚未准备完成的 Release。如果仓库支持 immutable releases，建议启用，避免已发布 APK 被替换。

## GitHub 检查接口

应用冷启动检查或用户点击版本号时请求：

```http
GET https://api.github.com/repos/Ankkaya/voice-assistant/releases/latest
Accept: application/vnd.github+json
User-Agent: voice-assistant-android
X-GitHub-Api-Version: <实现时固定的受支持版本>
```

仓库是公开开源仓库，因此使用匿名请求，不在 APK 中嵌入 GitHub PAT、OAuth token 或其他凭据。

匿名 REST API 存在按来源 IP 计算的限流。本功能每个应用进程启动后请求一次，用户也可以手动检查；同一时刻只允许一个请求，不使用固定轮询或后台任务。作为个人使用的开源应用，这一频率足够低，不需要持久化缓存。遇到限流时，自动检查保持静默，手动检查提示稍后重试。

## Flutter 客户端设计

### 依赖

- `package_info_plus`：读取当前 `versionName` 和 `versionCode`。
- `http`：项目已有，用于调用 GitHub REST API。
- `url_launcher`：通过系统浏览器打开 APK 下载地址。

不引入 `shared_preferences`、GitHub SDK、下载器、文件权限或安装器插件。

### `AppVersion`

封装本机版本：

```text
AppVersion(versionName: "0.1.0", versionCode: 1)
```

`package_info_plus` 返回的 `buildNumber` 必须解析为正整数。解析失败时停止检查并显示通用失败提示，不按 `versionName` 比较。

### `GitHubRelease`

从 GitHub 响应中只解析：

- `tag_name`
- `html_url`
- `body`
- `published_at`
- `draft`
- `prerelease`
- `assets[].name`
- `assets[].state`
- `assets[].size`
- `assets[].browser_download_url`
- `assets[].digest`（存在时）

解析结果包含远端 `versionName`、发布日期、变更说明、APK 大小、APK 下载地址和 Release 页面地址。

URL 必须严格校验：

- Release 页面必须是 `https://github.com/Ankkaya/voice-assistant/releases/tag/<当前 tag>`。
- APK 地址必须是 `https://github.com/Ankkaya/voice-assistant/releases/download/<当前 tag>/<精确 APK 文件名>`。
- 拒绝 HTTP、其他 host、用户名密码、非标准端口、query、fragment 和路径穿越。

Release body 在弹框中按纯文本摘要展示，最多 1,500 个字符和 10 个非空行；不渲染 Markdown、HTML、图片或链接。

### `GitHubReleaseService`

职责：

- 读取本机包版本。
- 请求 `/releases/latest`，超时为 5 秒。
- 限制响应体大小并严格解析 JSON。
- 校验 Release、tag、APK 资产和 URL。
- 按语义版本规则比较远端与本机 `versionName`。
- 返回 `upToDate` 或 `updateAvailable`；异常以类型化失败返回页面。
- 合并同一时刻的自动检查和手动检查，避免重复请求 GitHub。
- `close()` 释放 HTTP client。

同一时刻只允许一个检查请求。service 保存当前检查 Future，自动检查尚未完成时用户点击版本号应复用该 Future；测试应覆盖启动检查与快速连续点击只产生一个 GitHub 请求。

### 下载跳转

检测到新版本后，“从 GitHub 下载”按钮通过 `url_launcher` 的外部应用模式打开经过验证的 `browser_download_url`。

GitHub 可能把下载重定向到其 Release Asset 存储域名，该跳转由系统浏览器处理。应用自身不下载 APK、不申请存储权限，也不判断下载或安装是否完成。

Android 8.0 及以上设备如果未允许浏览器安装未知来源应用，会由系统要求用户对该来源明确授权。应用不绕过系统确认。

## 页面交互

### 启动自动检查

`CharacterPage` 首次挂载并完成首帧渲染后自动触发一次检查：

- 使用 post-frame 回调启动异步请求，不延迟应用首屏和角色数据加载。
- 每个应用进程生命周期只自动触发一次；从后台返回前台或页面重建不重复检查。
- 检测到新版本时弹出与手动检查相同的更新对话框。
- 已是最新版时不显示提示。
- 网络、限流或 Release 配置失败时保持静默。
- 请求完成时页面已经销毁，则丢弃 UI 操作，不弹框、不显示 SnackBar。

自动检查期间，页面底部版本入口显示检查中状态。用户此时点击入口不会创建第二个请求。

### 版本号位置

在现有角色管理页面 `CharacterPage` 的可滚动内容最底部增加居中版本文本：

```text
版本 0.1.0 (1)
```

交互要求：

- 使用较小的次要文字颜色，不抢占角色内容的视觉层级。
- 保留底部 SafeArea 和至少 24 像素间距。
- 整行具有足够的可点击区域，不能只让文字笔画可点。
- 增加 button 语义和“当前版本 0.1.0，点击检查更新”的无障碍标签。
- 版本值来自 `package_info_plus`，不能硬编码。

### 检查中

自动检查开始或用户点击版本号后：

- 立即设置 `_checkingUpdate = true`。
- 版本区域显示“正在检查更新…”和小型进度指示。
- 检查完成前忽略后续点击。
- 页面其他角色管理功能保持可用。

手动检查与自动检查使用相同服务，但反馈略有区别：两者检测到新版本都会弹框；只有手动检查才为“已是最新版”和检查失败显示 SnackBar。

### 发现新版本

当远端语义版本高于本机 `versionName` 时弹出 `AlertDialog`：

```text
发现新版本 0.2.0

当前版本：0.1.0 (1)
最新版本：0.2.0
安装包：约 48 MB

更新内容：
• 增加版本更新检查
• 修复通话问题

[取消]  [从 GitHub 下载]
```

要求：

- “取消”只关闭弹框，不保存忽略状态。
- “从 GitHub 下载”打开匹配 APK 的下载地址。
- 浏览器启动成功后关闭弹框；启动失败时保留弹框并显示 SnackBar，允许重试。
- 发布说明过长时内容区域可滚动，操作按钮始终可见。
- 不阻止系统返回键关闭弹框，不属于强制更新。

### 已是最新版

当远端语义版本不高于本机版本时不弹更新框，通过 SnackBar 提示：

```text
当前已是最新版本
```

本机版本高于最新 Release 时按开发版本处理，同样视为最新版，不提示降级。

### 检查失败

失败时恢复版本文本并通过 SnackBar 提示：

- 无网络、超时、TLS 或 GitHub 5xx：“检查更新失败，请稍后重试”。
- GitHub 403/429：“GitHub 请求频繁，请稍后重试”。
- GitHub 404：“暂未找到可用版本”。
- tag、APK 或响应配置错误：“版本信息配置有误”。
- 无法打开浏览器：“无法打开 GitHub，请稍后重试”。

失败不影响角色管理、拨号或通话。提示中不要求用户配置 GitHub token。

## 状态流程

```text
进入角色管理页 --首帧后自动检查--+
                                  |
底部版本号 --------点击手动检查---+--> checking
                                        /     \
                                       /       \
                                  请求失败      请求成功
                                    |             |
                         自动静默 / 手动 SnackBar +-- 远端版本 <= 本机版本
                                                  |      自动静默 / 手动提示最新版
                                                  |
                                                  +-- 远端版本 > 本机版本
                                                         |
                                                         v
                                                       更新弹框
                                                         |
                                                         v
                                                   系统浏览器下载 APK
```

页面销毁时如果请求尚未完成，不再更新 UI 或弹框；service 正常释放。无需取消系统浏览器中的下载。

## GitHub Actions 发布流程

使用仓库现有 `.github/workflows/release.yml` 发布：

1. 检出 tag 对应代码。
2. 校验 `v0.2.0` 或 `v0.2.0-rc.1` 形式的语义版本 Tag。
3. 恢复 GitHub Actions Secrets 中固定的 release keystore 和签名配置。
4. 执行 `flutter pub get`、格式检查、`flutter analyze` 和 `flutter test`。
5. 构建 universal release APK。
6. 使用 Android SDK 工具验证 APK 的 `applicationId` 是 `com.example.childvoice`，并验证 version name、version code 和签名证书指纹。
7. 将 APK、AAB 重命名为约定文件名并生成 `SHA256SUMS`。
8. 服务端部署健康检查通过后创建 GitHub Release 并上传产物。
9. 人工核对发布说明、资产和真机覆盖安装结果。

Workflow 使用 GitHub 自动提供的 `GITHUB_TOKEN` 上传当前仓库 Release，权限限制为 `contents: write`。该 token 只存在于发布任务，不写入 APK。

来自 fork 的 Pull Request 不拥有上游 signing secrets，也不能触发正式签名发布。

## 发布与回滚

标准发布顺序：

1. 合并待发布变更。
2. 创建语义版本 tag，例如 `v0.2.0`；流水线以 Tag 覆盖 Flutter build name，并以 `GITHUB_RUN_NUMBER` 设置 build number。
3. 等待 GitHub Actions 测试、签名和资产校验通过。
4. 在一台安装上一正式版本的真机上覆盖安装，确认本地角色和素材保留。
5. 流水线在部署健康检查通过后创建 GitHub Release。
6. 在已安装旧版本的真实设备上点击页面底部版本号，完成端到端检查与下载验收。

已发布资产不覆盖、不重传同名文件，也不移动现有版本 tag。新版本有问题时优先修复并发布更高语义版本的 Release。

紧急情况下可以把上一稳定 Release 重新设为 Latest：尚未更新的客户端不会再提示问题版本；已经安装更高版本的客户端只会显示“当前已是最新版本”，不会被提示降级。不要通过卸载回退，因为卸载会清除本地角色数据。

## 安全与隐私

- 固定使用 `com.example.childvoice`，每次正式 APK 保持同一 release 签名。
- APK 不包含 GitHub token、服务端密钥、keystore 或签名密码。
- 只信任固定公开仓库的 GitHub API 和精确匹配的 Release APK URL。
- Release body 以受限纯文本展示，不执行 Markdown、HTML 或脚本。
- 版本检查只在应用冷启动或用户点击版本号时发生，不发送设备 ID、角色资料、语音数据或通话信息。
- 应用不记录用户是否下载或安装，不增加更新统计。

## 测试方案

### 单元测试

- 本机 `buildNumber` 正整数解析及非法值处理。
- 合法稳定版/预发布语义版本，以及缺少 `v`、带 build metadata、格式不完整等非法 tag。
- 远端语义版本小于、等于和大于本机版本，包括预发布排序。
- draft、prerelease、APK 缺失、重复 APK、状态非 uploaded 和文件大小为零均被拒绝。
- 仓库、tag、文件名或 host 不匹配的 URL 被拒绝。
- Release body 纯文本摘要和长度限制。
- 200、403、404、429、5xx、超时、非法 JSON 和超大响应。
- 启动检查、同时发生的手动检查和快速连续点击只产生一个 GitHub 请求。
- HTTP client 能被正常释放。

### Widget 测试

- 角色管理页底部显示来自包信息的真实版本号。
- 每次应用冷启动并完成首帧后自动发起一次检查，不阻塞角色展示。
- 页面重建和前后台切换不重复触发自动检查。
- 自动检查发现更新时弹框；最新版和失败时保持静默。
- 版本号拥有足够点击区域和正确无障碍语义。
- 点击后显示检查状态，重复点击不重复请求。
- 远端版本较高时只弹出一次更新对话框。
- 最新版和本机开发版只显示“当前已是最新版本”。
- 取消弹框不打开浏览器，再次点击版本号仍可检查。
- 下载按钮打开正确 APK URL；打开失败时弹框保留且可重试。
- 网络和 Release 配置失败只显示对应 SnackBar。
- 检查期间角色管理功能不被禁用。
- 页面销毁后完成的异步请求不会调用已卸载的 context。

### 发布验收

- workflow 拒绝不符合既定语义版本格式的 Tag。
- APK 内 `applicationId` 始终是 `com.example.childvoice`。
- Release APK 使用固定正式签名。
- 从上一正式版本覆盖安装成功且本地数据保留。
- 最新 GitHub Release 能被真实 release APK 正确识别。
- 浏览器下载、取消下载、未知来源授权、取消安装和安装完成流程可用。
- GitHub 限流或不可达时，应用其余功能保持正常。

## 实施拆分

1. 建立固定 release signing 和密钥备份方案，保持现有 `applicationId`。
2. 使用现有 GitHub Actions tag 校验、签名构建、SHA-256 和 Release 流程。
3. 实现 `AppVersion`、`GitHubRelease`、`GitHubReleaseService` 及单元测试。
4. 在 `CharacterPage` 增加启动检查，并在底部增加版本入口、检查状态、更新弹框和 Widget 测试。
5. 创建首个正式 Release，完成真机覆盖安装及端到端下载验收。

## 成功标准

- 角色管理页面底部始终正确显示当前版本号。
- 每次应用冷启动后自动检查一次，已是最新版或检查失败时不打扰用户。
- 点击版本号可以随时手动检查，最新版和失败时给出明确反馈。
- 最新正式 Release 的语义版本较高时弹出更新提示，并能直接下载匹配 APK。
- 已是最新版和检查失败时给出明确轻量反馈，不弹错误的更新框。
- 检查和下载失败不影响角色管理与通话。
- `applicationId` 保持 `com.example.childvoice`。
- 新 APK 能覆盖上一正式版本并保留本地自建角色与素材。

## 参考资料

- [GitHub REST API：Releases](https://docs.github.com/en/rest/releases/releases)
- [GitHub：管理 Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [GitHub：链接到最新 Release 和资产](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
- [GitHub REST API：匿名访问限流](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
- [Android：应用更新约束](https://developer.android.com/google/play/app-updates)
- [Android：应用签名](https://developer.android.com/studio/publish/app-signing)
- [Android：通过网站分发 APK](https://developer.android.com/distribute/marketing-tools/alternative-distribution)
