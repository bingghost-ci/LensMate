# LensMate iOS 工程

这是从固定 OpenVision 提交复制并改名的独立开发副本。完整原有功能保留；阿里云三语翻译尚未实现。

2026-10-24 已通过 Xcode 签名构建并在 iPhone 14（iOS 18.6.2）安装启动，版本 `0.1.0 (1)`；用户确认可运行，设备安装与进程记录已复核。当前工具链为 Xcode 27.1 / Swift 6.4，早期 Swift 6.2.1 依赖阻碍已解除。眼镜和模型能力仍需分别验收。

```sh
open ios/LensMate.xcodeproj
```

在仓库根目录执行上面的命令。Xcode 中选择 `LensMate` scheme。工程文件已生成，不需要先安装 XcodeGen；`project.yml` 也同步维护了新名字，以后需要重新生成时再使用 XcodeGen。

首次准备与实测状态见 [todo](../todo/README.md)。初次依赖解析需要联网，Meta DAT/MLX 等依赖较大；不要以“工程能打开”代替“可以编译运行”。

本地 `Config.xcconfig` 与 `LensMate/Config/Config.swift` 已由空值模板生成且被 Git 忽略。换一台机器时，分别从对应 `.example` 复制。签名安装前在 Xcode 设置自己的 Team；必要时调整 Bundle ID，并使 Meta 注册信息与回调配置一致。

当前保留上游全部包依赖和 API 版本，不因工具链问题删除功能或随意降级依赖。构建命令与实际错误会记录在 [调试记录](../todo/debug-status.md)。
