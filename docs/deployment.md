# 本地正式发布与腾讯云部署

正式版本由开发机完成 Android 签名构建和 Linux 服务镜像构建。GitHub Actions 只运行发布检查；开发机通过 SSH 把不可变镜像传到腾讯云，健康切换成功后再创建 GitHub Release。

发布入口为 `scripts/release-local.ps1`。该脚本不会从 GitHub Secrets 下载或恢复任何私钥。

## 流程概览

1. 推送与 `mobile/pubspec.yaml` 匹配的语义版本标签。
2. GitHub Actions 并行运行后端测试与 Flutter 检查，不构建或部署生产产物。
3. 开发机再次运行同等检查，使用固定正式 keystore 构建 APK 和 AAB。
4. 开发机验证包名、版本号、versionCode 和签名证书。
5. 开发机为 `linux/amd64` 构建带提交标签的镜像。
6. 镜像通过 SSH/SCP 传到服务器并由 `docker load` 导入，不经过 GHCR；导入后以服务器实际 image ID 部署。
7. 服务器使用现有 `.env` 启动新容器；`/health` 和 `/ready` 通过后完成切换，失败则恢复上一镜像。
8. 开发机创建 GitHub Release 并上传 APK、AAB 和 `SHA256SUMS`。

## 开发机前置条件

- Windows PowerShell 7。
- Flutter 3.44.8、Dart 3.12、Java 17 和 Android SDK build-tools。
- Python 3.11 及 `server/requirements.txt` 中的依赖。
- Docker Desktop，能够构建 `linux/amd64` 镜像。
- GitHub CLI `gh`，已登录 `Ankkaya/voice-assistant`。
- OpenSSH `ssh`、`scp`，并已在 `known_hosts` 中人工核验部署服务器主机密钥。
- 固定正式 Android keystore 及其离线备份。

## Android 本地签名

复制示例并填写同一把长期正式密钥：

```powershell
Copy-Item mobile/android/key.properties.example mobile/android/key.properties
```

`mobile/android/key.properties` 示例：

```properties
storeFile=C:/secure/childvoice-release.jks
storePassword=<store password>
keyAlias=childvoice
keyPassword=<key password>
```

该文件和 `.jks` 已被 Git 忽略，不得提交。首个正式版本发布后不能更换密钥，否则 Android 无法覆盖安装并保留用户本地数据。

使用 `keytool` 查询公开证书指纹：

```powershell
keytool -list -v -keystore C:\secure\childvoice-release.jks -alias childvoice
```

脚本会把 APK 的实际签名与 `ANDROID_CERT_SHA256` 比较。指纹可以使用纯十六进制、冒号分隔格式或 `SHA256: AA:BB:...` 整行。

## 本地发布配置

在当前 PowerShell 会话设置：

```powershell
$env:VOICE_SERVER_URL = 'wss://voice.ankkaya.top/ws/voice'
$env:ANDROID_CERT_SHA256 = '<正式证书 SHA-256 指纹>'
$env:DEPLOY_SSH_KEY_PATH = 'C:\secure\docker_demo.pem'
$env:DEPLOY_HOST = '43.139.44.156'
$env:DEPLOY_USER = 'root'
$env:DEPLOY_PORT = '22'
```

`DEPLOY_USER` 未设置时默认为 `root`；SSH 端口默认为 `22`。推荐后续改为权限受限的专用部署用户。

密钥密码只保存在被忽略的 `key.properties` 中；脚本不会把密码、keystore、SSH 私钥或服务端 `.env` 写入产物和日志。

## 服务器准备

项目目录固定为：

```text
/opt/projects/voice-assistant
```

生产环境变量继续保存在 `/opt/projects/voice-assistant/.env`，权限应为 `600`。本地发布只上传：

```text
deploy/compose.prod.yml
deploy/deploy.sh
临时 Docker image tar
```

镜像 tar 导入成功后立即从服务器 `/tmp` 删除。服务端不需要 GitHub Token、GHCR 登录或源代码副本。

`deploy.sh` 接受两类不可变引用：

```text
sha256:<64 位本地 image ID>
ghcr.io/ankkaya/voice-assistant-server@sha256:<64 位镜像摘要>
```

前者用于新的本地发布流程；后者仅用于兼容和回滚已有部署。脚本只在本地不存在 GHCR 摘要时尝试拉取网络镜像，本地 image ID 必须预先由 `docker load` 导入。image ID 是内容寻址值，不能像普通 Docker 标签一样被覆盖。

## 创建版本

先更新 `mobile/pubspec.yaml`：

```yaml
version: 0.0.2+2
```

`+` 后的 Android versionCode 必须随正式版本单调递增。提交后创建并推送标签：

```powershell
git tag -a v0.0.2 -m 'Release v0.0.2'
git push origin feature/voice-call-mvp
git push origin v0.0.2
```

等待 GitHub Actions 的 `Release checks` 成功，然后在干净且与远端标签一致的工作区运行：

```powershell
pwsh -File scripts/release-local.ps1 -Tag v0.0.2
```

脚本会拒绝以下情况：

- 工作区存在未提交修改。
- 标签、`pubspec.yaml` 版本或当前提交不一致。
- 远端没有同一 annotated tag。
- 同名 GitHub Release 已存在。
- 缺少本地签名、证书指纹、SSH 配置或服务器 `.env`。
- APK 包名、版本、versionCode 或签名不符合预期。
- 服务镜像不是 `linux/amd64`。
- 新容器健康检查失败。

## 发布产物

本地产物保存在：

```text
dist/v0.0.2/child-voice-v0.0.2.apk
dist/v0.0.2/child-voice-v0.0.2.aab
dist/v0.0.2/SHA256SUMS
```

`dist/` 被 Git 忽略。发布完成后，同一批文件会上传到 GitHub Release。

开发机保留便于识别的提交标签：

```text
voice-assistant-server:sha-<完整提交 SHA>
```

服务器会核对镜像中的提交标签，并使用 `docker load` 后得到的实际内容寻址 ID 部署：

```text
sha256:<64 位 image ID>
```

部署脚本在切换前保存上一镜像引用。新容器启动或就绪检查失败时会自动恢复上一镜像；不要通过重新构建同一标签来回滚。
