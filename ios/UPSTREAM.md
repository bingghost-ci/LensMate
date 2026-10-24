# LensMate 源码来源

本目录是 LensMate 的独立 iOS 开发副本，用于用户个人使用。来源为 OpenVision：

- 上游：<https://github.com/rayl15/OpenVision>
- 固定提交：`1d5d9203a36f76040947425a603eba57757eac75`
- 来源记录：[upstream-source.json](upstream-source.json)
- 原始参考：`../references/OpenVision/`，保持不变。

已复制应用源码、全部原有测试、Xcode 工程、项目定义及 Vendor 代码；未带入嵌套 `.git` 或上游 CI。原有助手功能保留，新增功能按 `../todo/` 实施。

工程、target、scheme、Swift 模块、App 名称、提示文字、内部命名、回调 scheme 及默认唤醒词改为 LensMate。默认唤醒词为 `Ok LensMate`，保留设置中的自定义能力；实际识别效果待真机验证。当前图标仍沿用无文字的上游眼镜图形，独立视觉设计另列待办。

这是新 App 身份，Bundle ID 暂定 `com.bobby.lensmate`，版本 `0.1.0`，build `1`。它不会自动读取另一 Bundle ID 下旧 App 的沙盒或 Keychain；首次安装需重新配对授权并输入配置。

上游 MIT 许可证和版权声明保存在 [LICENSE](LICENSE)，Vendor 中各项目的许可及署名原样保留。应用改名不更改第三方框架/模型的正式名称，也不抹去源码许可署名。

真实 Team ID、Meta 凭据写入本地 `Config.xcconfig`；模型 Key 优先在 App 内配置。上述本地配置文件已加入 `.gitignore`。不要把密钥粘贴到任务文档或聊天里。
