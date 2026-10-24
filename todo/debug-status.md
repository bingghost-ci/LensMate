# LensMate 本机检查与调试记录

检查日期：2026-10-24，同日更新。结论：**依赖解析及 Xcode 签名构建已通过，LensMate `0.1.0 (1)` 已安装到 iPhone 14 并运行，用户确认正常。原有测试、眼镜与完整功能回归尚未验收，阿里云三语翻译尚未实现。**

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
