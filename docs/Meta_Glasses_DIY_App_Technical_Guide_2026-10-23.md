# Meta 智能眼镜 DIY App：技术资料与实施指南

> **项目目标：** 为自己的眼镜开发可切换模型的手机配套 App，在服务支持地区使用获准的 ChatGPT 订阅接入，在中国使用 DeepSeek，并预留 Mac／自托管本地模型接口。  
> **硬件范围：** 包装照片标示为 **BLAYZER OPTICS · GEN 2**，按 Ray-Ban Meta Blayzer Optics（Gen 2）规划。  
> **资料核对日期：** 2026-10-23。  
> **本文定位：** 个人 DIY 的技术设计、操作指引、参考文档与开发交接材料，不是已经通过真机验收的成品说明。  
> **验证范围：** 已核对公开文档、部分源码、发布记录及同型号问题记录；未在你的手机和眼镜上编译、运行，也未使用你的模型账号进行授权或付费调用。

---

## 使用这份文档

**推荐实施路线：先安装原版并验证眼镜 → 接 DeepSeek → 验证官方 ChatGPT 计划授权 → 接 Mac 本地模型 → 再做免手操作和工具调用。**

手机具体型号、iOS／Android 版本尚未确认。本文以你前面重点关注的 **OpenVision／iPhone 路线**为主；Android 的参考路径单列，不把 iOS 项目误当成跨平台应用。

快速阅读顺序：

- 准备开始动手：先看第 3、5、6、8 节。
- 交给 Codex／Claude 开发：看第 7、12、13、17 节。
- 订阅与本地部署：看第 9、10 节。
- 查原始资料：第 18 节是按用途分类的文档索引。

### 目录

[1. 目标和边界](#s1) · [2. 总体架构](#s2) · [3. 版本与同款眼镜兼容性](#s3) · [4. 值得参考的项目](#s4) · [5. 账号、环境与费用](#s5) · [6. OpenVision 编译与首次连接](#s6) · [7. 多模型设计](#s7) · [8. DeepSeek 接入](#s8) · [9. ChatGPT 订阅接入](#s9) · [10. 本地模型](#s10) · [11. 音频、相机和后台运行](#s11) · [12. 开发任务](#s12) · [13. 验收清单](#s13) · [14. 故障排查](#s14) · [15. DIY 玩法与安全边界](#s15) · [16. 自用和公开发行](#s16) · [17. 开发交接提示词](#s17) · [18. 文档索引](#s18)

<a id="s1"></a>
## 1. 目标和边界

### 1.1 我们实际要做什么

把眼镜作为可穿戴的输入输出设备：相机提供第一视角，麦克风输入问题，扬声器播放答案；手机负责连接、权限、转写、模型调用、朗读和会话管理。

这是**开发配套 App**，不是更换眼镜操作系统，也不是把云端大模型安装进眼镜。Meta 的 Device Access Toolkit（下文简称 DAT）提供移动应用接入路径；官方 iOS、Android 仓库均存在。[M1] [M5]

本项目按无镜内显示屏的音频／相机眼镜规划，不设计 Display 型号专有的镜内字幕界面。产品型号参考品牌页，最终以 Meta AI App 中的设备信息为准。[H1]

### 1.2 三个目标模式

| 模式 | 目标 | 第一版策略 |
|---|---|---|
| 海外模式 | 在相应服务支持地区使用 ChatGPT | 官方计划授权可用时启用；普通 API 是独立可选后端，不默认替代订阅 |
| 中国模式 | 使用 DeepSeek | 正式 API Key；语音识别与朗读分别配置 |
| 本地模式 | 使用自己的 Mac／服务器，或手机端模型 | 默认不调用云端；不自动把失败请求转发给外部服务 |

以上是产品设计，不是对账号、地区或设备兼容性的承诺。“海外”也不代表所有海外地区都支持同一服务，需检查官方支持地区。[O7]

### 1.3 第一版不做什么

暂不做全天候录音、全天候视频上传、无条件远程执行命令、支付或交易操作、生产环境自动发布，也不以替换系统唤醒词或完全移除 Meta AI App 为前提。

**系统的“Hey Meta”、第三方应用被语音唤起、应用运行时监听自己的唤醒词，是三个不同层面的能力。** DAT 1.0 的部分语音唤起、转写和输入能力仍标为 Experimental，不能按通用稳定能力承诺。[M2]

<a id="s2"></a>
## 2. 总体架构

下面是建议架构，不是 OpenVision 当前源码的逐字映射：

```text
┌────────────────────────────────────────────┐
│ Meta 眼镜                                  │
│ 第一视角相机 / 麦克风 / 扬声器              │
└───────────────────┬────────────────────────┘
                    │
           相机走 DAT；音频按实际路由处理
                    │
┌───────────────────▼────────────────────────┐
│ 手机 App                                   │
│ 设备状态 / 权限 / 会话状态机                │
│ 录音 → 转写 → 按需拍照 → 模型请求 → 朗读    │
│ 模型选择 / 本地历史 / 可见的数据目的地      │
└───────────────────┬────────────────────────┘
                    │
┌───────────────────▼────────────────────────┐
│ 模型适配层                                 │
│ ChatGPTPlanProvider / OpenAIAPIProvider     │
│ DeepSeekProvider / LocalModelProvider       │
└───────┬────────────────┬───────────────────┘
        │                │
   云端正式接口       Mac／本地推理服务
                         │
                  可选工具执行层
             知识库 / 笔记 / 开发任务 / 家居
```

### 2.1 为什么拆开“听、想、说”

建议分成五个接口：

| 模块 | 负责 | 不应该负责 |
|---|---|---|
| `DeviceAdapter` | 眼镜连接、相机、设备事件 | 决定使用哪家模型 |
| `SpeechToText` | 音频转文字 | 默认上传到当前大模型供应商 |
| `ModelProvider` | 文字／图片推理、工具请求 | 直接操控麦克风和系统签名 |
| `TextToSpeech` | 将最终回答转成声音 | 将推理内部字段当正文朗读 |
| `ToolExecutor` | 执行经过权限检查的工具 | 相信模型输出就授予全部系统权限 |

这样从 ChatGPT 切到 DeepSeek，不需要重新实现眼镜连接；从云端切到本地，也能独立替换语音识别。

### 2.2 首个闭环

```text
用户主动开始一次提问
→ 录音
→ 转写
→ 用户需要看图时取得一张新照片
→ 发送文字与照片
→ 接收最终答案
→ 朗读
→ 停止或等待下一轮
```

建议先实现“说一句、看一张、答一句”，再实现实时全双工和连续视觉。Meta 官方 Cookbook 的轻量示例也采用照片、转写和网关组合，可以参考其职责划分，而不必采用它全部的模型和工具服务。[M6]

<a id="s3"></a>
## 3. 版本与同款眼镜兼容性：必须先看

### 3.1 本次核对到的版本快照

| 项目 | 核对结果 | 对实施的影响 |
|---|---|---|
| OpenVision | 发布页标记 `v2.14.0` 为 Latest；页面日期为 2026-10-02 | 可以作为初始可复现标签，不把移动的 `main` 当固定版本。[OV11] |
| OpenVision 的 DAT 依赖 | `v2.14.0/project.yml` 精确锁定 `0.9.0` | 初次编译保持这个组合；升级 SDK 要单独开分支。[OV4T] |
| OpenVision 最低 iOS | 当前工程设置为 `18.0` | 旧安装文档中的 iOS 16 不能直接照用。[OV4] |
| Meta 官方 iOS DAT | CHANGELOG 最新条目为 `1.0.1`，日期 2026-10-09 | 官方最新版本不等于 OpenVision 已适配版本。[M2] |
| Meta SDK 状态 | 官方仓库仍写 Developer Preview | 自用开发与公开发行必须分别确认。[M1] |

**旧文档存在落后：** `SETUP.md` 部分内容仍描述旧 SDK 和工具链。遇到冲突，先检查你实际检出的 `project.yml`、依赖锁文件、发布记录和源码；不要让开发 Agent 同时使用不同版本的 API。[OV2] [OV4T]

### 3.2 与你的 Blayzer Gen 2 直接相关的修复

OpenVision 的 **Issue #55：Blayzer Gen 2 not recognized** 记录了同款设备的真实问题：旧 SDK 下设备数为 0，升级后又遇到相机挂载和项目配置问题。维护者最终将相关修复收入 `v2.13.0`。这是项目侧的兼容性证据，不等于已经验证了你手上的设备。[OV12]

优先核对以下四项：

1. 不使用早期缺少该硬件支持的 DAT 版本。
2. `DeviceSession` 启动并进入有效状态后，再附加相机；不要在未启动的会话上直接 `addCamera`。
3. Wearables Developer Center 项目中填好 Apple Team ID，并开启相机访问及用途说明。
4. 完成重新注册和项目提供的 **Install/Update Glasses App** 流程。

第 2 项可对照 `GlassesManager.swift`；第 3、4 项及该次迁移的版本门槛见 `v2.13.0` 发布说明。[OV6] [OV10]

发布记录当时列出的最低门槛包括眼镜固件 V126、Meta AI App V282、iOS 17.2；这只是该版本迁移的参考下限。**本次 OpenVision 工程自身要求 iOS 18，且后续固件可能改变要求。**不要将旧门槛当作永远有效的推荐版本。[OV10] [OV4]

### 3.3 版本记录模板

在仓库中创建 `docs/environment.md`，实际填写：

```text
测试日期：
OpenVision tag / commit：
Meta DAT 精确版本：
Package.resolved 的位置及哈希：
Xcode / Swift / macOS：
iPhone 型号 / iOS：
眼镜设备型号 / 固件：
Meta AI App 版本：
连接模式：前台 / 锁屏 / 后台
模型供应商 / 模型 ID：
测试网络：家庭 Wi-Fi / 移动网络 / 其他
```

不写入账号密码、Token、API Key 或完整设备序列号。每次升级先跑第 13 节回归测试。

<a id="s4"></a>
## 4. 值得参考的项目

| 项目 | 用途 | 对本项目的建议 |
|---|---|---|
| **[rayl15/OpenVision][OV1]** | iOS 多模型眼镜助手；源码可修改 | 第一优先。复用设备、界面和音频层，模型认证单独审查。 |
| **[Meta 官方 03_visionclaw][M6]** | 轻量 iOS 拍照问答示例 | 学习手机和服务端如何划分职责；不要和下一个同名项目混淆。 |
| **[Intent-Lab/VisionClaw][P1]** | 实时语音、视觉及工具集成 | 适合后续研究实时交互。当前默认网关不是公开服务，自托管还涉及网关、Agent 和 LiveKit 配置。 |
| **[OpenGlasses／Avenkin][P2]** | 可选 AI、语音、记忆与穿戴设备交互 | 当前 README 名称已是 Avenkin；作为架构参考，许可证为 BSL 1.1，不是可无条件商用的 MIT 项目。[P3] |
| **[locafra/hey-casa][P4]** | Android 眼镜语音控制 Home Assistant | 可借鉴语音启动、家庭服务调用和回复流程；语音唤起等实验能力不能当成正式发行能力。 |

**平台选择：** iPhone 优先 OpenVision；Android 优先官方 DAT 示例，再借鉴 VisionClaw／Hey Casa。不要一开始同时重写两端。

OpenVision 采用 MIT 许可证，修改与分发时仍需遵守版权和许可保留要求。Meta SDK、模型权重和其他依赖各自的授权不能被 OpenVision 的 MIT 一并替代。[OV13] [M1]

<a id="s5"></a>
## 5. 账号、环境与费用

### 5.1 准备清单

| 项目 | 准备内容 |
|---|---|
| 开发电脑 | 已有 M4、48GB 内存 Mac，可先作为开发和本地推理测试机；具体性能以实际模型测试为准 |
| 手机 | 确认是否为 iPhone、型号及系统版本；眼镜真实连接必须用真机验收 |
| Apple 账号 | 在 Xcode 登录，配置个人团队或开发者会员 |
| Meta | 官方 App 中完成眼镜配对；按当前开发流程完成项目、注册和授权 |
| 模型账号 | DeepSeek 正式 API Key；ChatGPT 官方授权单独验证；本地服务独立配置 |
| 工程工具 | Xcode、Git、XcodeGen；涉及 MLX 构建时检查 Metal Toolchain |
| 支持数据 | 一张不含隐私的测试图、几段自录测试语音、固定的测试问题 |

Xcode／依赖要求以检出的工程与发布记录为准。`v2.14.0` 发布说明已经提到针对当前工具链的 MLX 构建修复，因此不要仅依据旧文档中的“Xcode 15+”决定环境。[OV11]

### 5.2 只为个人 DIY，不必先为上架付费

| 项目 | 当前可确认的费用／边界 |
|---|---|
| 免费 Apple Personal Team | 可安装个人测试 App，但描述文件 7 天到期，需重新构建安装；还有数量限制。[A1] |
| 中国区 Apple Developer Program | 当前为 **688 元／年**，最终以注册付款页面为准。[A2] |
| 签名证书 | 自己的开发签名由 Apple 开发体系管理，不需要购买第三方共享证书。[A1] |
| Meta 开发准备 | OpenVision 安装说明列为免费开发账号路径；不把它等同于已取得公开发行资格。[OV2] |
| 模型调用 | ChatGPT 计划授权、普通 OpenAI API、DeepSeek API 分别管理；普通 ChatGPT 与 API 账单分离。[O6] |
| 本地推理 | 无需按 Token 向云端供应商付费的本地链路，仍有设备、电力、维护和远程访问成本 |

**建议先免费编译和验证，再决定是否缴苹果年费。**若免费团队因某项 entitlement 无法签名，先查具体能力；不要将所有签名失败都归结为“必须买证书”。OpenVision 当前有增加内存限制的 entitlement，缩减手机本地大模型功能时可评估是否需要该能力，但必须重新测试。[OV9]

<a id="s6"></a>
## 6. OpenVision 编译与首次连接

以下是建议操作顺序。命令用于建立可复现的工作副本，未在你的 Mac 上执行；遇到后续版本变化，以所选标签的实际文件为准。

### 6.1 取得一个固定起点

先安装 Xcode，并完成首次启动所需组件安装。已有 Homebrew 时可以使用：

```bash
brew install xcodegen

git clone --branch v2.14.0 --single-branch \
  https://github.com/rayl15/OpenVision.git GlassesDIY
cd GlassesDIY
git switch -c diy/baseline

git rev-parse HEAD
xcodebuild -version
```

不要在第一步就升级所有依赖，也不要直接覆盖仓库的锁文件。先原样编译，成功后记录 commit 和工具链。

### 6.2 生成自己的配置

```bash
cp Config.xcconfig.example Config.xcconfig
cp OpenVision/Config/Config.swift.example OpenVision/Config/Config.swift
```

`Config.xcconfig` 的核心字段参考实际模板：[OV5]

```xcconfig
DEVELOPMENT_TEAM = YOUR_APPLE_TEAM_ID
PRODUCT_BUNDLE_IDENTIFIER = com.example.glassesdiy
META_APP_ID = YOUR_META_APP_ID
CLIENT_TOKEN = AR|YOUR_META_APP_ID|YOUR_META_CLIENT_TOKEN
APP_LINK_URL_SCHEME = glassesdiy
```

这里的 `com.example.glassesdiy` 和 `glassesdiy` 是示例，须替换成自己的标识，并确保 App 和开发后台的回调配置一致。保留模板对 `CLIENT_TOKEN` 完整格式的要求。

**模型密钥不要填进准备公开的源码。**建议在 App 设置中输入并存入 Keychain；检查 `.gitignore` 和待提交文件，防止配置泄露。Meta Client Token 也不是 OpenAI／DeepSeek 的 API Key。

### 6.3 生成 Xcode 工程并编译

```bash
xcodegen generate
open OpenVision.xcodeproj
```

在 Xcode 中选择自己的 Team 和实际 iPhone，检查签名，然后使用 Run。新增或删除源文件后，应重新生成工程，避免只改 `.xcodeproj` 后又被生成器覆盖。

若报缺少 Metal 编译器，按项目说明与所用 Xcode 安装相应组件；支持该命令的 Xcode 可使用：[OV2]

```bash
xcodebuild -downloadComponent MetalToolchain
```

**构建插件要审查后再信任。**项目文档为命令行构建列出跳过宏／插件验证的参数，但不建议把这些参数设成所有项目的默认值。第一轮优先在 Xcode 里逐项确认依赖。

### 6.4 分清两处“开发者模式”

一处是 iPhone 允许开发版应用运行的系统设置；另一处是 **Meta AI App 内用于眼镜开发的 Developer Mode**。它们不能相互代替。

OpenVision 文档描述的 Meta 入口为设置中的 About／版本信息页，连续点击版本号五次后开启开发模式。实际菜单名称可能变化，按手机当前界面和官方说明核对。[OV2]

### 6.5 注册、授权与眼镜端组件

对照 `v2.13.0` 的迁移说明依次检查：[OV10]

```text
Meta AI App 完成正常配对
→ Wearables Developer Center 项目配置正确
→ Apple Team ID 与应用身份匹配
→ 相机访问开启并填写用途
→ App 发起注册并完成 Meta AI 回调
→ 必要时 Unregister → Register 更新授权
→ 执行 Install/Update Glasses App（当前版本提供时）
→ 检查设备数量和兼容状态
```

该按钮用于 DAT 集成需要的眼镜端应用／组件流程，**不是给眼镜安装一个大模型**。

### 6.6 首轮验收只检查设备

先不要调复杂模型：

- 在 App 中看到设备，而不只是蓝牙设置显示“已连接”。
- 得到一张实时的新画面，而不是旧缓存。
- 录音实际来自眼镜，并能通过眼镜播放声音。
- 停止使用后释放相机和录音；摘戴、断开和重连有明确状态。

先用手机摄像头模式跑通 App，再测眼镜，能区分“App／模型失败”和“眼镜连接失败”。不要把手机模式成功当作眼镜验收成功。

<a id="s7"></a>
## 7. 多模型设计：不要只做一个 Base URL 输入框

### 7.1 推荐的后端边界

| 后端 | 认证 | 协议 | 应独立处理的问题 |
|---|---|---|---|
| `ChatGPTPlanProvider` | 官方 OAuth 计划授权 | 官方规定的 Responses 路径 | 账号资格、权限、模型列表、Token 刷新、计划额度 |
| `OpenAIAPIProvider` | 正式 API Key | 选定的公开 API | 独立计费、模型能力和限额 |
| `DeepSeekProvider` | DeepSeek API Key | Chat Completions 等官方支持格式 | 模型 ID、图片能力、思考参数和错误处理 |
| `LocalModelProvider` | 自建网关认证 | 本地服务实际支持的接口 | 网络、模型加载、休眠、图片能力、离线策略 |

前三者不能仅凭“都带一个 Bearer Token”就混用。OpenAI 官方计划使用流程和普通 API 的认证、支持字段与计费语义不同。[O3] [O4] [O6]

### 7.2 能力描述，而不是硬编码模型名称

建议每个后端对上层暴露：

```text
supportsText
supportsImages
supportsStreamingText
supportsNativeAudio
supportsTools
executionLocation = on_device / private_server / cloud
billingMode = subscription / metered / local
```

这些是**我们建议新增的抽象字段**，不是任何供应商的通用返回格式。

“接口兼容”只代表部分请求形状接近，不代表视觉、工具、结构化输出和流式事件完全一致。例如 Ollama 官方明确说明它支持 OpenAI API 的一个子集。[L1]

### 7.3 三个配置档

建议先手动切换，之后才考虑网络感知提示。切换会话时告知用户哪些历史文字和图片将发给新的服务，默认不跨供应商发送旧照片。

下面是**建议的自定义配置结构**，不能直接当作 OpenVision 现有导入文件：

```json
{
  "schemaVersion": 1,
  "activeProfile": "cn",
  "profiles": {
    "overseas": {
      "provider": "chatgpt_plan",
      "modelSelection": "account_catalog",
      "speechRecognition": "on_device",
      "speechOutput": "system",
      "automaticFallback": false
    },
    "cn": {
      "provider": "deepseek",
      "baseURL": "https://api.deepseek.com",
      "model": "deepseek-flash",
      "credentialRef": "keychain:deepseek",
      "automaticFallback": false
    },
    "local": {
      "provider": "local_openai_compatible",
      "baseURL": "https://your-private-gateway.example/v1",
      "model": "REPLACE_WITH_INSTALLED_MODEL",
      "credentialRef": "keychain:private_gateway",
      "cloudAllowed": false,
      "automaticFallback": false
    }
  }
}
```

安全规则建议固定为：密钥不导出；更换域名不自动携带旧凭据；本地模式禁止云端回退；订阅额度不足不自动切成付费 API。

### 7.4 OpenVision 中优先查看的代码位置

| 路径 | 阅读目的 |
|---|---|
| `Managers/GlassesManager.swift` | 注册、设备发现、相机及会话生命周期 |
| `Services/AIBackend/` | 后端协议、注册与云端请求 |
| `Services/AIBackend/OpenAIService.swift` | 兼容接口 URL 拼接、请求和订阅分支 |
| `Services/OAuth/` | 授权、回调、Token 保存及刷新 |
| `Services/Audio/`、`Services/Voice/` | 音频路由、识别、唤醒和输入结束判断 |
| `Services/TTS/` | 朗读及分句播放 |
| `Views/VoiceAgent/` | 主会话编排和 UI 状态 |
| `Managers/SettingsManager` 相关代码 | 模型配置、凭据管理及持久化 |

路径以 `OpenVision/` 为代码根目录；具体文件名可能随提交变化，先在本地搜索定义，不要凭表格猜不存在的符号。架构入口见项目架构说明。[OV3]

**一个容易误判的实现细节：** 当前 `OpenAIService.connect()` 主要检查配置是否填写，不等于已向服务器发请求并通过认证。应增加真正的连通性测试，分别显示配置完整、网络可达、认证成功、推理成功。[OV7]

<a id="s8"></a>
## 8. DeepSeek 接入

### 8.1 当前接口与模型能力

官方文档当前列出的 OpenAI 格式 Base URL 是 `https://api.deepseek.com`。`deepseek-flash` 支持图片输入；模型表中的 `deepseek-v4-pro` 不支持视觉。模型别名及其实际版本可能更新，不要按过往印象写死能力。[D1] [D2] [D3]

**第一版建议：** 先用 `deepseek-flash` 做文字和单张图片问答，普通口语交互优先测试非思考模式的响应速度；复杂问题再允许用户切换。思考模式的具体字段以官方文档为准。[D4]

### 8.2 在 OpenVision 的兼容后端中测试

建议初始填写：

```text
认证：API Key
Base URL：https://api.deepseek.com
Model：deepseek-flash
API Key：自己的 DeepSeek API Key
```

当前 `OpenAIService.swift` 会在配置后追加 `/chat/completions`，因此不要把完整的 `/chat/completions` 路径再填进 Base URL。对本地服务通常需要保留 `/v1`，不能机械套用同一个地址。[OV7] [L1]

这是一条值得先测试的兼容路线，**不代表 OpenVision 的全部原生工具和默认请求参数已与 DeepSeek 实测兼容**。第一次请求关闭工具，先测最小文本，再加图片、流式输出和工具。

### 8.3 与眼镜无关的最小 API 测试

先在 Mac 上验证账号和接口，避免把模型错误误认为蓝牙问题。以下脚本需要本机环境变量 `DEEPSEEK_API_KEY`，不要把真实密钥写入仓库或发送给他人。

```bash
# 在 bash 中执行；先以安全方式设置本机的 DEEPSEEK_API_KEY。
: "${DEEPSEEK_API_KEY:?请先设置 DEEPSEEK_API_KEY}"

curl --fail-with-body --silent --show-error \
  --connect-timeout 10 --max-time 60 \
  https://api.deepseek.com/chat/completions \
  -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
  -H 'Content-Type: application/json' \
  --data '{
    "model": "deepseek-flash",
    "messages": [{"role": "user", "content": "请用一句中文确认接口已连接。"}],
    "thinking": {"type": "disabled"},
    "stream": false
  }'
```

这是最小网络验证，不是正式语音客户端。正式 App 要检查 HTTP 状态、解析错误对象、支持取消，并避免盲目重试造成重复消费。接口结构参考官方首次调用和思考模式文档。[D1] [D4]

### 8.4 图片请求

Chat Completions 的图片消息可采用以下结构；把占位内容替换为实际图片的 Base64，且 MIME 类型与图片内容一致：[D3]

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "请读出画面中的英文，并简短翻译成中文。"},
    {
      "type": "image_url",
      "image_url": {"url": "data:image/jpeg;base64,REPLACE_WITH_BASE64"}
    }
  ]
}
```

建议在 App 中设置图片大小上限、拍摄时间和来源标记。读不清就提示重新拍摄，不要让模型猜小字；不要无提示复用一分钟前的旧帧。

### 8.5 语音链路

```text
眼镜麦克风 → 手机识别 → DeepSeek 文字／图片请求
→ 最终回答文字 → 本地朗读 → 眼镜扬声器
```

不要把“模型支持图片”推导成“同一接口支持原始音频和视频”。本项目的普通模型路径统一先转写；原生实时音频作为独立能力实现。

<a id="s9"></a>
## 9. ChatGPT 订阅接入：单独做授权验证

### 9.1 三种方式必须区分

| 方式 | 状态与建议 |
|---|---|
| OpenVision 自带订阅登录 | 项目发布说明明确标注使用非公开的 Codex 集成面；可能变化，并可能影响同账号其他会话。不作为长期稳定基础。[OV11] |
| 官方 Sign in with ChatGPT 计划使用 | 当前有面向开源、本地托管应用的官方文档；仍需检查账号、工作区、地区和应用适用范围。[O1] |
| 普通 OpenAI API Key | 正式独立计费路径；不要认为拥有 ChatGPT 订阅就自动有 API 额度。[O6] |

**这里不承诺你的订阅一定适用。**能成功登录也不等于有计划使用权限；官方要求检查返回的 `chatgpt.tokens.use.direct` 等授权结果，并有用户不符合条件、地区和额度错误。[O5]

### 9.2 推荐的开发顺序

先做一个小型官方授权验证，而不是立即把现有登录代码大改：

```text
确认应用与账号适用范围
→ 按官方流程注册和授权
→ 验证回调、身份与权限
→ 安全保存凭据
→ 取得当前账号可用模型
→ 完成一次最小 Responses 请求
→ 测试取消授权、Token 刷新、额度错误
→ 再接到眼镜的模型适配层
```

OAuth 要使用官方规定的注册身份、回调、PKCE、state 与 nonce 等机制；不要提取网页 Cookie、复用其他客户端身份或让用户手动粘贴高权限登录凭据。原生 iOS 回调是否适配当前流程，必须单独验证，不能因为桌面例子可用就直接视为已支持。[O2]

官方文档中的开源／本地托管适用范围不能自动扩展为收费或远程托管产品；后一类应按官方接入意向流程确认。[O1]

### 9.3 推理接口要点

当前官方计划使用文档指定：使用 OAuth Access Token 调用 `https://api.openai.com/v1/responses`，先取当前账号模型列表，再使用返回的可选模型标识。**不应改用 ChatGPT 网页的 `backend-api` 私有路径。**[O3]

当前 HTTP 路径要求 `store: false`、`stream: true`，且需要自行携带必要历史；部分普通 Responses 参数在此路径不支持。文字和图片需与模型能力匹配，原始音频／视频和转写 API 不属于这条计划使用路径。[O4]

因此本项目的适配方式是：

```text
本地转写 + 可选照片 → 获准的 ChatGPT Responses 请求
→ 解析答案文字 → 本地朗读
```

### 9.4 仅在完成正式授权后使用的请求结构示例

下面是 HTTP 请求体结构，不包含 OAuth 实现；`MODEL_FROM_ACCOUNT_CATALOG` 必须替换成该账号实际可用的模型。不要把它复制到普通 Chat Completions 客户端。[O3] [O4]

```json
{
  "model": "MODEL_FROM_ACCOUNT_CATALOG",
  "store": false,
  "stream": true,
  "instructions": "请作为语音助手回答，先给结论，尽量简短。",
  "input": [
    {
      "role": "user",
      "content": [{"type": "input_text", "text": "请用一句话介绍你的用途。"}]
    }
  ]
}
```

### 9.5 必须实现的异常策略

| 情况 | 建议行为 |
|---|---|
| 只有身份登录、没有计划权限 | 显示“已登录，但未获准使用计划”，不继续推理 |
| 用户／工作区不符合资格 | 说明限制，停止循环重新登录 |
| 额度不足 | 暂停请求，允许用户主动选择其他后端 |
| 临时不可用 | 有上限的退避重试；保留登录凭据 |
| 用户取消授权或退出 | 清理对应会话，不影响其他后端 |

官方有这些类别的错误说明，但具体处理须保留实际状态码、错误码和请求 ID，不要仅凭 HTTP 429 就猜测全部订阅额度已耗尽。[O5]

<a id="s10"></a>
## 10. 本地模型：先用现有 M4 Mac 验证

### 10.1 两种“本地”不是同一回事

| 方案 | 数据处理位置 | 主要代价 |
|---|---|---|
| iPhone 端模型 | 手机本机 | 占用手机内存、存储、电量，需要设备和模型兼容性测试 |
| Mac／私有服务器模型 | 从手机发送至自己的机器 | 依赖网络、机器在线和网关；不是“数据从不离开手机” |

OpenVision 已有手机端 MLX 路线；底层相关运行库可参考 MLX Swift LM。你希望“包装一个接口给眼镜调用”，更适合先验证第二种方式。[OV1] [L4]

对于 M4、48GB 内存，建议从较小的量化文本模型和单独的视觉模型开始测，不直接追求能装下的最大模型。**这里不提供未经实测的 Token／秒、续航或模型规模保证。**

### 10.2 Ollama 作为第一种服务实现

Ollama 提供 OpenAI 兼容接口；默认本地服务地址通常为 `127.0.0.1:11434`。本地兼容接口要求客户端填写的 API Key 可能只是占位值，Ollama 本身会忽略它，因此它不是安全认证。[L1] [L2]

在官方安装方式完成后，先检查：

```bash
ollama list
curl --fail-with-body --silent --show-error \
  --connect-timeout 5 --max-time 15 \
  http://127.0.0.1:11434/v1/models
```

实际推理示例：把 `YOUR_INSTALLED_MODEL` 改成 `ollama list` 中已安装的本地模型名称。

```bash
curl --fail-with-body --silent --show-error \
  --connect-timeout 5 --max-time 120 \
  http://127.0.0.1:11434/v1/chat/completions \
  -H 'Content-Type: application/json' \
  --data '{
    "model": "YOUR_INSTALLED_MODEL",
    "messages": [{"role": "user", "content": "用一句话说明你运行在本地。"}],
    "stream": false
  }'
```

上面的回答不能证明实际离线；还要检查所选模型不是云端模型、日志和出站网络。

### 10.3 明确禁用云端回退

Ollama 当前提供 `OLLAMA_NO_CLOUD=1` 或配置文件关闭云端功能的方式，修改后需要重启服务。[L2]

例如，确认没有另一个 Ollama 实例占用端口后，可以在一个单独终端以前台方式运行：

```bash
OLLAMA_HOST=127.0.0.1:11434 OLLAMA_NO_CLOUD=1 ollama serve
```

**这只管理该 Ollama 进程，不会自动阻止手机 App 的云端语音识别、网络搜索或第三方 TTS。**整条链路仍要检查。

### 10.4 手机怎样访问 Mac

手机中的 `localhost` 指手机，不是 Mac。推荐结构：

```text
iPhone → 仅授权设备可访问的 HTTPS 私有网关
       → Mac 本机 127.0.0.1:11434
```

开发阶段可以在受控的家庭局域网做连通性测试；正式常用时增加认证、访问控制和加密。不要把无认证的 11434 端口直接映射到公网。

建议的网关责任：验证设备 Token、限制模型与路由、限制图片尺寸、设置超时和并发上限、日志脱敏，以及防止客户端指定任意外部 URL。

iOS 侧还需检查本地网络权限和传输安全配置。调试 HTTP 时只做有范围的开发例外，不把全局关闭传输安全当长期方案；当前应用配置入口可参考 `Info.plist`。[OV8]

### 10.5 看图与普通聊天分开验收

纯文本模型不能因为接口变成本地地址就理解图片。选择支持视觉的模型，并确认模型服务接受的图像格式；Ollama 自有 `/api/chat` 与 OpenAI 兼容接口的图片字段也不能混写。[L3] [L1]

建议统一保存以下实测指标：

```text
模型与量化版本 / 是否支持图片
首次加载耗时 / 首段答案延迟 / 完整回答耗时
内存占用 / 手机发热 / 连续使用稳定性
中文识别质量 / 图片小字识别质量
网络断开和 Mac 休眠时的错误表现
```

### 10.6 语音识别的本地候选

可先使用系统提供的设备端识别，再评估 `whisper.cpp` 或 Argmax 的 Swift 语音组件。原 WhisperKit 仓库目前跳转到 `argmaxinc/argmax-oss-swift`；使用时检查当前模块和许可证。[L5] [L6]

Apple 的设备端识别请求是否生效，依赖相应识别器是否支持该语言与设备端能力。需要检查 `supportsOnDeviceRecognition`，并在离线模式要求 `requiresOnDeviceRecognition`；不支持就明确提示，不能偷偷转云端。[A5] [A6]

<a id="s11"></a>
## 11. 音频、相机与后台运行：比模型接口更容易出问题

### 11.1 先确认输入设备

DAT 的相机连接成功，不证明录音来自眼镜。iOS 蓝牙 HFP 输入输出需要通过音频会话正确配置和检查；选择 HFP 输入也会影响对应输出路由。[A3]

建议调试页展示：当前输入和输出设备、采样率、是否录音、是否朗读、相机状态和最后一帧时间。对系统路由变化、来电和其他音频中断，应重新检查实际路由，而不是只在启动时设一次。[A4]

可用的人工测试：把手机放远，在同样环境下对着眼镜正常说话，比较实际录音；再摘下眼镜重复测试。不要以“有转写文字”作为唯一证据。

### 11.2 SDK 音频接口与蓝牙音频不是一条路

Meta DAT 1.0 的相机音频流、设备端转写等新接口带有实验标记。它们可以作为研究分支，但第一版可先保持独立的手机音频路由，避免为了新功能同时升级整个设备 SDK。[M2]

### 11.3 朗读时避免自己触发自己

建议会话状态机：

```text
idle → listening → transcribing → capturing_if_needed
     → requesting → speaking → idle

任意状态 → cancelling → idle
任意状态 → recoverable_error → 用户可见提示
```

设计上使用会话 ID、请求 ID 和取消令牌。用户说“停止”后，取消请求、停止语音队列，并丢弃旧请求迟到的回调。不要只停止播放器，却让旧请求继续把下一段文字入队。

全双工、回声消除和可打断朗读单独测试；不要把“不断重启识别器”当成稳定的唤醒方案。

### 11.4 锁屏不是只勾选一个后台选项

同款设备的问题记录明确涉及：原始视频流在进入后台／锁屏时暂停，而压缩流需要不同的处理。官方 SDK 文档也区分 `.raw` 和 `.hvc1`。这意味着视频编解码、会话生命周期和后台权限要一起验证，不能宣称某个勾选项能保证全天运行。[OV12] [M3]

第一版建议仅承诺已测试的前台问答；后台音频、后台相机、免手唤起分成三个独立验收项目。

### 11.5 相机取帧和发送频率分开

相机输出帧率与向模型发送图片的频率不是一回事。即使相机持续出帧，也不需要每帧上传。

建议先按需取新帧；连续视觉阶段再加入采样、内容变化检测、预算限制和明显的开始／停止状态。分辨率与压缩参数属于调优项，不在首次连接时同时修改。

<a id="s12"></a>
## 12. 可交给开发 Agent 的任务拆分

以下全部是建议开发任务，不是宣称仓库已有对应实现。每项任务完成后提交独立 commit，并记录验证方法；不要一次升级 SDK、重构音频和改模型协议。

| 编号 | 优先级 | 任务 | 完成标准 |
|---|---|---|---|
| T01 | P0 | 固定上游版本、环境和依赖 | 能说明准确 commit、工具链与 SDK；原版可构建 |
| T02 | P0 | 眼镜注册、设备发现、相机与音频验收 | 真机完成一张新图、一次眼镜录音和一次眼镜播放 |
| T03 | P0 | 建立调试状态页 | 可见设备、授权、音频路由、最后帧时间、请求状态 |
| T04 | P1 | DeepSeek 最小文字问答 | 禁用工具时成功；错误 Key 和断网有正确提示 |
| T05 | P1 | DeepSeek 单张图片问答 | 发送新照片；不支持图片的后端拒绝该功能 |
| T06 | P1 | 多模型配置档和凭据隔离 | 切换后不泄露旧服务凭据，不默认转发旧图片 |
| T07 | P1 | 官方 ChatGPT 授权验证 | 记录实际权限、模型列表和最小推理结果；失败不改走私有接口 |
| T08 | P1 | Mac 本地模型接口 | 本机请求与手机访问均成功；机器离线时清晰报错 |
| T09 | P1 | 可取消请求和朗读 | 停止后无旧回调继续朗读；不会重复执行工具 |
| T10 | P2 | 语音端侧模式和离线验证 | 识别、模型、朗读及工具均符合所选数据策略 |
| T11 | P2 | 后台／锁屏／重连 | 分模式记录结果，不将前台成功外推为后台成功 |
| T12 | P2 | 安全工具调用 | 只读工具先行；写入和高风险动作有独立确认 |

### 12.1 每个任务的交付格式

```text
修改目标：
涉及文件：
依据的官方文档及版本：
修改内容：
自动测试：命令与结果
真机测试：设备、系统、步骤与结果
未测试部分：
已知限制：
回滚方式：
下一项任务：
```

**硬性规则：** 编译成功不等于真机成功；模拟数据通过不等于蓝牙链路通过；第三方项目写“支持”不等于本设备已验收。

### 12.2 建议的仓库补充目录

```text
docs/
  environment.md           # 实际环境与版本
  architecture-diy.md      # 本项目自己的设计
  provider-contracts.md    # 每个模型后端的能力和协议差异
  device-test-results.md   # 真机测试证据
  privacy-dataflow.md      # 哪些数据离开手机，发给谁
  known-issues.md          # 已知限制与复现步骤
  source-index.md          # 本文参考资料及核对日期
config/
  profiles.example.json   # 仅示例，不含凭据
```

不要提交真实录音、私人照片、登录 Token、诊断文件中的身份信息或含凭据的网络抓包。

<a id="s13"></a>
## 13. 验收清单

建议逐项打勾并写入实测结果，不能仅把这份表当功能宣传。

### 13.1 基础功能

- [ ] iPhone 真机可以启动开发版 App；签名有效。
- [ ] Meta AI App 中原生眼镜功能正常，第三方 App 注册状态正确。
- [ ] App 能发现这副 Blayzer，而不是仅显示系统蓝牙已配对。
- [ ] 图片确实来自眼镜，带有可检查的新鲜度。
- [ ] 录音确实来自眼镜麦克风，答案从眼镜播放。
- [ ] 手机独立模式和眼镜模式显示不同的输入来源。

### 13.2 后端与计费

- [ ] DeepSeek 文字、图片分别测试，最终回答能够朗读。
- [ ] ChatGPT 订阅测试确认了实际授权范围，而不只是网页登录成功。
- [ ] 本地模型名称与安装清单一致；图片模型单独验证。
- [ ] 模型不支持某项能力时，界面禁用或明确解释。
- [ ] 订阅额度不足不会自动切到按量付费 API。
- [ ] 失败请求不进行无限重试；工具调用有防重复机制。

### 13.3 生命周期

- [ ] 持续使用一段时间后，记录延迟、发热、电量和错误。
- [ ] 锁屏、回前台、电话中断、切换蓝牙输出分别测试。
- [ ] 摘戴眼镜、折叠镜腿、断线重连后的状态正确。
- [ ] Mac 休眠、服务重启、Wi-Fi 切移动网络后不会一直转圈。
- [ ] 停止回答后不再继续朗读旧内容。
- [ ] 关闭当前会话后，相机和录音资源确实释放。

### 13.4 隐私与离线

- [ ] 界面能说明当前数据处理位置和接收服务。
- [ ] 未授权时不会拍照或录音；不尝试绕过硬件录制指示。
- [ ] 开启严格本地模式后，识别、推理、朗读和工具没有云端回退。
- [ ] 断开互联网、保留必要局域网后仍能完成承诺的本地功能。
- [ ] 冷启动、手机重启、眼镜重启后重新测试，而不只测已有会话。
- [ ] 日志无密钥、原始音频、Base64 图片和不必要的私人对话。
- [ ] 删除历史、删除凭据、退出账号的行为符合界面说明。

### 13.5 中国使用场景

分别测试“已配对且已授权的日常使用”和“重启、重新注册、授权失效后的恢复”。切换 DeepSeek 只改变模型后端，**不证明 Meta 配对、设备注册和授权恢复在当地网络都可用**。这些属于尚需实际网络与设备验证的边界。

<a id="s14"></a>
## 14. 故障排查速查表

| 现象 | 优先检查 | 不建议直接做的事 |
|---|---|---|
| 编译报旧 SDK 类型不存在 | 实际 DAT 锁定版本与调用代码是否匹配 | 让 AI 猜一个旧构造函数硬塞进去 |
| 已注册但设备数量为 0 | SDK 是否支持该硬件；固件、注册授权、设备状态 | 先怀疑模型 API Key |
| `addCamera` 返回空 | 会话是否真正进入 started；相机能力和权限 | 只增加无穷重试 |
| App 配置看似正确仍不能开相机 | Team ID、Camera 权限、重新注册、眼镜端组件安装 | 只改手机端一行代码 |
| 开始视频后相册没有文件 | 是预览流还是主动录像；是否真正启动录制与保存 | 认为所有流都会自动保存 |
| 锁屏后视频停了 | 当前编码、前后台生命周期、SDK 限制 | 宣称开启 Background Modes 就一定解决 |
| 听得到声音但识别不到 | 实际麦克风来源、HFP 路由、识别权限和语言资源 | 根据扬声器连接推断麦克风也正常 |
| Base URL 配好却 404 | 路径是否被重复追加；是否缺少 `/v1` | 同时修改模型名、SDK 和网络配置 |
| 显示已连接但提问失败 | “连接”是否只是本地配置检查；真实 HTTP 请求结果 | 认为保存 Key 就等于认证成功 |
| DeepSeek 很慢 | 是否默认启用思考；图片大小；首字与整段延迟 | 先归咎于眼镜蓝牙 |
| 本地接口在 Mac 成功、手机失败 | localhost、监听地址、防火墙、局域网权限、网关认证 | 直接裸露端口到公网 |
| 本地模式仍有网络请求 | 识别、朗读、搜索工具、云端模型选项和 SDK 遥测 | 只检查大模型地址 |
| ChatGPT 已登录但 403／429 | 计划权限、资格、地区、错误码及使用限制 | 循环 OAuth 或悄悄改用付费 Key |
| 语音助手读出自己说的话 | TTS 与识别并发、回声、会话状态和取消处理 | 仅把识别重启间隔缩短 |
| 运行几天后开发版不能打开 | 免费签名描述文件期限或实际签名状态 | 购买来源不明的企业证书 |
| 增加文件后找不到类型 | XcodeGen 工程是否重新生成 | 反复清缓存但不检查工程输入 |

设备和源码相关依据见 [OV6]、[OV7]、[OV10]、[OV12]；模型与认证依据见 [D4]、[O5]；本地和签名依据见 [L2]、[A1]。表中的排查顺序是工程建议，不是唯一可能原因。

<a id="s15"></a>
## 15. 后续好玩的 DIY 方向

### 15.1 随口记录与内容整理

说出想法后，保存转写和时间，再由模型整理成选题、待办或 Markdown。建议默认不保留原始录音，只有主动选择时才保存。

适合先做，因为不需要持续相机和全双工音频；产物也容易检查。

### 15.2 视觉翻译和阅读辅助

按需拍摄标牌、菜单或资料，朗读原文或译文。给对方看的内容放手机屏幕，不假设这副眼镜有镜内字幕。

遇到小字、模糊画面和关键数字时要求重新拍摄或人工核对；不把模型读数当作医疗、驾驶或安全判断的唯一依据。

### 15.3 语音查询开发任务

先开放“读构建结果、读测试报告、创建待办草稿”等功能。再考虑经确认启动测试或提交开发任务。

建议工具接口接收结构化参数，而不是把转写直接拼成 Shell 命令。模型只能提出工具请求，由执行层检查身份、权限和参数。

### 15.4 家庭设备控制

借鉴 Hey Casa 的 Home Assistant 路线，从查询设备状态和控制普通灯具开始。门锁、监控、支付类操作不按同一低风险权限放行。[P4]

### 15.5 远程第一视角协助

借鉴 VisionClaw 的视觉分享与实时交互结构，但要独立处理身份认证、会话过期和录制提示，不把服务地址或访问码公开给无关人员。[P1]

### 15.6 工具权限建议

| 等级 | 示例 | 默认策略 |
|---|---|---|
| 只读 | 查任务状态、读文档 | 用户授权相应数据源后可执行 |
| 可撤销写入 | 建草稿、记笔记、开普通灯 | 明确反馈，可查看和撤销 |
| 高风险 | 发消息、删文件、合并或发布代码 | 执行前独立确认，参数可见 |
| 财务／生产关键操作 | 转账、交易、生产配置变更 | 第一版不开放 |

图像中文字、网页内容或工具返回值都可能包含诱导指令。应当把它们视为待分析的数据，不允许覆盖用户意图和工具权限。

<a id="s16"></a>
## 16. 自用、分享测试与公开发行

当前目标是**自己使用的 DIY App**，不需要把 App Store 上架作为前置条件。OpenVision 当前安装说明没有提供面向普通用户直接下载的 App Store／TestFlight／IPA 分发路径，主要方案仍是自己编译。[OV2]

将来分享给别人时，分别检查三层资格：

| 层次 | 要确认什么 |
|---|---|
| Apple 分发 | 开发签名、测试分发或商店分发的适用流程 |
| Meta 设备接入 | 开发预览、测试渠道、公开发行资格及实验性接口限制 |
| 模型服务 | OAuth／API 的适用范围，是否允许对应发行和收费方式 |

Meta SDK 的当前预览状态和实验性限制见官方仓库及 CHANGELOG；不能用“苹果通过了审核”代替 Meta 的接入资格。[M1] [M2]

官方 ChatGPT 计划使用文档同样区分开源本地应用与付费／远程托管应用。[O1]

### 16.1 本项目的成本管理建议

先不买新电脑，不先租 GPU，不先搭复杂代理层。优先用现有设备和一个正式模型接口验证核心体验。

为按量计费后端设置单次输出限制、图片尺寸限制、每小时请求上限及用户可见的消费记录。不要在调试阶段启用高频视频上传或无限重连推理。价格需要使用时重新核对，不在代码里长期硬编码旧单价。[D2]

### 16.2 Meta 遥测与“完全离线”的措辞

Meta SDK 官方仓库提供遥测 opt-out 配置说明。可以按所选 SDK 版本评估并配置，但它不等于移除 Meta App、账号、配对或全部网络依赖。[M1]

对用户界面建议使用准确表达：

```text
“本次模型推理在你的 Mac 上完成”
```

而不是未经全链路验证就写：

```text
“所有数据永远不会离开设备，完全不依赖任何在线服务”
```

<a id="s17"></a>
## 17. 可直接交给 Codex／Claude 的开发交接提示词

下面的提示词可以作为首次任务说明；请连同这份文档和实际仓库一起提供。不要只贴提示词而不给 Agent 查看源码。

````text
你现在协助我开发一个个人使用的 Meta 眼镜 DIY 配套 App。

目标硬件：Blayzer Optics Gen 2。
主路线：基于 rayl15/OpenVision 的 iOS 项目，优先最小改动。
目标后端：DeepSeek 正式 API、官方且获准的 ChatGPT 计划授权、Mac 本地模型。
手机型号与 iOS、眼镜固件等信息：先在 environment.md 标为待实测，不可编造。

开始前：
1. 阅读本技术指南。
2. 阅读当前 checkout 的 README、SETUP、project.yml、Config 模板和关键源码。
3. 阅读 Meta DAT 官方 AGENTS.md，并对照项目锁定的 SDK 版本。
4. 阅读 Blayzer 相关 Issue #55 和 v2.13.0 迁移说明。
5. 记录 git commit、依赖锁文件、Xcode、Swift 和构建状态。

第一轮只做：
A. 建立可复现的构建基线。
B. 说明眼镜注册、设备发现、相机和音频分别如何验证。
C. 检查配置与日志是否泄露凭据。
D. 给出后续 DeepSeek 最小文字请求的改动方案。
不要一次升级 Meta SDK、重构音频和加入全部模型后端。

实现约束：
- 不修改眼镜固件，不绕过权限或录制指示。
- 以真实源码和版本匹配的官方文档为依据，不编造 SDK 方法。
- 不把非官方 Codex／ChatGPT 私有后端当作长期稳定依赖。
- ChatGPT 计划授权必须独立验证资格、scope、模型列表和推理权限。
- 不默认切换数据接收方；不从订阅自动回退到付费 API。
- 本地模式不允许云端回退，语音识别与朗读也要检查。
- 密钥放 Keychain 或服务端安全存储，不提交源码、不打印日志。
- 接口失败使用有上限的重试；不自动重放可能有副作用的工具。
- 取消操作必须取消网络、语音队列和过期回调。
- 优先主动提问、单张图片、文字回答、本地朗读。
- 所有权限请求都有真实用途，不开启无关能力。

每轮输出：
- 修改文件与原因。
- 文档和版本依据。
- 实际执行的构建／测试命令和结果。
- 无设备或无凭据时未执行的测试。
- 已知限制、回滚方式和下一个最小任务。

没有运行过的测试不能写“通过”。
遇到需要真人完成的 Apple／Meta 授权，停在明确步骤，不模拟成功。
````

### 17.1 官方 Agent 文档入口

Meta 官方仓库提供 `AGENTS.md`，并在文档中列出面向模型的完整文档索引与文档 MCP 入口。它们适合帮助开发 Agent 查 API，但仍要按实际 SDK 版本过滤，不要让 `latest` 文档覆盖旧版本工程。[M3]

- [iOS AGENTS.md][M3]
- [DAT 文档入口][M4]
- 文档索引：`https://wearables.developer.meta.com/llms.txt?full=true`
- 文档 MCP：`https://mcp.developer.meta.com/wearables`

后两项是官方仓库列出的参考入口，本文没有代替你在本地开发工具中安装或验证 MCP 连接。

<a id="s18"></a>
## 18. 参考文档索引

以下链接按用途排列。标注 `main`／`latest` 的文档会变化；开始实施时应记录对应版本。技术结论以所引用的官方文档、源码或项目维护者记录为依据；工程路线、任务划分与验收标准为本文建议。

### 18.1 OpenVision：第一批必须阅读

| 编号 | 文档 | 建议阅读目的 |
|---|---|---|
| OV1 | [OpenVision 主仓库／README][OV1] | 确认项目定位与功能；不把 README 宣传当作真机验收。 |
| OV2 | [SETUP.md][OV2] | 安装、配置和排错；与工程版本有冲突时交叉核对。 |
| OV3 | [架构说明][OV3] | 定位设备、后端、音频、OAuth 和主会话模块。 |
| OV4 | [main 的 project.yml][OV4] | 检查真实最低系统、依赖和构建设置。 |
| OV4T | [v2.14.0 的 project.yml][OV4T] | 固定版本构建依据，不与 main 的后续变化混淆。 |
| OV5 | [Config.xcconfig.example][OV5] | Apple Team ID、Meta 凭据及回调配置模板。 |
| OV6 | [GlassesManager.swift][OV6] | 设备注册、权限、会话启动顺序与相机状态。 |
| OV7 | [OpenAIService.swift][OV7] | 兼容请求路径、配置检查、普通 API 与订阅分支。 |
| OV8 | [Info.plist][OV8] | 权限用途、URL Scheme、网络及后台相关配置入口。 |
| OV9 | [OpenVision.entitlements][OV9] | 签名能力及手机端模型内存设置。 |
| OV10 | [v2.13.0 发布说明][OV10] | 重点：新眼镜支持、信任链与迁移准备。 |
| OV11 | [v2.14.0 发布说明][OV11] | 重点：订阅接入警告、工具链及已知限制。 |
| OV12 | [Issue #55：Blayzer Gen 2 not recognized][OV12] | 与你同型号最直接相关的问题和修复记录。 |
| OV13 | [MIT LICENSE][OV13] | 修改和分发前核对许可要求。 |

### 18.2 Meta：设备 SDK 与官方示例

| 编号 | 文档 | 建议阅读目的 |
|---|---|---|
| M1 | [DAT iOS 官方仓库][M1] | 预览状态、集成方式、条款和遥测配置。 |
| M2 | [DAT iOS CHANGELOG][M2] | 升级前必读；区分稳定与 Experimental 功能。 |
| M3 | [DAT iOS AGENTS.md][M3] | 给开发 Agent 的类型、生命周期及 API 参考。 |
| M4 | [Wearables Developer Center 文档][M4] | 官方仓库指向的开发文档入口；部分内容可能要求登录。 |
| M5 | [DAT Android 官方仓库][M5] | Android 工程、分发依赖及配置说明。 |
| M6 | [Meta Cookbook：03_visionclaw][M6] | 轻量手机端拍照问答与网关架构。 |

### 18.3 OpenAI：订阅授权与正式推理接口

| 编号 | 文档 | 建议阅读目的 |
|---|---|---|
| O1 | [ChatGPT plan usage 概览][O1] | 先核对适用范围；不是所有订阅和应用都自动获准。 |
| O2 | [Registration and sign-in][O2] | 注册、OAuth、安全校验与回调流程。 |
| O3 | [Models and inference][O3] | 账号模型列表、公开 Responses 端点和推理方式。 |
| O4 | [Preview limitations][O4] | 请求字段、上下文及输入模态限制。 |
| O5 | [Errors and recovery][O5] | 资格、权限、地区、额度及恢复策略。 |
| O6 | [ChatGPT 与 API 的账单][O6] | 区分订阅与普通 API 费用。 |
| O7 | [ChatGPT 支持地区][O7] | 部署和旅行使用前核对，不把“海外”一概视为支持。 |

### 18.4 DeepSeek：接口与视觉

| 编号 | 文档 | 建议阅读目的 |
|---|---|---|
| D1 | [Your First API Call][D1] | 基础 URL、认证、模型别名与兼容调用。 |
| D2 | [Models & Pricing][D2] | 最新模型能力、版本映射和价格。 |
| D3 | [Vision][D3] | 图片输入字段、支持格式和限制。 |
| D4 | [Thinking Mode][D4] | 思考开关、参数及多轮／工具差异。 |

### 18.5 本地推理和语音组件

| 编号 | 文档 | 建议阅读目的 |
|---|---|---|
| L1 | [Ollama OpenAI compatibility][L1] | 兼容端点、支持范围和本地 API Key 行为。 |
| L2 | [Ollama FAQ][L2] | 监听地址、云端禁用、环境变量和运行诊断。 |
| L3 | [Ollama Vision][L3] | 本地视觉输入，区分原生与兼容协议。 |
| L4 | [MLX Swift LM][L4] | Swift 文本／视觉模型运行库。 |
| L5 | [whisper.cpp][L5] | 本地语音识别候选；按平台选择编译和模型。 |
| L6 | [Argmax OSS Swift（原 WhisperKit 入口）][L6] | Apple Silicon 语音组件，评估移动端识别。 |

### 18.6 Apple：签名、音频和设备端识别

| 编号 | 文档 | 建议阅读目的 |
|---|---|---|
| A1 | [Developer account overview][A1] | 免费 Personal Team、签名期限与会员能力。 |
| A2 | [Apple Developer App 中国区注册][A2] | 身份准备、注册方式和当前人民币年费。 |
| A3 | [AVAudioSession 蓝牙音频选项][A3] | 理解 HFP 输入输出行为；代码名称按所用 SDK 核对。 |
| A4 | [Responding to audio route changes][A4] | 处理蓝牙连接、断开及输出设备变化。 |
| A5 | [supportsOnDeviceRecognition][A5] | 检查当前识别器是否能在设备端工作。 |
| A6 | [requiresOnDeviceRecognition][A6] | 离线模式要求与能力限制。 |

### 18.7 其他 DIY 项目和硬件资料

| 编号 | 文档 | 建议阅读目的 |
|---|---|---|
| P1 | [Intent-Lab/VisionClaw][P1] | 实时语音、视觉及工具集成参考。 |
| P2 | [OpenGlasses／Avenkin][P2] | 多模型、语音和记忆架构参考。 |
| P3 | [OpenGlasses LICENSE][P3] | BSL 的非商用许可及商业限制。 |
| P4 | [Hey Casa][P4] | Android 眼镜与 Home Assistant 接入。 |
| H1 | [Blayzer Optics Gen 2 品牌产品页][H1] | 核对型号；最终设备信息以实际购买设备为准。 |

---

## 最后落到一个最小目标

**先让这副眼镜通过自己的 App 完成一次：看一张新照片 → 说一句问题 → DeepSeek 回答 → 眼镜朗读。**

成功后再接官方 ChatGPT 计划授权和本地模型。先把设备、权限、音频、请求和错误处理做可靠，再增加实时视频、免手唤起和工具调用。

> 本文不包含真实凭据、完整第三方源码或打包安装文件。公开文档已核对，但示例网络调用、手机安装和眼镜运行均需在你的环境中执行和验收。

[OV1]: https://github.com/rayl15/OpenVision
[OV2]: https://github.com/rayl15/OpenVision/blob/main/SETUP.md
[OV3]: https://github.com/rayl15/OpenVision/blob/main/docs/architecture.md
[OV4]: https://github.com/rayl15/OpenVision/blob/main/project.yml
[OV4T]: https://github.com/rayl15/OpenVision/blob/v2.14.0/project.yml
[OV5]: https://github.com/rayl15/OpenVision/blob/main/Config.xcconfig.example
[OV6]: https://github.com/rayl15/OpenVision/blob/main/OpenVision/Managers/GlassesManager.swift
[OV7]: https://github.com/rayl15/OpenVision/blob/main/OpenVision/Services/AIBackend/OpenAIService.swift
[OV8]: https://github.com/rayl15/OpenVision/blob/main/OpenVision/Resources/Info.plist
[OV9]: https://github.com/rayl15/OpenVision/blob/main/OpenVision/OpenVision.entitlements
[OV10]: https://github.com/rayl15/OpenVision/releases/tag/v2.13.0
[OV11]: https://github.com/rayl15/OpenVision/releases/tag/v2.14.0
[OV12]: https://github.com/rayl15/OpenVision/issues/55
[OV13]: https://github.com/rayl15/OpenVision/blob/main/LICENSE
[M1]: https://github.com/facebook/meta-wearables-dat-ios
[M2]: https://github.com/facebook/meta-wearables-dat-ios/blob/main/CHANGELOG.md
[M3]: https://github.com/facebook/meta-wearables-dat-ios/blob/main/AGENTS.md
[M4]: https://wearables.developer.meta.com/docs/develop/
[M5]: https://github.com/facebook/meta-wearables-dat-android
[M6]: https://github.com/meta-models/meta-model-cookbook/blob/main/03_use_cases/03_visionclaw/README.md
[O1]: https://developers.openai.com/siwc/token-sharing-open-source
[O2]: https://developers.openai.com/siwc/token-sharing-open-source/sign-in
[O3]: https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
[O4]: https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
[O5]: https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery
[O6]: https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform
[O7]: https://help.openai.com/en/articles/7947663-chatgpt-supported-countries
[D1]: https://api-docs.deepseek.com/
[D2]: https://api-docs.deepseek.com/quick_start/pricing/
[D3]: https://api-docs.deepseek.com/guides/vision/
[D4]: https://api-docs.deepseek.com/guides/thinking_mode/
[L1]: https://docs.ollama.com/api/openai-compatibility
[L2]: https://docs.ollama.com/faq
[L3]: https://docs.ollama.com/capabilities/vision
[L4]: https://github.com/ml-explore/mlx-swift-lm
[L5]: https://github.com/ggml-org/whisper.cpp
[L6]: https://github.com/argmaxinc/argmax-oss-swift
[A1]: https://developer.apple.com/help/account/basics/about-your-developer-account
[A2]: https://developer.apple.com/cn/help/account/membership/enrolling-in-the-app/
[A3]: https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetooth
[A4]: https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
[A5]: https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition
[A6]: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
[P1]: https://github.com/Intent-Lab/VisionClaw
[P2]: https://github.com/straff2002/OpenGlasses
[P3]: https://github.com/straff2002/OpenGlasses/blob/main/LICENSE
[P4]: https://github.com/locafra/hey-casa
[H1]: https://www.ray-ban.com/usa/electronics/RW7001ray-ban%20meta%20gen%202%20blayzer%20optics-black/8056262944554
