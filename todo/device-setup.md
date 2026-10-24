# LensMate 真机调试准备

LensMate `0.1.0 (1)` 已在 iPhone 14 上签名安装并启动，用户确认正常；安装记录、运行进程和本地 App 签名已核实。三语翻译仍是后续新增功能。先继续验证眼镜与原有功能基线，再接阿里云翻译。实际检查见 [debug-status.md](debug-status.md)。

## 1. 当前工具链已准备好

本机复核结果（2026-10-24）：macOS 27.0.1、Xcode 27.1、Swift 6.4，iPhoneOS SDK 27.1。依赖解析已通过，当前机器已完成 Xcode 签名构建与首次真机运行。

此前 macOS 26.1 / Xcode 26.1.1 / Swift 6.2.1 的解析错误保留在调试记录中，已不再阻塞当前机器。MLX 清单要求 Swift 6.3；旧工具链兼容改造仍未验证，[BASE-09](backlog.md) 暂缓。

- [x] 当前 macOS 与 Xcode 已可用于本次构建。
- [x] Swift 6.4 满足已发现的 MLX 清单版本要求。
- [x] iOS 平台支持可用，Xcode 已生成真机 App。
- [x] 命令行已选择 `/Applications/Xcode.app/Contents/Developer`。

换机或重新安装 Xcode 时，重新核对 [Apple Xcode 系统要求表](https://developer.apple.com/xcode/system-requirements)。若构建提示缺少 Metal Toolchain，按 Xcode 的 `Download & Install` 安装组件；若提示启用 `CudaBuild` 或 `MLXHuggingFaceMacros`，核对依赖来源后在 Xcode 中处理对应信任提示。本次只记录最终构建和运行结果，不把中间提示视作仍未解决的阻碍。

依赖需要联网下载。目前不需要先安装 XcodeGen，仓库已有生成好的 `.xcodeproj`。模拟器可用于部分界面检查，但不能代替蓝牙眼镜、麦克风路由和端侧模型的真机验证。

## 2. Apple 账号与 iPhone

- [x] Xcode 已选择个人 Apple Account 的 Personal Team，并生成签名 App。
- [x] iPhone 14 已通过 USB 连接并完成配对。
- [x] 手机开发者模式已开启。换设备时可参考 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
- [x] 当前手机 iOS 18.6.2，满足工程 iOS 18 最低部署版本；部分端侧能力仍有额外机型或系统要求。
- [x] Automatic Signing 与 Team 已配置，当前构建已成功安装启动。

本次 Personal Team 已完成安装启动。免费签名有期限和能力限制，不能据此认定所有端侧模型和 entitlement 的运行效果已通过；后续按具体功能验收。参考 [Apple 开发者计划说明](https://developer.apple.com/help/account/membership/programs-overview/)。

已知设备与账号条件：**iPhone 14、iOS 18.6.2、Personal Team**，无需重复准备。

## 3. 眼镜和 Meta AI

- [ ] 给眼镜和手机充足电量，确认眼镜已在 Meta AI App 内正常配对，能播放声音。
- [ ] 在 Meta AI 内检查眼镜固件与 App 更新，并按当前官方入口开启眼镜 Developer Mode。这个开关与 iPhone 的“开发者模式”是两回事。
- [ ] 保留 Meta AI，用于配对、设备管理及 SDK 注册授权；LensMate 作为单独 App 运行。
- [ ] 首次启动 LensMate 时按实际功能授权蓝牙、麦克风、语音识别与相机等权限；在注册跳转后验证回到 LensMate。

Meta 官方说明通过 Meta AI 开启开发者模式并进行配对，见 [Meta 开发 FAQ](https://developers.meta.com/wearables/faq/)。本项目暂沿用 OpenVision 的 **DAT 0.9.0**，官方新样例已更新，不能把新版本的免凭据开发流程直接当成 0.9.0 的已验证结论。

模板中的 `META_APP_ID = 0`、空 `CLIENT_TOKEN` 是占位值；本地文件是否填写也不能代替真机注册验证。如果当前 SDK/设备流程要求 Meta 应用资料，再为 LensMate 创建或配置对应应用，把真实值填入本地文件。注册使用的 Bundle ID 与回调 scheme 必须和工程一致：当前为 `com.bobby.lensmate` 与 `lensmate`。后续若更改 Bundle ID，也要同步 Meta 配置。

当前无屏设备：眼镜播放声音，字幕显示在手机。镜片字幕留在未来设备任务中。两个助手的录音交接、锁屏和蓝牙恢复都需要实测。

## 4. 打开、安装、首次使用

在仓库根目录执行：

```sh
open ios/LensMate.xcodeproj
```

1. 选择 `LensMate` scheme 和已连接的 iPhone。
2. 等待依赖解析，确认 Team 与签名配置；本机已完成这一步，旧 Swift 版本错误已解除。
3. 按 Run（⌘R）编译并安装；若有错误，保留第一处完整错误用于继续调试。
4. 启动后检查桌面名称、引导、设置、历史、设备连接及权限；默认唤醒词已经改为 `Ok LensMate`，识别效果尚未实测。
5. 先配置一个已有的助手后端做录音、回复与播放验证，再逐项回归其他功能。

新名字使用独立 App 身份，旧 OpenVision 的沙盒配置不会自动迁移。现在没有“一键三语翻译”可用；该功能完成后会补充专门的使用步骤。

## 5. 模型与阿里云凭据何时准备

编译检查无需付费模型 Key。验证现有云端助手时，在 App 的设置里填所用服务凭据；不需要一次准备所有服务。

阿里云翻译开发阶段再确定地域、语音识别和翻译模型，开通对应 API，设置个人预算并实测三语效果。模型 Key 与 Meta 注册资料属于不同用途，不能互换。现在工具链与手机安装启动已完成，下一步先验证眼镜注册、收音播放和一个已有助手后端。

真实凭据只写 App 设置或本地忽略文件，不放进待办与代码仓库。
