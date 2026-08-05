# GHCR、腾讯云与 Android 自动发布

生产发布由 `.github/workflows/release.yml` 完成。推送语义化版本标签后，工作流测试代码、发布不可变服务端镜像、构建签名 Android 包、部署腾讯云，并在健康检查通过后创建 GitHub Release。

## 发布入口

普通 Pull Request 和 `main` 推送只运行 `.github/workflows/ci.yml`，不会接触生产密钥或部署服务器。

生产发布必须从已合入 `main` 的提交创建标签：

```bash
git switch main
git pull --ff-only origin main
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin v0.2.0
```

支持 `v0.2.0` 和 `v0.2.0-rc.1`，其他标签不会触发发布工作流。

## GitHub Environment

在仓库 Settings → Environments 中创建 `production`，推荐启用 Required reviewers，并只允许 `v*` 标签部署。

配置 Environment variable：

| 名称 | 示例 | 用途 |
| --- | --- | --- |
| `VOICE_SERVER_URL` | `wss://voice.ankkaya.top/ws/voice` | 编译进 Android App 的公开 WebSocket 地址 |
| `DEPLOY_PORT` | `22` | SSH 端口；不设置时使用 22 |

配置 Environment secrets：

| 名称 | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 正式 `.jks` 文件的 Base64 文本 |
| `ANDROID_KEY_ALIAS` | Android 签名别名 |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_PASSWORD` | 私钥密码 |
| `ANDROID_CERT_SHA256` | 正式签名证书的 SHA-256 指纹，用于发布前核验 APK |
| `DEPLOY_HOST` | `43.139.44.156` |
| `DEPLOY_USER` | 当前为 `root`；后续建议改为专用部署用户 |
| `DEPLOY_SSH_KEY` | `docker_demo.pem` 的完整内容 |
| `DEPLOY_HOST_KEY` | 经人工核验的服务器 `known_hosts` 完整行，不是单独的指纹 |

`ANDROID_CERT_SHA256` 可以填写纯十六进制、冒号分隔格式，或 `keytool` 输出的
`SHA256: AA:BB:...` 整行；工作流会统一规范化后再核验 APK 签名。

在 Windows PowerShell 中生成 keystore 的 Base64 文本：

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes('C:\secure\childvoice-release.jks')
) | Set-Clipboard
```

不要提交 `.jks`、`key.properties`、SSH 私钥或任何密码。原始 Android keystore 必须另做离线备份；丢失后将无法为现有 App 发布可覆盖安装的更新。

## 服务器准备

服务器项目根目录固定为：

```text
/opt/projects/voice-assistant
```

现有 `.env` 继续保存在该目录，权限应保持 `600`。工作流只上传 `deploy/compose.prod.yml` 和 `deploy/deploy.sh`，不会读取或上传服务器 `.env`。

如果 GHCR Package 是 Public，服务器不需要登录。如果保持 Private，需要在服务器上使用仅含 `read:packages` 权限的 Token 登录一次：

```bash
printf '%s' "$GHCR_READ_TOKEN" | docker login ghcr.io --username Ankkaya --password-stdin
```

完成后从当前 shell 清除 `GHCR_READ_TOKEN`。不要把 Token 写进项目 `.env`。

`deploy/deploy.sh` 只接受以下不可变格式：

```text
ghcr.io/ankkaya/voice-assistant-server@sha256:<64 位十六进制摘要>
```

脚本会保存当前镜像、拉取新镜像、启动容器并检查 `/health` 和 `/ready`。失败时自动恢复上一个 digest。服务器不会执行 `git pull` 或 `docker build`。

## Android 本地签名

GitHub Actions 从 Environment Secrets 读取签名参数。本地仍可在 `mobile/android/key.properties` 中配置同一把正式密钥；示例见 `mobile/android/key.properties.example`。Release 构建不再回退到 debug 签名，缺少任何签名参数都会失败。

## 发布产物

成功发布后，GitHub Release 包含：

```text
child-voice-v0.2.0.apk
child-voice-v0.2.0.aab
SHA256SUMS
```

对应服务端同时存在版本标签和提交标签，但腾讯云实际部署的是不可变 digest：

```text
ghcr.io/ankkaya/voice-assistant-server:v0.2.0
ghcr.io/ankkaya/voice-assistant-server:sha-<完整提交 SHA>
ghcr.io/ankkaya/voice-assistant-server@sha256:<digest>
```
