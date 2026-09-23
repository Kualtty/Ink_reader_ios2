# 把墨阅装到 iPad（Windows 电脑 + 免费 Apple ID）

CI 编出来的 ipa 是**未签名**的（GitHub 上没有你的证书），iPad 不认。
所以流程是：**下载 ipa → 在 Windows 上用工具重签 → 装进 iPad**。

---

## 第 1 步：下载 ipa

1. GitHub 打开仓库 `Ink_reader_ios2`
2. **Actions** → 点最新那次 **绿色 ✓** 的运行
3. 页面拉到最下面 **Artifacts** → `InkReader-unsigned-ipa`
4. 下载下来是个 `.zip`，解压得到 `InkReader-unsigned.ipa`

> Artifacts 默认保留 30 天。

---

## 第 2 步：iPad 上打开「开发者模式」（只做一次）

**设置 → 隐私与安全性 → 开发者模式** → 打开 → 按提示重启。

不做这一步，装完点图标会直接闪退/打不开。

---

## 第 3 步：签名安装（三选一）

### A. Sideloadly —— 最简单，推荐先用这个

1. 电脑装 [Sideloadly](https://sideloadly.io/)（Windows / macOS 都有，免费）
2. iPad 数据线接电脑，解锁屏幕，弹「信任此电脑」时点信任
3. Sideloadly 里点 IPA 那一栏选中 `InkReader-unsigned.ipa`
4. 填 Apple ID（**建议专门注册一个小号**，别用主号）
   - 开了双重认证的话，密码栏要填 **App 专用密码**：
     到 [appleid.apple.com](https://appleid.apple.com) → 登录 → 「App 专用密码」→ 生成一个，16 位
5. 点 **Start**，等进度条走完（首次会慢一点）
6. 桌面出现图标后：iPad **设置 → 通用 → VPN 与设备管理 → 点你的 Apple ID → 信任**
7. 打开 App，开始用

**7 天后会失效**（免费账号限制）。到期不用重新编译，插上电脑再点一次 Start 就行。
Sideloadly 里有 **Auto Re-sign** 选项，开着的话连着电脑会自动续签。

### B. AltStore —— 可以无线续签，不用每次插线

1. Windows 装 AltServer（[altstore.io](https://altstore.io)），并用它把 AltStore 装到 iPad
2. iPad 打开 AltStore → **My Apps** → 左上角 `+` → 选那个 ipa
3. 之后只要电脑和 iPad 在**同一个 Wi-Fi**、AltServer 开着，AltStore 会自己在后台续签

适合不想每周插一次线的情况。

### C. 巨魔 TrollStore —— 永久签名，但门槛高

只在 iPadOS **17.0 整版**（17.0.1 及以上都不行）能用。
装了之后 ipa 直接永久签名，**不用 7 天一签**，也没有 App ID 数量限制。

先去「设置 → 通用 → 关于本机」看系统版本：
- 正好是 **17.0** → 可以考虑这条路（能装就用，最省心）
- 17.0.1 及以上 → 回到方案 A 或 B

---

## 第 4 步：装完常见状况

| 现象 | 原因 | 怎么办 |
| --- | --- | --- |
| 点图标闪退 / 打不开 | 开发者模式没开 | 第 2 步 |
| 提示「无法验证 App」「未受信任的企业级开发者」 | 证书没信任 | 设置 → 通用 → VPN 与设备管理 → 信任 |
| 用得好好的突然打不开 | 7 天到了 | 插电脑重签（方案 A 第 7 步） |
| Sideloadly 报 Apple ID 错误 | 用的是登录密码而不是 App 专用密码 | 去 appleid.apple.com 生成专用密码 |
| 装到第 4 个 App 失败 | 免费账号限 3 个 App ID | 删掉一个旧的再装 |

---

## 想要「一次签一年」/ 发给别人装

免费 Apple ID 永远是 7 天。想一劳永逸需要**付费开发者账号**（¥688/年）：

1. 拿到证书后导出 `.p12` 和 `.mobileprovision`
2. 到 GitHub 仓库 **Settings → Secrets and variables → Actions** 新建：
   - `CERTIFICATE_BASE64`（p12 的 base64）
   - `CERTIFICATE_PASSWORD`
   - `PROVISIONING_PROFILE_BASE64`
   - `EXPORT_OPTIONS_PLIST`
3. 我给工作流加一个 `-exportArchive` 的步骤，就能直接产出**已签名、1 年有效**的 ipa，
   下载下来用爱思助手 / Apple Configurator 直接装，不用每次重签。

需要的话跟我说，我把这个工作流补上（再加个 `build-signed-ipa.yml`）。
