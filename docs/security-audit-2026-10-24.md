# 三个参考项目的安全与数据外发审计

审计日期：2026-10-24。范围：本地固定提交的源码静态审计，重点为 iOS App 的音频、图片、对话、密钥、日志与额外联网行为。

**后续范围确认：用户接受 Meta SDK 的官方采集，当前重点是 OpenVision 自己是否向作者服务器另行收集上报。** 对此已完成[专项复核](openvision-author-server-audit.md)：尚未发现作者私设回传端点。OV-01 保留为 SDK 行为说明，状态改为用户接受，不再作为要求移除 SDK 或关闭采集的前置条件；其他密钥、日志、搜索及设备标识问题仍需处理。

**最新实施决定：用户已阅读审计并选择保留 OpenVision 现有功能。** 下文保留原始发现与当时的整改建议供追溯；其中移除模块、裁剪功能的建议已被[保留功能的增量方案](openvision-development-plan.md)取代，不作为当前开发前置条件。

## 1. 结论

**推荐以 OpenVision 为二次开发基础，但必须先完成隐私裁剪和密钥修复，再接入真实对话。** 它的主项目采用 MIT，规模较小，已有眼镜连接、音频路由、朗读和会话界面，适合改造成中英泰翻译 App。

**“选择某个 AI 模型”不等于“数据只发给这个模型”。** 三份代码中确实存在模型以外的数据处理或网络路径：

- OpenVision 没有关闭 Meta SDK 的默认分析采集；语音识别没有强制端侧运行；搜索会把查询交给 Tavily / DuckDuckGo；模型请求还能携带近期对话、文档摘录与所附照片。
- OpenGlasses 显式关闭了 Meta 分析与崩溃采集，具备更多密钥和日志保护；但本地模型的联网搜索回退默认开启，唤醒识别不支持端侧时会回退到服务器，支持邮件也可以包含对话。
- Meta 官方仓库提供示例与接入资料，SDK 核心并非可完整审阅的源码。部分示例没有关闭默认采集，不能直接视作隐私配置模板。

**在已检查的应用代码和关键调用链中，未发现足以认定“偷偷把全部对话上传到作者服务器”的证据。这个结论不等于没有任何额外上传，也不构成“绝对安全”认证。** 未编译运行、未做真机抓包、未审阅全部依赖和 SDK 二进制，不能证明闭源组件或所有运行路径不会外发数据。

## 2. 下载版本与审计方法

| 项目 | 提交 | Git 跟踪文件 | 纳入词法扫描的文本文件 |
|---|---|---:|---:|
| OpenVision | `1d5d9203a36f76040947425a603eba57757eac75` | 241 | 204 |
| OpenGlasses / Avenkin | `e3b2dad823e1e038ea787748fee204eadbe8cb8e` | 3,559 | 2,920 |
| Meta DAT iOS | `bbae597cd1c748cd29b9375a1624a8d75b1c9e14` | 885 | 307 |

先盘点三仓库文件、URL 字面量、网络调用位置和疑似密钥位置，再人工追踪高风险路径：配置默认值 → 功能入口 → 收集的数据 → 请求构造 → 收件方 → 持久化/日志。重点细读 OpenVision，另两个项目按外发与安全控制路径核查；**没有逐行人工审阅全部文件**。

扫描覆盖 Swift、Objective-C/C/C++、配置、JSON、脚本及部分网页文件，单文件上限 4 MB；完整扩展名与限制记录在扫描摘要。大量行数来自 JSON 数据和第三方代码，不能当作人工审计覆盖率。URL 出现也可能只是注释、文档、测试或打开网页的链接。

- [源码版本与摘要](audit/2026-10-24/source-manifest.json)
- [URL 候选清单](audit/2026-10-24/endpoint-inventory.csv)：1,437 处，已去掉查询串、片段和 URL 用户信息；不是实际连接记录。
- [网络调用候选位置](audit/2026-10-24/network-call-sites.csv)：827 处，需结合调用上下文判断。
- [扫描范围与密钥候选位置](audit/2026-10-24/scan-summary.json)：5 处候选均核对为 OpenGlasses 的脱敏测试样本及对应扫描白名单，未据此认定真实密钥泄露。
- [可复现的只读扫描脚本](../scripts/audit_reference_sources.py)。未扫描 Git 完整历史，未使用任何用户密钥验证候选字符串。

证据链接指向固定提交的 GitHub 页面；对应文件也在 `references/`，可以离线打开。报告中的“默认”指源码默认配置，已有用户设置可能覆盖它。

## 3. OpenVision：主要发现

优先级含义：P0 为 LensMate 接入敏感数据前必须处理；P1 为首个可用版本必须处理；P2 为扩展功能前处理。这是面向本项目的修复顺序，不是 CVSS 漏洞评分。

### OV-01 · 用户已接受：Meta SDK 的分析与崩溃采集没有关闭

`project.yml` 锁定 Meta SDK 0.9.0；App 初始化会调用 `Wearables.configure()`。`Info.plist` 的 MWDAT 配置中没有 `Analytics.OptOut` 和 `CrashReporting.OptOut`。

核对了 **0.9.0 对应提交的官方说明**：缺少开关时分析默认开启，SDK 崩溃捕获也默认开启。前者涉及 Meta 设备与 App 交互信息；后者涉及 SDK 崩溃信息。无法仅凭公开源码列全上传字段，也不能断言它会上传完整音频或对话。关闭 OpenVision 自己的 Telemetry 不会自动关闭 Meta 的采集。

证据：[依赖版本](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/project.yml#L114)、[App 初始化](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/App/OpenVisionApp.swift#L34)、[Info.plist](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Resources/Info.plist)、[本地保存的 SDK 0.9.0 官方说明](audit/2026-10-24/sdk-0.9.0/README.md)。

当前处理：按用户明确接受的范围保留 Meta SDK 及官方采集；不因本项强制移除 SDK。后续联网观察将 Meta 官方行为与 OpenVision 自有请求分开归因。若以后选择退出采集，可以显式设置两个 OptOut；这些开关也不等于阻断设备注册、认证、Meta AI App 或眼镜自身的全部网络行为。

### OV-02 · P0：Keychain 失败时把密钥写回普通配置文件

`SettingsManager.performSave()` 先尝试 Keychain；失败的字段进入 `secretsKeptInFile`，不可读期间新输入的密钥也可能保留。`SettingsSecrets.forFile()` 让这些字段留在序列化对象中，最终写入 `Documents/settings.json`。

这是一条明确可达的代码路径，涉及模型 API Key、网关认证信息、搜索和遥测凭据。**这是本地保存风险，不是已经发现的网络外传。** 文件仍受 iOS 沙盒和系统数据保护，但不再具有原本预期的 Keychain 隔离；设备备份、调试导出或后续误共享的风险因此扩大。

证据：[保存与失败处理](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Managers/SettingsManager.swift#L170)、[保留密钥的序列化逻辑](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Managers/SettingsSecrets.swift#L50)。

修复：写入失败时停止保存密钥并明确提示，只在内存中暂存；配置文件永远不带密钥。个人版采用适合后台音频的 `AfterFirstUnlockThisDeviceOnly`；正式分发采用自有服务端保管长期 Key，按接口能力使用短期凭据或受控代理。

### OV-03 · P0：语音识别不能保证音频只发给所选模型

`VoiceCommandService` 使用 Apple `SFSpeechRecognizer`，当前固定 `en-US`；配置识别请求时设置 partial results、taskHint 和唤醒词偏置，但没有强制 `requiresOnDeviceRecognition` 或检查端侧支持。`wakeWordEnabled` 默认 true；在语音监听启动后，音频会进入该识别请求。**这不是说 App 安装后无需权限就会自行偷录。**

Apple 说明要求端侧识别需设置相应属性并具备支持，否则不能保证音频留在设备。因此即便 LLM 选择本地模型，语音前端仍可能交由 Apple 服务处理。当前英文识别入口也不适合直接承诺中英泰三语。

证据：[识别请求配置](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Voice/VoiceCommandService.swift#L291)、[默认唤醒设置](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Models/AppSettings.swift#L265)、[Apple 端侧识别属性说明](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)。

修复：MVP 使用手动开始/停止，音频直接进入选定的阿里云 ASR，不启动这条 Apple Speech 监听链。以后做唤醒词时使用明确端侧的实现，不支持时禁用，不能静默改走云端。

### OV-04 · P0：搜索、历史和文档会扩大外发内容范围

`CloudChat` 默认提供 `web_search` 及本地工具，模型返回工具调用后 App 会执行，再把结果放回下一轮云端请求。搜索优先使用已配置的 Tavily，之后回退 DuckDuckGo；后者不要求 API Key。查询内容可能带有用户问题及上下文信息，不只是抽象关键词。

同时，云端请求会加入近期对话，文档聚焦模式会加入相关摘录，附图会编码进请求。`ConversationContext` 保留最多 8 条近期消息。这些是功能设计，不能单凭存在认定为恶意；但“我只让它翻译这一句话”时，不应连带发送历史、文档或照片。

证据：[请求上下文及自动工具循环](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/AIBackend/CloudChat.swift#L43)、[工具执行](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/AIBackend/CloudChat.swift#L117)、[搜索服务及回退](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Web/WebSearchService.swift#L16)、[近期上下文](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/LocalAgent/ConversationContext.swift#L20)。

修复：翻译建立独立请求类型，仅允许当前稳定短句、语言参数和受限翻译上下文；不复用通用助手的 `CloudChat`；移除搜索、工具、记忆、文档聚焦和自动视觉上传。

### OV-05 · P1：日志与本地会话保留了敏感正文

`VoiceCommandService` 多处直接 `print` 识别文本，Gemini/OpenClaw 分支也记录用户文本或回复片段；这些日志没有全部限制在 DEBUG 构建。`ConversationManager` 自动保存会话 JSON，消息模型还可含 `photoData`。未见该存储路径实施应用层加密或显式排除备份。

日志本身不等于自动上传，但一旦进入支持包、开发调试或系统诊断，正文会进入更广的可见范围。图片和历史的长期留存也超出一次翻译的必要范围。

证据：[识别正文日志](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Voice/VoiceCommandService.swift#L529)、[OpenClaw 日志](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/OpenClaw/OpenClawService.swift#L419)、[会话存储](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Managers/ConversationManager.swift#L169)、[消息图片字段](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Models/Conversation.swift#L63)。

修复：只记录事件类型、耗时、状态码和字节数；不记录原文、译文、图片、Key 或完整带参 URL。会话默认仅驻留内存，用户主动保存才写文件，并提供清除、保留期限与备份策略。原项目 POV 录制有明确操作入口，不据此认定为默认录制；保存至 Photos 后还可能受用户系统照片同步设置影响。

### OV-06 · P1：允许宽泛明文网络，且部分凭据在 URL 参数里

Info.plist 开启全局 `NSAllowsArbitraryLoads`，加上可自定义的服务地址，会扩大误用 HTTP/WS 的风险。部分协议把认证值放进 WebSocket URL 查询参数，可能被代理、错误日志或抓包记录；不等同于已泄露，也不代表所有服务支持直接改为请求头。

证据：[ATS 配置](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Resources/Info.plist#L139)、[网关认证 URL 构造](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/OpenClaw/OpenClawService.swift#L332)。

修复：发行版只允许 HTTPS/WSS，精确限制域名、端口与路径；检查重定向的新目的地，不向其他域名转发认证头。旧网关和不使用的云服务全部移出翻译构建目标。

### OV-07 · P2：依赖和模型下载仍需供应链核查

项目包含第三方 Swift 包、PrismML 的 MLX 分支依赖及部分版本范围依赖。Kokoro 模型从 Hugging Face `resolve/main` 按需下载，所查下载函数检查 HTTP 成功，但未校验固定内容摘要。当前原始源码下载不包含完整依赖解析结果，不能据此宣布依赖没有漏洞。

证据：[依赖定义](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/project.yml#L124)、[Kokoro 下载](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/TTS/KokoroTTSService.swift#L384)。

修复：MVP 移除 MLX/Kokoro/模型下载链，保留必要音频实现；对剩余依赖锁定 revision、生成依赖及许可清单，在隔离构建中复核下载内容。下载权重通常暴露 IP 和所请求资源，不能将它直接写成“上传了对话”。

### 已确认的正向控制

OpenVision 自有 Influx Telemetry 默认关闭，地址默认为空；只有打开开关并配置地址才建立远端 sink。所查 payload 为设备/性能/耗时/token 数/事件等指标，已核对事件调用为固定名称，未见把正文直接装进该 payload。地址由用户填写，未发现硬编码作者遥测收集地址。

OAuth 回调监听限制在 loopback，并校验 state；不据此认定为对局域网开放的后门。上述保护不抵消前述 SDK、Speech、搜索和日志问题。

证据：[Telemetry 默认值](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Models/AppSettings.swift#L283)、[sink 配置条件](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Telemetry/MetricsCollector%2BConfiguration.swift)、[指标 payload](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Telemetry/InfluxMetricsSink.swift)、[OAuth 回调](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/OAuth/OAuthLoopbackServer.swift#L38)。

### 定向补查：剪贴板与设备信息

针对用户关于剪贴板读取、设备信息采集和上报的追问，重新检查同一固定提交的应用源码。以下结论不涵盖尚未解析的外部依赖和闭源 SDK，也不是运行时抓包结果。

**剪贴板：没有发现主动读取现有剪贴板内容的代码。** 唯一直接使用 `UIPasteboard` 的应用实现为 `ClipboardTool.execute()` 中的 `UIPasteboard.general.string = text`，它把工具参数写入剪贴板。Apple Foundation 的同名工具转调这份实现。该函数还会返回待复制文本最多 60 字符的预览作为工具结果；云端工具循环可能把此结果返回模型，但预览来自传入的 `text`，不是从用户原有剪贴板读取的内容。搜索也未发现 `UIPasteControl`、`PasteButton` 或剪贴板读取/检测入口。不能仅因代码出现 clipboard 字样就认定为窃取剪贴板。

证据：[剪贴板写入与预览](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/NativeTools/ClipboardTool.swift#L15)、[Apple 工具转调](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/AppleFoundation/AppleNativeTools.swift#L130)、[云端工具结果回传](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/AIBackend/CloudChat.swift#L80)。

**设备性能信息：有采集与条件上报实现，但自有遥测不是默认外发。** 采集字段包括进程内存占用、可用/总内存、进程 CPU、热状态、电量及低电量模式。打开 Telemetry 页面会开始本地采样；只有 `telemetryEnabled == true` 且设置了目标地址，才安装远端 sink。上报包括这些设备状态，以及模型/后端/TTS 名称、耗时、token 数、事件和时间戳；目的地是用户配置的 Influx `/api/v2/write`。设备标签默认只是字符串 `iphone`，不是自动读取的手机个人名称。开启后设置会持久化，下次启动恢复上报。

证据：[设备字段](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Telemetry/SystemMetrics.swift#L18)、[页面本地采样](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Views/Settings/TelemetrySettingsView.swift#L22)、[外发字段](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Telemetry/InfluxMetricsSink.swift#L64)。Meta SDK 默认分析是另一条路径，不能被这个关闭状态覆盖，见 OV-01。

**OV-08 · P1：Hermes API Key 模式会发送 IDFV。** `HermesService.sessionKey` 读取 `UIDevice.current.identifierForVendor`，拼成 `openvision:glasses:<IDFV>`；API Key 模式发送聊天请求时，将其放入 `X-Hermes-Session-Key` 请求头。接收方为 `settings.hermesServerURL` 指定的服务器，该地址默认空，App 默认后端也不是 Hermes。没有证据表明这条路径默认发往作者服务器，但它确实会将设备标识交给配置的服务端，可用于关联多次请求。用户名/密码的 WebSocket 分支不经过这段 HTTP 请求构造，不能一概说所有 Hermes 模式都发送该标识。

证据：[请求入口与配置目的地](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/AIBackend/HermesService.swift#L64)、[标识与请求头](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/AIBackend/HermesService.swift#L202)、[默认空地址](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Models/AppSettings.swift#L238)。

修复：翻译版按现有方案移出 Hermes 与自有遥测，不读取 IDFV。将来若确实需要服务端会话连续性，使用按服务隔离、可重置的随机会话 ID，并向用户说明关联范围，不直接复用设备 IDFV。

## 4. OpenVision 数据去向速查

| 路径 | 会涉及的数据 | 接收方 | 触发条件 / 默认情况 |
|---|---|---|---|
| Meta DAT | 设备与 App 交互信息，SDK 诊断相关信息；完整字段未知 | Meta SDK 服务 | App 配置 SDK；采集未显式关闭 |
| Apple Speech | 麦克风音频 | Apple 语音服务可能参与 | 启动语音监听；没有端侧强制条件 |
| 云模型 / 网关 | 文字、近期上下文、所附图片；实时分支可包含音频/画面 | 所选 Google/OpenAI/xAI 或用户配置网关 | 对应模式启动且已配置；不是全部供应商同时收件 |
| 文档 / 原生工具 | 被选取的文档摘录、工具结果，可能含个人事项 | 当前模型服务 | 使用通用助手与对应功能/权限 |
| 联网搜索 | 搜索问题及可能改写的上下文 | Tavily / DuckDuckGo | 工具调用或本地搜索逻辑触发，可跨服务回退 |
| 自有 Telemetry | 性能、时序、事件、模型与设备标签 | 用户填写的 Influx 地址 | 默认关闭且地址为空 |
| Hermes API Key 模式 | 含 IDFV 的会话标识请求头 | 用户配置的 Hermes 服务器 | 选择并配置该后端后发送聊天请求；默认地址为空 |
| 模型/音色下载 | IP、资源请求等连接信息 | Hugging Face 等资源托管方 | 选择相关功能并下载；未见该路径发送会话正文 |
| 本地日志 / 历史 / Photos | 原文、回复、照片或用户主动录制内容 | 首先在设备上；后续由备份/导出/系统同步决定 | 历史自动保存；录制需操作，日志在相关路径产生 |

## 5. OpenGlasses / Avenkin 的外发与保护

### OG-01 · P0：本地模型仍可能自动联网搜索

`localWebSearchFallbackEnabled` 默认 true。Apple 本地模型和 MLX 的回答被判断为不确定或需要时效信息后，会执行搜索再回答。搜索链可依次尝试已配置的 Perplexity、Tavily、Brave、SearXNG，之后有免 Key 的 Tavily 与 DuckDuckGo 回退。改写查询可能使用近期对话。

有医疗本地模式等 guard，并非所有模式都放行；但普通“本地模型”选择本身不足以保证离线。这是本项目不宜直接继承通用助手逻辑的另一个原因。

证据：[默认开关](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Utils/Config.swift#L2187)、[本地模型调用路径](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/LLMService.swift#L4370)、[搜索供应商回退](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/NativeTools/WebSearchTool.swift)。

### OG-02 · P0：端侧唤醒不可用时回退服务器

默认偏好端侧唤醒是积极措施，但 `requiresOnDeviceRecognition = wantsOnDevice && canDoOnDevice` 在端侧不可用时变为 false，随后继续识别，只记录 unavailable 事件。源码注释也明确真实问题的转写仍可走服务器。因此不能向用户承诺“打开本地模型后所有麦克风数据都不出手机”。

证据：[WakeWordService](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/WakeWordService.swift#L1614)。

### OG-03 · P1：支持报告可以发给作者，但所查路径有用户操作与预览

诊断界面分普通问题报告、最近会话/当天活动等不同范围。会话类报告可以包含对话和相关事件；遮蔽 Key 不等于移除对话正文。个人设备的支持收件地址可以回落到开发者邮箱，组织设备有不同收件方限制。

所查路径先生成报告供阅读，再打开 Mail composer 或分享界面，由用户发送；没有把这个功能认定为后台自动上传。发送前必须核对报告类别、正文和实际收件方，不能仅凭“已脱敏”理解成没有隐私数据。

证据：[支持界面与内容说明](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/App/Views/DiagnosticsSupportView.swift#L36)、[邮件与收件方解析](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Diagnostics/DiagnosticsEmailDraft.swift)。

### 已确认的保护及其他联网

| 项目 | 查到的实现 | 审计判断 |
|---|---|---|
| Meta SDK | Info.plist 两项 OptOut 均为 true；启动前安装 `MetaTelemetryBlock` | 优于 OpenVision 默认配置；该类拦截特定遥测 URL，不等于覆盖所有 SDK 网络 |
| Keychain | 提供 ThisDeviceOnly 属性及抛错的严格读写接口 | 可借鉴其原则；不能只看一个封装就保证全项目调用均正确 |
| 日志/出口策略 | `PrivacyLog`、`MedicalEgressGuard`、`EndpointPolicy` 等 | 存在专门防护；完整调用覆盖仍需动态及跨模块核查 |
| 语言包 | 按需从上游 GitHub `main` 下载 JSON | 外部服务器可知 IP、所选语言资源；该下载函数没有附会话正文，资源版本可变 |
| 恢复连接探测 | 对当前云模型 origin 发 HEAD；临时 session、无 Cookie、无认证正文 | 自动网络行为，但目标由已选模型决定，不是另设作者采集站 |
| LicenseService | 本地验证签名许可 | 所查类未发现远端激活请求，不能说它会自动把使用数据发给许可服务器 |
| 其他工具 | 云 STT/TTS、搜索、地图/位置、业务系统、MCP、广播等 | 按所配置功能会产生其他接收方；未把每个 URL 都当成默认上传 |

证据：[Meta OptOut](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Info.plist#L217)、[遥测拦截实现](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Device/MetaTelemetryBlock.swift)、[Keychain](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/KeychainService.swift)、[语言包](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/LocalizationManager.swift#L136)、[连接探测](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Offline/Handoff/ConnectivityProbe.swift)、[许可验证](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/LicenseService.swift)。

它的功能面明显超过翻译 MVP。当前 [BSL 1.1](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/LICENSE) 允许所列个人及非商业用途，但商业用途需要另外许可，标注的变更日为 2030-03-24。我们的方案只参考设计，不把受该许可约束的实现直接搬进 MIT 派生代码。

## 6. Meta 官方参考项目

第三份仓库用于核对设备接入和 API 生命周期，不能当作完整替代 App。当前源码说明分析默认开启，SDK 崩溃捕获也默认开启。实际检查 plist：

| 示例 | Analytics.OptOut | CrashReporting.OptOut |
|---|---|---|
| CameraAccess | 缺失 | 缺失 |
| DisplayAccess | 缺失 | 缺失 |
| BirdSpotter | true | true |

证据：[官方说明](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/README.md)、[CameraAccess 配置](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/CameraAccess/CameraAccess/Info.plist)、[DisplayAccess 配置](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/DisplayAccess/DisplayAccess/Info.plist)、[BirdSpotter 配置](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/BirdSpotter/BirdSpotter-Info.plist)。

OpenVision 使用的 SDK 0.9.0 包定义为 `binaryTarget`，已保存[包定义](audit/2026-10-24/sdk-0.9.0/Package.swift)。此次没有反编译、加载或运行这些二进制。官方示例 App 源码里没查到某个请求，不代表 SDK 内部不会发请求。

Meta AI App 和眼镜固件不在三个源码仓库内，其配对、认证、语音助手与账号数据处理也不在此次静态审计范围。LensMate 关闭自身采集不能控制另一个 App 的隐私策略。

## 7. 下一轮必须补的动态验证

静态审计已经足以决定如何裁剪，以下项目仍标记为**未执行**：

| 场景 | 验收要求 |
|---|---|
| 首次启动 / 闲置 10 分钟 | 无意外模型、搜索、遥测请求；系统与配对流量单独归因 |
| 中英泰六个方向翻译 | 只向披露的 ASR/MT 端点发必要音频与短句；无文档、照片或其他会话混入 |
| 断网 / 服务报错 / 额度不足 | 不自动换供应商、搜索引擎或 Apple 云识别；界面明确报告失败 |
| 停止 / 锁屏 / 蓝牙断开 / App 切后台 | 录音和上传生命周期符合用户选择；旧任务不继续上传或朗读 |
| 调用 Meta AI / 电话打断 | 释放音频会话、丢弃旧任务；恢复行为有提示并经真机验证 |
| Keychain 不可读 / 写入失败 | 配置和备份中没有 Key，日志没有请求正文和认证信息 |
| 关闭历史 / 清除会话 | 不留下原始录音、图片、持久化文本或可复原临时文件 |
| 启用 DAT 相机扩展 | 单独观察 SDK 注册、认证、遥测与相机数据去向，校验两个 OptOut 的实际效果 |

使用受控测试文本、专用低额度 Key，在可行处结合 Instruments、设备网络日志、RVI/代理观察；TLS 加密或证书固定时仅有域名与连接记录也不能证明 payload 内容，需结合我们可控的请求构造代码检查。不得为了方便抓包而把绕过证书验证的代码留进 App。

**交付状态：参考源码和静态审计完成；上游源码未修改；安全修复、依赖构建、iPhone 真机验证与实际流量审计尚未执行。** 后续实施按[OpenVision 二次开发方案](openvision-development-plan.md)推进。
