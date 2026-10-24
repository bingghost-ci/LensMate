# 保留 OpenVision 后，另外两个项目能补什么

日期：2026-10-24。用户已看过审计，选择**保留 OpenVision 现有代码功能，在此基础上增加能力**。当前设备为无屏、只有声音输出的 Meta 眼镜；以后可能购买带屏版本。

## 1. 推荐路线

OpenVision 继续作为完整助手基础，保留多模型、实时语音、视觉、搜索、工具、记忆、历史、录制、本地模型和已有设置。新增独立翻译模式，优先接阿里云中英泰识别与翻译，并逐步补充快捷入口和使用体验。

对现在的设备：**眼镜收音/播放，iPhone 显示字幕与操作**。对未来带屏设备：再增加镜片字幕输出；不能通过软件让当前无屏硬件显示文字。

本比较依据已下载的固定源码，不把 README 中的功能描述等同于我们已经完成真机验收。OpenVision 提交 `1d5d9203a36f`；OpenGlasses 提交 `e3b2dad823e1`；Meta 官方参考提交 `bbae597cd1c7`。

## 2. OpenGlasses / Avenkin：适合补充的用户功能

| 候选 | 相对 OpenVision 的补充 | 对你的用途 | 建议 |
|---|---|---|---|
| 专用双向翻译与连续字幕 | 有单向/双向语言路由、原文显示、字幕分段与合并；OpenVision 主要是通用助手问答 | 泰语/英语说话时，手机显示原文与中文；中文回答时切换目标语言 | **第一批**；做成独立翻译入口，接我们选择的阿里云链路 |
| 通义实时语音适配 | 有独立 Qwen Omni / Qwen Audio 协议适配层；并非只改一个模型名字 | 在原有助手模式中新增阿里云实时语音选择 | **第一批研究**；与专用 ASR + MT 翻译链分开验证 |
| 音频中断和蓝牙恢复 | 明确区分暂停、恢复、重建音频图，并检查当前会话所有权 | 来电、断连、换麦克风后尽量恢复；减少“连接着但没声音” | **第一批**；以真机结果衡量，不承诺 Hey Meta 无缝接管 |
| Siri / 快捷指令入口 | 有问答、开始/停止监听、拍照等 App Intents | 少拿手机；支持 Siri、快捷指令及兼容 iPhone 的操作按钮入口 | **第二批**；参考其框架新增“开始/停止翻译”意图 |
| 最近一段话回顾 | 可选滚动录音缓冲，按需转写并交给模型总结 | “刚才他说了什么？”“再翻译上一句”“再读一次” | **第二批**；先复用已产生的译文做重播，再考虑音频回顾 |
| 更完整的离线语音链 | 端侧 ASR、翻译后端选择、断网状态与会话交接 | 网络差时尽量保留可用能力 | **后续**；OpenVision 已有本地 LLM/TTS，补的是语音识别与衔接，不重复开发模型加载 |
| 说话人区分 / 会议回顾 | 有说话人分段与标签、字幕历史、会议摘要工具链 | 多人交谈、会议整理 | **后续按需**；现有云说话人方案使用 Deepgram，不等于阿里云已覆盖，也不能保证中英泰效果 |
| 会话加密与解锁 | 可选加密存储、Face ID/Touch ID/设备密码解锁 | 保留对话历史时更方便控制访问 | 可作为独立增强；不要求先删掉原有历史功能 |

OpenVision 已有视觉问答、拍照/录制、文档和本地模型，OpenGlasses 的同类功能不再算作本次主要新增项。企业工单、临床工作流、广播等暂不进入日常翻译优先列表。

## 3. 已从代码确认的细节与边界

### 双向翻译可以参考，但不能整段照搬

`TranslationConfig` 的语言列表包含 `zh`、`en`、`th`；`TranslationRouting` 区分佩戴者和对方语言，手机可呈现两边。`AmbientCaptionService` 实际连接了翻译 provider，属于已有接线的代码，不只是一个功能名称。

不过这里有多条不同实现：新的翻译字幕云端分支使用 Gemini 的 TEXT 模式；端侧分支为 SenseVoice → Apple Translation；另一个 `LiveTranslationService` 提供翻译后朗读。**字幕路径并不自动等于我们需要的阿里云语音播报闭环。** `AmbientCaptionService` 的注释还明确标记相关集成待设备验证。

旧 `LiveTranslationService` 存在“至少三个空格分隔词”才翻译的条件，这对中文和泰语不适合作为通用规则。我们的短句处理应采用识别事件、停顿、标点和长度上限，并验证重复字幕与重播问题。

代码：[语言与双向配置](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Translation/TranslationConfig.swift)、[方向路由](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Translation/TranslationRouting.swift)、[字幕接线](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/AmbientCaptionService.swift)、[断句](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Translation/UtteranceSegmenter.swift)、[原有语音翻译](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/LiveTranslationService.swift)。

### 阿里云实时协议有参考实现，真实调用仍待验证

`QwenRealtimeAdapter` 和 `QwenAudioRealtimeAdapter` 分别处理会话格式、音频、工具和中断，能力并不相同：一个有图片缓冲但不支持其通用文字注入命令，另一个有文字轮次但不支持图片。不能把一个兼容地址直接套进全部 OpenAI Realtime 行为。

该仓库自己的兼容说明明确表示 Qwen 的鉴权实时会话尚未验证。因此我们参考协议分层方式，在自己账号、地域和选定模型上验证，不把这个仓库的模板当作“接上 Key 就肯定能用”的保证。普通聊天、实时语音和专用 ASR/MT 是三类接口，分别接入。

代码：[Qwen Omni 适配](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/QwenRealtime/QwenRealtimeAdapter.swift)、[Qwen Audio 适配](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/QwenRealtime/QwenAudioRealtimeAdapter.swift)、[仓库兼容与验收边界](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/docs/compatible-realtime.md)。

### 快捷入口、回顾和音频恢复

- Siri 的问答入口由 Siri 收集问题，再交给 App 的已有模型链；不是接管眼镜的“Hey Meta”。我们可以按此设计新的翻译快捷动作，能否在锁屏状态直接开始持续录音仍需验证。
- `MemoryRewindService` 需要先开启缓冲，不能追回此前没录到的声音；源码有可配置缓冲容量，回顾转写可能进入系统/云识别。对翻译用户，先增加“上一句重播”通常更简单，也更省调用费用。
- `AudioInterruptionPolicy` 已区分系统允许恢复与不允许恢复，并检查会话归属。它能补 OpenVision 现有重连逻辑，但不能单凭静态代码证明所有 iOS/眼镜组合都恢复正常。

代码：[Siri 问答](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/App/Intents/AskQuestionIntent.swift)、[监听开关](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/App/Intents/ListeningToggleIntents.swift)、[回顾缓冲](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/MemoryRewindService.swift)、[音频恢复策略](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Audio/AudioInterruptionPolicy.swift)、[说话人配置](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/Diarization/DiarizationConfig.swift)、[会话加密](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/OpenGlasses/Sources/Services/ConversationEncryptionService.swift)。

## 4. Meta 官方项目：主要补充设备接入与验证能力

| 参考内容 | 对当前无屏设备的价值 | 以后带屏设备的价值 |
|---|---|---|
| CameraAccess 的会话生命周期 | 参考启动/结束会话、预览/录制、切后台和暂停状态处理；OpenVision 已有拍照，不重复算新功能 | 继续复用设备状态管理 |
| 设备/眼镜应用更新处理 | 遇到固件或设备端应用版本不兼容时给出正确更新入口 | 同样适用 |
| MockDeviceKit | 开发时用模拟设备验证界面和生命周期，减少每次都依赖实体眼镜 | 可以预先开发带屏交互；模拟验证不能替代蓝牙和续航测试 |
| DisplayAccess | 当前硬件没有显示屏，不作为第一阶段功能 | 把译文、提示卡片、操作步骤显示到支持的镜片屏幕 |
| BirdSpotter 的组件组织 | 参考把会话、相机、语音和检测分开的结构；鸟类识别本身不是当前重点 | 可参考语音与显示协同，但不要把示例 App 整体搬进项目 |

官方 DisplayAccess 明确要求支持显示的 Meta Ray-Ban Display 设备，同时提供手机/模拟器预览路径。[官方示例说明](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/DisplayAccess/README.md)

代码：[CameraViewModel](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/CameraAccess/CameraAccess/ViewModels/CameraViewModel.swift)、[模拟设备管理](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/CameraAccess/CameraAccess/ViewModels/MockDeviceKit/MockDeviceKitViewModel.swift)、[DisplayAccess](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/DisplayAccess/README.md)、[BirdSpotter](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/samples/BirdSpotter/README.md)。

版本不能混用：当前 OpenVision 锁定 DAT 0.9.0，官方参考快照为 1.0.1 发布提交。参考生命周期和模拟测试时先对齐 API，升级作为独立变更验证，不把复制样例等同于直接编译通过。

## 5. 功能借鉴与源码使用

OpenVision 的主项目为 MIT。OpenGlasses 当前为 BSL 1.1，其许可明确允许所列个人/非商业使用，但商业用途需要另行许可。**个人实验可按许可条件复用；若我们要保留将来商业分发的选择，优先参考功能设计并独立实现，不直接混入受 BSL 约束的源码。** 这不影响保留 OpenVision 的功能。

Meta 官方仓库受其 Developer Terms 约束，也不能统一当成 MIT。涉及直接复制的文件、依赖和分发条件应按各自许可处理。[OpenGlasses 许可](https://github.com/straff2002/OpenGlasses/blob/e3b2dad823e1e038ea787748fee204eadbe8cb8e/LICENSE) · [Meta 官方许可声明](https://github.com/facebook/meta-wearables-dat-ios/blob/bbae597cd1c748cd29b9375a1624a8d75b1c9e14/LICENSE)

## 6. 采用顺序

1. 保留并跑通 OpenVision 基线，列出原有功能验收项。
2. 新增中英泰翻译模式：阿里云识别/翻译、iPhone 双语字幕、眼镜播报、方向切换和上一句重播。
3. 增强共享音频的中断恢复；增加 Siri/快捷指令入口。研究通义实时语音作为通用助手的新增 provider。
4. 根据日常使用再决定音频回顾、离线链路、说话人区分和会话加密。
5. 购买带屏设备后，接 `DisplayCaptionOutput`；现阶段只保留字幕输出接口，不提前开发或承诺镜片显示。

当前仅完成源码比对与规划，未复制 OpenGlasses 实现到主项目，未编译安装或调用付费 API。
