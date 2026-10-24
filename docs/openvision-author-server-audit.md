# OpenVision 是否向作者服务器收集上报数据

复核日期：2026-10-24。固定提交：`1d5d9203a36f76040947425a603eba57757eac75`。

用户已明确：Meta SDK 的官方采集可以接受，本轮重点检查 OpenVision 应用自己是否另行收集、转发或后台上报。这个接受范围不自动扩展到其他厂商或任意自定义服务器。

## 结论

**在当前下载的源码及本次追踪的请求构造、配置和启动路径中，未发现将设备信息、剪贴板、对话或图片额外自动发送到 OpenVision 作者自有服务器的实现。** 未找到硬编码作者统计/收集端点，也未找到业务请求完成后再向另一个作者地址复制一份内容的调用链。

这不是“完全不采集、不联网”：应用具备设备性能采样、可选遥测、设备标识发送、搜索、定位笔记和云模型等逻辑。需要分别判断收件方和触发条件，不能把这些都归为作者偷偷收集，也不能忽略它们。

本结论针对固定源码快照。没有运行 App、抓包或分析作者发布的 IPA；外部 Swift 包与闭源组件未做完整内部审计。网络重定向、外部包下载与实际发布构建的行为还需要构建和运行证据。

## 1. 已追踪的应用网络路径

下表按代码构造的初始目的地归类。完整文件位于 `references/OpenVision/OpenVision/`。域名/URL 字面量与请求调用位置另见[原始清单](audit/2026-10-24/endpoint-inventory.csv)。

| 路径与实现文件 | 地址来源 / 接收方 | 请求携带内容 | 作者自有上报判断 |
|---|---|---|---|
| `Telemetry/InfluxMetricsSink` | 用户填写 `telemetryURL`，请求 `/api/v2/write` | 内存、CPU、热状态、电量、模型、时序、事件、时间戳及用户设置标签 | 默认关闭且地址空；没有内置作者接收地址 |
| `OpenClaw/OpenClawService` | `openClawGatewayURL`；可由用户或编译配置指定 | 聊天文字、附图、认证及客户端握手信息 | 未发现额外复制到第二个作者端点；编译配置例外见第 4 节 |
| `AIBackend/HermesService` | 用户填写 `hermesServerURL` | 文字、附图、认证；API Key 模式额外发送 IDFV 派生的会话头 | 地址默认空；数据交给配置的服务器，不是默认作者收件 |
| `AIBackend/HermesGateway` | 用户配置 dashboard 的 `/auth/native/*`、`/api/auth/ws-ticket`、`/api/ws` | 登录凭据交换、会话、文字和附图 | 地址由 dashboard 配置派生；未找到独立作者回传端点 |
| `AIBackend/OpenAIService` | `openAIBaseURL`，默认 `api.openai.com/v1` | 文字、附图、近期对话、启用的文档/工具结果 | 对应配置的模型服务 |
| `OpenAIRealtime/OpenAIRealtimeService` | 将 `openAIBaseURL` 派生为 WS(S) realtime 地址 | 语音流、文字、图片、模型参数 | 对应配置的实时模型服务 |
| `AIBackend/ChatGPTSubscription` | `chatgpt.com/backend-api/wham` | 文字/图片/工具上下文、认证及账号相关头 | 对应所选订阅服务；不是作者统计服务 |
| `AIBackend/GrokService` | `api.x.ai/v1` | 文字、图片、工具上下文、认证；模型列表请求 | 对应所选模型服务 |
| `GeminiLive/GeminiLiveService`、`GeminiVisionService` | `generativelanguage.googleapis.com` | 所选实时模式的音频/文字/图片、工具结果和认证 | 对应所选模型服务 |
| `TTS/CloudTTSService` | `api.x.ai/v1/tts` 或 `openAIBaseURL/audio/speech` | 待朗读文字、音色、认证；另有音色列表请求 | 云朗读会额外发送正文，但未发现发往作者服务器 |
| `Web/WebSearchService` | `api.tavily.com`、`api.duckduckgo.com`、`html.duckduckgo.com` | 搜索查询；Tavily 还带配置的 API Key | 搜索接收方可能超出当前模型，但不是已发现的作者收集站 |
| `OAuth/OAuthClient` | `auth.openai.com`、`auth.x.ai` 或用户 Hermes dashboard | 授权码、验证参数、刷新凭据等 | 未找到作者中转服务；xAI 发现文档的端点还经过 HTTPS/主机范围检查 |
| `OAuth/OAuthLoopbackServer` | 本机 loopback 回调监听 | 接收登录回调并校验 state | 本地接收器，不是向作者服务器上报 |
| `TTS/KokoroTTSService` | Hugging Face 模型/音色资源 | 下载请求 | 所查函数未附带对话；不是作者上报 |
| `GemmaLocal/GemmaLocalService`、`Voice/SpeechActivityDetector` | MLX/Hugging Face 模型加载、FluidAudio VAD 初始化 | 应用侧传入模型 ID/配置；VAD 在本机接收音频块 | 依赖包内部及实际资源请求需另验；不能仅据应用源码证明依赖绝无联网 |
| `ContextualNoteTool.LocationHelper`、`VoiceCommandService` | 系统定位/地理编码、Apple Speech 框架 | 定位或音频进入相应系统 API | 未发现作者服务端路径；具体系统网络由框架决定 |

设置页中的 GitHub、API 控制台和文档 `Link` 是用户打开的网页链接，不能直接视为后台数据上报。plist 的 Apple DTD URL 也不是应用代码构造的业务上传请求。

## 2. 自有遥测的完整链路

复核到的链路为：

```text
AppSettings：telemetryEnabled = false，telemetryURL = ""
    ↓ 用户开启并填写地址，或恢复此前已保存的设置
MetricsCollector.applySavedConfiguration()
    ↓ 同时检查开关和非空地址
InfluxMetricsSink(config: 用户设置)
    ↓ 编码设备/耗时/事件指标；约每 10 秒或达到批量阈值发送
POST 用户地址的 /api/v2/write
```

没有目标地址时不能形成这条上报链。打开 Telemetry 页面会开始本地设备采样，不能把“本地采样发生”写成“已经发给作者”。设置页也明确使用 `Push to InfluxDB` 开关、URL 字段和推送状态。

所查指标 payload 没有原始录音、照片、识别全文或剪贴板内容。事件名称的调用点为固定事件值；`device` 标签默认 `iphone`，并非自动读取用户手机名称。启用后会持久化并在 App 重启时恢复上报，因此“以前开过、现在没打开遥测页面”仍可能发送。

证据：[默认值](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Models/AppSettings.swift)、[配置检查](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Telemetry/MetricsCollector+Configuration.swift)、[实际 payload 与发送函数](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Telemetry/InfluxMetricsSink.swift)、[设置入口](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Views/Settings/TelemetrySettingsView.swift)。

## 3. 继续追踪到的隐私处理

| 内容 | 采集 / 保存行为 | 是否发现作者上报 |
|---|---|---|
| 剪贴板 | `ClipboardTool` 仅写入工具参数，并返回待复制文字预览；未找到主动读取现有剪贴板的业务代码 | 未发现 |
| IDFV | Hermes API Key 分支读取并拼入 `X-Hermes-Session-Key` | 发到用户配置的 Hermes，不是默认作者地址 |
| 定位 | App 启动创建 `LocationHelper`；已有定位授权时会请求一次位置。保存笔记时可记录经纬度与地点 | 未发现作者路径；云模型调用笔记工具时，结果可带地点名称与笔记正文 |
| 人脸 | Vision 特征、姓名与最近见面时间保存在 `Documents/known_faces_v2.json`；识别日志会打印姓名及距离值 | 在此类中未发现网络上传；不能因此保证通用相机功能从不把照片发给所选模型 |
| 会话/日志 | 会话 JSON、识别和回复日志；Keychain 失败时配置文件可能保留密钥 | 未发现专门上传这些文件给作者的函数；本地泄露风险依旧存在 |
| 日历/提醒/文档 | 功能调用读取或操作本机信息；工具结果可以进入当前模型请求 | 收件方是对应模型/网关，不是已发现的独立作者服务器 |

新增定位细节：`LocationHelper.init()` 在已经获权时调用 `requestLocation()`；`currentPlace()` 才调用地理编码。不能说它会在每次冷启动自动把 GPS 发给作者，也不能说它完全不在启动时读取位置。笔记保存的经纬度与回传给模型的地点文字应分别对待。

证据：[剪贴板](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/NativeTools/ClipboardTool.swift)、[IDFV](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/AIBackend/HermesService.swift)、[定位及笔记](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/NativeTools/ContextualNoteTool.swift)、[启动调用](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/App/OpenVisionApp.swift)、[人脸持久化](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Services/Vision/FaceRecognitionService.swift)。

## 4. 公开源码与安装包的边界

这次发现一个必须单独说明的配置入口：

- `Config.swift.example` 中 `defaultOpenClawGatewayURL`、认证字段和 Gemini Key 均为空。
- `SettingsManager.createDefaultSettings()` 会应用编译时的这些默认值，所以 App 不一定非要由最终使用者手动填写网关。
- 真正的 `OpenVision/Config/Config.swift` 被上游 `.gitignore` 排除。公开 CI 只是复制示例文件来做未签名构建，不能证明所有发布包也用了同样配置。

因此，源码中没有作者接收地址，**不等于已经验证作者提供的安装包没有预置网关**。这只是尚未验证的边界，不是发现作者实际这样做的证据。我们从固定源码自己构建、把这些默认地址保持为空并留存构建配置，就能控制这项风险。

证据：[空值模板](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Config/Config.swift.example)、[默认配置应用](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/OpenVision/Managers/SettingsManager.swift)、[忽略规则](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/.gitignore)、[公开 CI](https://github.com/rayl15/OpenVision/blob/1d5d9203a36f76040947425a603eba57757eac75/.github/workflows/ci.yml)。

## 5. 对 LensMate 的决定

更新：用户看完审计后决定保留 OpenVision 全部现有功能。以下实施建议以最新的[二次开发方案](openvision-development-plan.md)为准，取消此前删除遥测、Hermes、搜索等功能的计划。

1. 继续采用 OpenVision 为开发基础；目前没有“作者私自回传数据”的源码证据需要因此否决它。
2. 按用户允许保留 Meta SDK 接入及官方采集，不把它归入 OpenVision 作者私设收集服务器的问题；设备能力仍需真机验证。
3. 保留 Influx 上报、Hermes、搜索、定位笔记等原有功能及设置，新增翻译模式独立处理其请求和上下文。
4. 密钥写入普通配置及正文日志问题保留为独立改进项，不作为删功能的理由。
5. 后续从我们自己的固定源码构建；首次启动、闲置、翻译和停止分别观察流量。所有自有请求应可对应配置与功能，不出现无解释目的地。

本轮只更新审计和方案，三个参考仓库原代码保持未修改，未运行上游脚本或调用任何模型 API。
