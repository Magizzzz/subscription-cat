# 订阅猫 Subscription Cat

一款使用 SwiftUI 和 SwiftData 开发的 iPhone 订阅管理应用。手动记录订阅费用、周期和到期时间，在本机查看钱包、统计和提醒。

## 功能

- 手动管理订阅、归档与恢复，按分类浏览和统计。
- 通过本地通知提醒到期；支持导出和恢复 JSON 备份。
- 提供订阅体检和分享海报。
- 本地存储、无需登录；导出的备份未经加密，请妥善保管。

项目仍在开发中，真机通知、无障碍和完整界面流程尚需进一步验证。截图识别导入等规划功能不应视为已经完成。

## 运行

需要支持 iOS 17 或更新版本的 Xcode 和 iOS SDK。打开 `SubscriptionWallet.xcodeproj`，选择 `SubscriptionWallet` scheme 和模拟器运行。真机运行需在 Xcode 中配置自己的签名与 Bundle Identifier。

```sh
xcodebuild -project SubscriptionWallet.xcodeproj -scheme SubscriptionWallet \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

项目不依赖第三方包。修改源文件列表后可运行 `python3 scripts/generate_project.py` 重新生成工程；该脚本也是项目构建配置的来源。

## 素材与许可

源代码按 [MIT License](LICENSE) 开源。第三方品牌图标、服务名称和商标属于各自权利人，不属于本项目的 MIT 授权范围；图标来源见 [品牌图标说明](docs/brand-icons.md)。使用或再分发这些素材时，请自行确认相关权利。应用名称与图形标识并不暗示任何第三方背书。
