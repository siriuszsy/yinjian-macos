# 音键源码发布说明

最后更新：2026-04-11

## 1. 发布策略

当前仓库只发布：

- 源码
- 设计文档
- 架构文档
- 编译说明
- 权限说明

当前仓库不发布：

- `.app` 二进制
- 本地签名证书
- 本地私钥
- 本地 API Key

这是有意为之。  
当前项目仍然依赖本地签名、权限授权和系统级 Accessibility 行为，直接公开二进制并不能给普通用户带来稳定安装体验。

## 2. 如何从源码编译

前提：

- macOS
- Xcode
- 阿里云百炼 API Key

### 2.1 直接构建

```bash
xcodebuild -project tinyTypeless.xcodeproj \
  -scheme tinyTypeless \
  -configuration Debug \
  -derivedDataPath .derived \
  build
```

### 2.2 运行

构建产物默认在：

```text
.derived/Build/Products/Debug/tinyTypeless.app
```

如果只是本地调试，可以直接从 Xcode 运行。

## 3. API Key

本项目使用阿里云百炼：

- `qwen3-asr-flash`
- `qwen3.5-flash`

API Key 不会写进仓库。  
运行后在设置页里填入你自己的百炼 `API Key` 即可。

## 4. 权限说明

### 4.1 麦克风

作用：

- 录音

不开就不能说话录制。

### 4.2 辅助功能

作用：

- 获取当前焦点输入位置
- 把整理后的文本写回当前输入框

不开的话，ASR 和 cleanup 仍然可能工作，但最终文字无法稳定写回别的 app。

### 4.3 键盘监听

作用：

- 监听 `Fn` / 右侧 `⌥` 这类全局单键触发

当前开发版默认触发键是：

`⌘ + ;`

所以当前版本默认不依赖键盘监听权限。

## 5. 苹果编译与本地签名说明

项目里保留的本地签名脚本，主要是为了处理苹果本地编译、调试签名和权限稳定性问题。

它的用途是：

- 让本地调试版 `.app` 更稳定地运行
- 降低辅助功能权限漂移
- 方便重复构建后的本地测试

如果你只是本地开发，Xcode 自带的本地运行签名通常就够了。  
如果你需要更稳定地处理辅助功能权限，建议：

- 保持 `Bundle Identifier` 稳定
- 保持 `.app` 安装路径稳定
- 不要一边测权限一边频繁改 app 身份

当前仓库保留了本地签名脚本，但不会公开任何证书和密码。

如果你使用 `vibe coding` 方式接手项目，这部分可以按文档来做，不需要自己重新发明一套签名流程。

如果你确实要自己处理本地签名，先看：

- [Vibe Coding 开发说明](./vibe-coding-guide.md)

## 6. 界面预览素材建议

如果你要把仓库整理成更适合浏览的 GitHub 主页，推荐配这几类图：

1. 设置页截图
2. 录音态截图
3. 思考中截图
4. 一段短 GIF，展示 `按住说话 -> 松开 -> 出字`

当前仓库已有 HTML 原型，可作为预览参考：

- `prototypes/floating-orb/index.html`
- `prototypes/ui-states/index.html`

## 7. 公开仓库前必须确认的清单

1. `.derived` 不进入仓库
2. `codesign/` 下的证书和私钥不进入仓库
3. 本地 API Key 不进入仓库
4. README 使用外部名称 `音键`
5. 不在 README 中承诺提供现成二进制安装包

## 8. 当前推荐的公开方式

推荐：

- GitHub 仓库公开源码
- Release 只放源码压缩包和文档

当前不推荐：

- 直接提供面向大众的 `.app` 安装包

等后续如果做 `Developer ID + notarization`，再考虑提供稳定的可安装版本。
