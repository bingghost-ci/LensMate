# 中英泰文字翻译与 iPhone 本地朗读

更新：2026-10-24。本批开发和非 UI 验证完成；真实阿里云联调与用户 UI/听感验收待完成。新版尚未安装到用户 iPhone。原有助手保留，翻译位于独立的「翻译」标签页。

## 配置与使用

1. 在「设置 → 翻译设置」或翻译页右上角打开配置。选择**中国（北京）**或**新加坡**，填入该地域的阿里云百炼（Model Studio）API Key，并确保账号已开通 `qwen-mt-flash`。首次使用不预选地域。
2. 点击「保存翻译设置」。保存只检查格式和 Keychain 写入，不调用接口，也不代表鉴权已通过。留空可沿用该地域保存的密钥；切换地域不会挪用另一地域的密钥。可单独移除所选地域的密钥。
3. 选择中文、英文或泰语的源/目标语言，输入文字（每次最多 2,000 个 Unicode 标量），点击「翻译文字」。同语言选择会交换另一端，始终保持有效方向。支持中↔英、中↔泰、英↔泰。
4. 页面显示原文和译文，默认自动朗读，可关闭自动朗读、停止请求/朗读、重播当前完成的上一句译文。编辑原文、交换方向或重新提交会清除旧结果，避免用错误方向重播。
5. 朗读只使用 iPhone 可用的 Apple 系统音色，通过当前系统音频输出播放。缺少目标语言音色时保留译文并提示下载；在系统辅助功能的朗读/声音设置下载后重播。无云端 TTS 回退，不使用第三方合成扩展或个人音色。

界面继续支持英文、简体中文和跟随系统；不支持的系统首选语言回退英文。翻译语言不受界面语言影响。

## 本轮接口契约

2026-10-24 核对阿里云官方文档：

| 项目 | 实现 |
|---|---|
| 北京 | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` |
| 新加坡 | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions` |
| 模型 | 固定 `qwen-mt-flash`，非流式 HTTP POST |
| 鉴权 | `Authorization: Bearer <所选地域的 API Key>` |
| 正文 | 单条 `user` 消息，仅本次文字；根对象 `translation_options.source_lang/target_lang` 使用 `Chinese`、`English`、`Thai` |
| 响应 | `choices[0].message.content`；要求 `finish_reason=stop`，拒绝空结果、拒绝回复和截断结果 |
| 时限 | 请求等待 30 秒、URLSession 总资源时限 35 秒；不自动重试收费请求 |

[Qwen-MT API 文档](https://help.aliyun.com/en/model-studio/qwen-mt-api)说明工作空间专属域名已推出，原共享域名继续有效；本批使用受支持的固定共享域名，不需要 Workspace ID，也不允许自定义上传地址。[模型信息](https://help.aliyun.com/zh/model-studio/qwen-mt-flash)列出北京和新加坡的模型服务；[语言与消息格式](https://help.aliyun.com/en/model-studio/machine-translation)及[地域密钥规则](https://help.aliyun.com/en/model-studio/get-api-key)是本轮适配依据。

## 隔离和生命周期

- `Services/Translation/` 包含请求、地域配置、专用 Keychain 存储、音频交接与系统朗读；`Views/Translation/` 包含页面和请求状态管理。
- 密钥按地域独立保存在 Keychain，使用 `WhenUnlockedThisDeviceOnly`；替换先原子更新，失败不删除旧值，也不写普通文件。UserDefaults 只保存地域。此规则不改变既有助手凭据机制。
- 请求入口不接受助手历史、图片、文档或工具参数。专用临时 URLSession 不保留缓存、Cookie 或 URL 凭据，拒绝所有重定向。新增代码不打印密钥、正文或服务端错误正文。
- 正文和译文只在当前进程内存中，不进入助手历史、设置、文件或遥测。退出页面取消任务并停止播放，内存里的输入和最后结果可供返回后查看；重新启动 App 后不恢复正文。
- 切换方向、编辑、提交新请求、停止、进入设置、切后台、音频中断和退出会取消旧任务。请求标识及活跃状态同时校验，即使传输层忽略取消，旧响应也不能覆盖或朗读。
- 进入翻译时停止助手监听、朗读、实时音频和已有录制；助手音频入口拒绝翻译期间的晚到工作。返回助手后由原页面恢复监听，翻译不自动恢复旧任务或播放。

本批不含 ASR、持续录音、后台翻译、眼镜专用路由、镜片字幕或持久翻译历史。

## 已执行的非 UI 验证

Xcode 27.1 / Swift 6.4，iPhone 18 Pro / iOS 27.0 模拟器测试宿主：完整构建成功；**171 项 XCTest 全部通过**，其中新增 26 项。覆盖六方向参数及最小请求、解析/错误/超时、URLSession 注入响应与真实任务取消、拒绝重定向、Keychain 真正读写及注入写入失败、旧响应/旧错误隔离、停止/重播、音色不可用和助手音频交接。未执行 UI 自动化、截图或视觉验收。

新增测试：`TranslationClientTests`、`TranslationConfigurationTests`、`TranslationSessionTests`。测试使用合成正文和隔离 Keychain 服务名，不使用用户密钥，不调用付费接口。

本机执行命令（从仓库根目录；模拟器 ID 和 DerivedData 路径按机器调整）：

```sh
xcodebuild -project ios/LensMate.xcodeproj -scheme LensMate \
  -destination 'platform=iOS Simulator,id=05581DD8-B185-4612-A56E-4748154E078C' \
  -derivedDataPath /Users/bobby/Library/Developer/Xcode/DerivedData/LensMate-bewuaglexxfjojenwptcxdczqcae \
  -disableAutomaticPackageResolution \
  -xcconfig .build/localization/signing.xcconfig \
  -testLanguage en -testRegion US -collect-test-diagnostics never test
```

临时签名配置沿用[调试记录](../todo/debug-status.md#中英文界面与语言选择2026-10-24)中的资源包处理方式；它不在 Git 中。首次克隆需先按 [iOS README](../ios/README.md)准备本地配置、依赖和签名。机器可正常签名时可省略临时 `-xcconfig`。本轮未修改 Vendor、依赖版本或正式签名设置。

## 待联调和用户验收

尚无本轮可用的地域/API Key，因此**未验证真实鉴权、翻译质量、实际网络延迟、额度或账单**。需要用户在 App 中保存所选地域的有效 Key，并开通该地域 `qwen-mt-flash`；不要把密钥写入仓库或聊天记录。

用户 UI 验收清单：

- 原助手、历史和设置仍可进入；中英文界面及跟随系统切换正常，新增页面文字随之切换，翻译方向保持独立。
- 用短句逐一验收六个方向，检查原文/译文、键盘关闭、长文滚动及自动朗读；确认中文、英文、泰语音色和听感，缺音色时提示明确。
- 连续提交、立即交换方向、编辑、停止、切标签或锁屏/切后台后，没有旧结果覆盖或旧声音恢复；重播只读当前完成的译文。
- 在助手正在回复时打开翻译，再返回助手，确认不叠音且助手可以继续使用。真实电话、蓝牙及眼镜路由矩阵另行验收。
- 保存后重启仍保留地域与 Key；错误地域/Key 显示鉴权提示；删除密钥后无法发起翻译；App 重启不恢复正文，助手历史不出现翻译内容。

UI、听感和缺凭据的真实接口验收不阻塞本轮开发 goal 交付，未通过前不宣称产品整体已验收。
