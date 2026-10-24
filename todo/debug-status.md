# LensMate 本机检查与调试记录

检查日期：2026-10-24，同日更新。结论：**依赖解析及 Xcode 签名构建已通过，LensMate `0.1.0 (1)` 已安装到 iPhone 14 并运行，用户确认正常。后续界面本地化、文字翻译及非 UI 验证结果见本文末尾；眼镜与完整功能回归尚未验收，文字翻译真实接口与用户 UI/听感待验收。**

## 首次真机运行证据

- 本次会话实测环境：macOS 27.0.1（26A434）、Xcode 27.1（27A9275）、Swift 6.4；iPhone 14，iOS 18.6.2，已配对并启用开发者模式；Xcode 已选 Personal Team。
- 未签名命令已通过依赖解析，随后停在 `Validate plug-in “CudaBuild”`；Xcode 界面还出现 `MLXHuggingFaceMacros` 启用提示和 Metal Toolchain 下载提示。这些是首次构建期间的历史阻碍。
- 随后用户反馈“我看到了，正常，能运行”。再次只读检查发现 `Debug-iphoneos/LensMate.app`，版本 `0.1.0 (1)`，Bundle ID `com.bobby.lensmate`；`codesign --verify` 退出码为 0。
- `devicectl device info apps` 确认该版本已安装，`device info processes` 确认 LensMate 进程存在。证据摘要见 [首次运行核验](evidence/2026-10-24-first-device-run.txt)。
- 因此 BASE-05/06 按实际签名构建、安装和启动结果完成。独立未签名命令没有重验，不能把前一次失败日志当作成功记录；本轮也没有重跑原有测试或调用付费模型 API。

## 已完成的代码准备

- 从 OpenVision `1d5d9203a36f76040947425a603eba57757eac75` 复制 215 个受 Git 管理的文件，含应用、原有测试、Xcode 工程及 Vendor。
- 工程、应用、target、scheme、Swift 模块、显示文案、回调与默认唤醒词改为 LensMate；版本 `0.1.0`，build `1`，Bundle ID 暂定 `com.bobby.lensmate`。
- 本地无真实凭据的配置已建立并忽略；来源、许可证和参考目录完整保留。当前图标沿用上游无文字眼镜图形。
- 三个原始参考仓库 `git status --porcelain` 均为空；91 个 Vendor 文件与原始快照逐字节一致，MIT LICENSE 也一致。

## 实际检查结果

| 检查 | 结果及边界 |
|---|---|
| 105 个 Swift 源文件（应用与原有测试）语法解析 | `swiftc -frontend -parse` 通过；不检查完整类型、SDK 链接和运行行为 |
| `LMExceptionCatcher.m` | 使用 iPhoneOS SDK 和 arm64 iOS 18 target 的 Clang 语法检查通过 |
| Xcode 工程、Info.plist、entitlements | `plutil -lint` 通过 |
| 工程文件引用、共享 scheme | 文件引用均存在，scheme XML 可解析 |
| 旧名字扫描 | 应用、测试、工程和配置模板中未找到 OpenVision、旧唤醒短语和旧 ObjC 桥接符号；来源与版权声明按要求保留 |
| Swift Package 解析 | 本次通过；`Package.resolved` 已存在，早期 Swift 6.2.1 失败不再代表当前状态 |
| Xcode 签名构建 / 安装 / 启动 | 已有签名 App；手机安装和运行进程已核实，用户确认正常 |
| 独立未签名构建命令 / 原有测试 | 未签名命令此前停在插件验证，未重验；原有测试未执行 |
| 眼镜音频 / 各模型 API / 完整功能回归 | 尚未验收；没有对应性能、费用或完整功能结果 |

早期检查环境（历史记录）：macOS 26.1（25B78），Xcode 26.1.1（17B100），Swift 6.2.1，iPhoneOS/iOS Simulator SDK 26.1。当时未发现连接设备及可用模拟器；当前环境与设备状态以上述首次运行证据为准。

## 历史失败点：旧工具链依赖解析

实际执行：

```sh
xcodebuild -resolvePackageDependencies \
  -project ios/LensMate.xcodeproj \
  -scheme LensMate \
  -clonedSourcePackagesDirPath .build/SourcePackages
```

关键错误：

```text
package 'mlx-swift' @ 9c3a80a4ce8be105540e378c2a703bfc9de57f25 is using Swift tools version 6.3.0 but the installed version is 6.2.1
xcodebuild: error: Could not resolve package dependencies
```

来源是原有 `PrismML-Eng/mlx-swift` 依赖。保留上游依赖配置，没有通过删除端侧模型功能或降级依赖绕过。脱敏记录见 [解析日志](evidence/2026-10-24-package-resolution.txt)。日志还出现上游 Kokoro Resources 提示，解决工具链兼容问题后继续确认是否影响构建；不能把当前解析失败直接归因于该提示。

后续复核确认：MLX 清单为 `swift-tools-version: 6.3;(experimentalCGen)`，`mlx-swift-lm` 的固定提交与三个 Vendor 包清单均声明 6.2。现已使用更新工具链完成首次真机运行；旧工具链兼容评估 BASE-09 暂缓，未实施或验证。

## 可选的独立未签名构建复核

当前已完成 Xcode 签名构建，不需要为首次安装重复准备工具链。下列保留命令可用于后续独立构建复核，其缓存路径与 Xcode GUI 的 DerivedData 不同：

```sh
xcodebuild \
  -project ios/LensMate.xcodeproj \
  -scheme LensMate \
  -destination 'generic/platform=iOS' \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

该独立命令目前没有成功执行记录。接下来运行原有测试，并依次验收名称与权限、眼镜注册及回调、单次语音问答、眼镜收音播放、视觉、历史等原有能力；首次启动成功不代表这些项目全部通过。

## 中英文界面与语言选择（2026-10-24）

- 已添加英文、简体中文及默认的「跟随系统」选项，即时切换并持久保存。系统首选语言为中文变体时使用简体中文，不支持的首选语言回退英文。
- 新增 `AppLanguageTests`，覆盖中文地区变体、英文回退、手动覆盖、保存与旧安装默认值、资源加载及格式化消息。全部 145 项自动化测试通过，包含新增的 5 项语言测试；完整模拟器构建通过。
- 实际检查了中英文切换、导航标题刷新、重启保留选择、中文系统跟随，以及泰语优先且中文排第二时仍显示英文。用户反馈「没有太大的问题，语言切换没有问题」，随后要求停止继续测试。
- 此轮没有将更新重新安装到 iPhone 14，也未验收眼镜或调用付费模型。系统权限弹窗语言由 iOS 控制。
- 后续分工见仓库根目录 `AGENTS.md`：Codex 负责开发和非 UI 测试，最终 UI 测试与验收由用户负责。

本机 Xcode 27.1 的普通模拟器签名会在上游 Kokoro/Misaki 的资源包上报 `bundle format unrecognized`；未签名运行又会导致 Meta SDK 初始化失败。测试使用临时 `.xcconfig` 仅启用应用、测试及构建工具签名，未修改 Vendor 或正式签名配置：

```xcconfig
CODE_SIGNING_ALLOWED = $(LM_LOCAL_SIGN_$(PRODUCT_NAME))
LM_LOCAL_SIGN_LensMate = YES
LM_LOCAL_SIGN_LensMateTests = YES
LM_LOCAL_SIGN_MLXHuggingFaceMacros = YES
LM_LOCAL_SIGN_CudaBuild = YES
```

最终完整回归命令使用 `xcodebuild test`，scheme 为 `LensMate`，目标为 iPhone 18 Pro / iOS 27.0 模拟器，并传入上述临时 `-xcconfig`、`-testLanguage en -testRegion US -collect-test-diagnostics never`。退出码为 0，结果为 `TEST SUCCEEDED`；日志保存在本机忽略目录 `.build/localization/regression-final.log`。

## 中英泰文字翻译第一批（2026-10-24）

- 独立翻译页、六方向、交换、原文/译文、北京/新加坡配置与 `qwen-mt-flash` 真实适配器已实现。阿里云最新官方契约、固定端点与区域密钥要求见[使用说明](../docs/text-translation.md)。
- 专用 Keychain 保存密钥，失败不写普通配置；独立临时 URLSession、拒绝重定向、不带助手上下文、不持久化正文、不输出正文/密钥日志。系统朗读支持停止/重播和缺音色提示；切换、后台及旧响应隔离和助手交接已实现。
- 完整模拟器构建成功，`xcodebuild` 退出码 0。完整 XCTest 回归 **171 项通过、0 失败**，含新增 26 项翻译测试。编译器提取的 484 个文案键全部存在，所有需翻译键均具备英文/简体中文资源。
- 非 UI 集成使用 URLProtocol 注入 HTTP 响应并验证 URLSession 取消；Keychain 测试使用独立服务名做实际读写与失败注入。没有调用真实阿里云接口，没有使用或输出用户凭据。
- 沿用上一节的本机测试签名配置与现有 DerivedData，不更改 Vendor、包版本或正式签名。初次添加工程文件时的分组路径和 Swift actor 默认参数编译错误已修正，最终构建/测试成功。
- 日志位于本机忽略目录 `.build/translation/build-final.log`、`regression-final.log`；可提交的结果摘要见[验证记录](evidence/2026-10-24-text-translation.txt)。未运行 UI 测试、截图或视觉走查，也未将新版安装到用户真机。
- 待用户在 App 中选择地域、保存有效 Key 并开通模型后，验收真实鉴权、六方向译文、系统三语音色、UI、助手交接及生命周期。ASR、持续录音、后台翻译、眼镜专用路由和字幕不在本批范围。

## 轮流对话翻译与停顿设置（2026-10-24）

- 根据用户提供的对话流程，将默认翻译页改为双方原文/译文卡片：我方眼镜/HFP 收音、可调静音结束；对方手动开启/停止手机录音；对方译文在眼镜朗读后再恢复我方收音。原文字页保留在「… → 改用文字输入」。
- 新增我方停顿 1～10 秒设置，默认 5 秒，自动保存；对方停顿不会自动提交。单句 60 秒上限：对方到上限暂停收音但仍等待手动提交。20 秒未检测到说话声取消并提示。
- 按句 `qwen3-asr-flash` 真实适配器已实现并核对官方地域、语言、WAV Base64 格式；录音只在内存中，录音期间不上传。沿用同地域 Keychain 密钥和独立请求链，无助手上下文。
- Xcode 27.1 / Swift 6.4 完整模拟器构建成功；完整回归 **191 项、0 失败**，包含本批新增 20 项。对方上限策略改为手动提交后，相关 20 项再次通过；最终权限说明资源更新后构建成功。没有做 UI 自动化或截图走查。
- 编译器提取的 537 个文案键均有资源，需要翻译的键完整支持英文/简体中文；原有文案保持不变。补充了中英文麦克风用途说明。
- 日志：`.build/conversation/build-final.log`、`regression.log`、`focused-final.log`，均为本机忽略文件。可提交摘要见[验证记录](evidence/2026-10-24-conversation-translation.txt)。
- 仍待用户用实际地域/Key 验证 ASR/MT、在 iPhone 上确认眼镜与手机输入/输出、三语听感、噪声下停顿效果和 UI。模拟器/注入设备不代表真实音频路由通过。见[使用与验收说明](../docs/conversation-translation.md)。
