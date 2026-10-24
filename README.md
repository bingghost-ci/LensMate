# LensMate

为 Meta 智能眼镜设计的 iPhone 配套 App，保留 OpenVision 现有助手功能，优先新增采用阿里云百炼的中文、英文、泰语实时翻译。当前眼镜为无屏声音版：眼镜播放译音，iPhone 显示字幕；未来再接带屏设备。

已从固定 OpenVision 提交建立 `ios/` 开发副本，工程和 App 已改名为 **LensMate**。依赖解析和 Xcode 签名构建已通过，`0.1.0 (1)` 已安装到 iPhone 14，用户确认可正常启动运行；眼镜和各项功能仍需逐项验收，阿里云三语翻译尚未实现。

- [待办目录](todo/README.md)：总任务清单、真机准备和实际调试结果。
- [LensMate iOS 工程](ios/README.md)：打开工程、配置与上游来源。

- [参考源码与审计依据](docs/security-audit-2026-10-24.md)：固定提交与复核依据；`references/` 仅保留在本机，整个目录不提交。
- [安全与数据外发审计](docs/security-audit-2026-10-24.md)：默认采集、搜索回退、密钥、日志及未验证边界。
- [OpenVision 作者服务器专项复核](docs/openvision-author-server-audit.md)：只看应用自有请求、收件方和后台上报，区分源码与安装包。
- [OpenVision 二次开发方案](docs/openvision-development-plan.md)：保留现有功能的增量方案、实施顺序与验收条件。
- [参考项目功能补充比较](docs/reference-feature-comparison.md)：OpenGlasses 与 Meta 官方样例可补充的功能、优先级和复用边界。
- [交互式工作原理图](docs/translation-flow.html)：浏览器直接打开，查看七步流程、切换语言和设备、估算费用。
- [阿里云实时翻译方案](docs/aliyun-translation-plan.md)：当前第一版方案、API 凭据、成本、使用方法与验收步骤。
- [iOS 方案与使用指南](docs/ios-plan-and-quickstart.md)：早期通用助手研究、安装步骤和 DIY 项目。
- [技术资料与实施指南](docs/Meta_Glasses_DIY_App_Technical_Guide_2026-10-23.md)：模型、设备接入和开发资料索引。

第一版链路：眼镜或手机收音 → iPhone → 阿里云识别 → iPhone 整理短句 → 阿里云翻译 → iPhone 系统朗读 → 眼镜或手机播放。蓝牙路由、三语音色和实际延迟仍需真机验证。

以完整 OpenVision 为基础增量开发，保留原有功能；用户接受 Meta SDK 官方采集。源码静态审计、功能比较、开发副本改名及首次真机安装启动已完成；功能回归、眼镜音频和 API 调用仍待验收，见 [调试记录](todo/debug-status.md)。
