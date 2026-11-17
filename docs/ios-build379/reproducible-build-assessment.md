# Folia iOS build 379 — 导入与可重复构建评估

## 1. 本地清理包完整性记录

针对原始 IPA 的 `public/` 目录制作了第二版公开资源快照。该快照仅包含 Web/NodeMobile 资源，不包含 IPA 的原生可执行文件与 Frameworks。

| 项目 | 已记录值 |
|---|---:|
| 清理包 | `Folia-iOS-3.0.6-build379-public-sanitized-v2.zip` |
| ZIP 大小 | 41,823,396 bytes |
| SHA-256 | `f8e08042914a01f63f8aabbadd9f61cca32dd92fd45cfe194495f1e40acbab32` |
| 文件数 | 8,421 |
| 解压总大小 | 103,639,746 bytes |
| JavaScript 文件数（全树） | 4,939 |
| CSS 文件数（全树） | 13 |
| package.json 数量 | 475 |

这些计数覆盖整个 `public/` 树，包括随包分发的 `node_modules/`，不是只统计顶层应用 bundle。它们是归档快照的静态盘点值，不是运行测试结果。

## 2. 目前可复用的构建材料

| 层 | 当前拥有的材料 | 能否独立重建原版 IPA |
|---|---|---|
| Web 前端 | 编译后的 `public/`、HTML/CSS/JS 资源 | 否；缺少原始前端源码与构建配置 |
| NodeMobile 服务 | `nodejs-project/main.js`、桥接 JS、随包 node_modules | 可做独立 Node 语法/逻辑检查；不能单独生成 iOS App |
| 原生壳 | IPA 中的编译 Mach-O、Capacitor/Cordova/NodeMobile Frameworks | 否；缺少完整 Xcode 工程与 Swift 源码 |
| 签名 | 原 IPA 的签名元数据（已从公开资源快照排除） | 否；没有可用的签名身份，也不应将私钥放进仓库 |

## 3. 建议的仓库目录约定

拿到作者原始工程后，建议整理成以下结构；在取得源码前，不要把二进制反编译产物伪装成源码：

```text
ios-build379/
  reference/
    package-metadata.json
    checksums.txt
  web/
    public/                 # 当前清理包的 Web/NodeMobile 资源
  native/
    Folia.xcodeproj/        # 等作者提供
    Sources/                # 等作者提供
    Frameworks/             # 按作者工程/依赖管理方式恢复
  patches/
    web/
    native/
  scripts/
    verify-payload.sh
    replace-web-assets.sh
  docs/
    provenance.md
    build-and-sign.md
```

在原生工程未取得前，`native/` 应保持明确的 TODO/缺失状态，不应创建一个空壳工程并称其为原版工程。

## 4. 资源替换的安全原则

1. 原始 IPA 保持只读；所有变更从 `ios-build379-baseline` 分支进行。
2. 每次修改前记录目标文件原始 SHA-256、补丁内容和来源。
3. 替换 Web 资源时只覆盖 `App.app/public/` 对应资源，不触碰可执行文件、Frameworks、签名目录或 provisioning profile。
4. 若后续使用新的 Capacitor wrapper，必须单独命名为重建 wrapper，并重新实现/验证原生消息桥接；不能把它标成原作者原版壳。
5. 不把 Apple Music/QQ/汽水等登录态、设备标识、token、证书或私钥纳入仓库。
6. 不在未验证依赖许可的情况下删除第三方 license/NOTICE 文件。

## 5. 可执行验证分层

### A. 归档验证（当前可做）
- 对 ZIP 校验固定 SHA-256。
- 检查归档路径不包含绝对路径或 `..`。
- 检查敏感认证状态、签名材料与私钥路径是否存在。
- 解压后确认 `public/index.html`、`assets/`、`nodejs-project/` 存在。

### B. 前端静态验证（当前可做）
- 检查 HTML 引用的本地资源均存在。
- 对主要 JS/CSS 文件执行静态扫描与语法检查（需按 bundle 语法目标选择工具）。
- 检查 runtime config 是否由部署/启动流程注入。
- 对修改过的单个视觉器做资源差异和依赖完整性检查。

### C. Node 后端验证（部分可做）
- 在匹配 Node 版本下执行语法检查与单元测试。
- 使用 mock/stub 验证路由、代理目标校验、认证状态读写和媒体 Range 行为。
- Node 22 的 `node --check` 通过不等于 iOS NodeMobile 18 真机运行通过。

### D. iOS 构建与真机验证（当前阻塞）
- 必须取得原作者 Xcode 工程、构建脚本、Framework 集成方式和最低部署配置，或正式决定采用独立的新 wrapper。
- 必须在 macOS/Xcode 环境执行 archive/export。
- 使用用户自己的签名身份在本地或受控 CI 签名；私钥不得提交仓库。
- 真机验证原生播放器、后台音频、远程控制、Provider 登录桥、NodeMobile 本机服务和各视觉引擎。

## 6. 当前阻塞与解除条件

**阻塞 1：完整原生工程缺失。** 解除条件：作者提供 Xcode 项目/Swift 源码及依赖配置，或用户明确选择独立新 wrapper 路线。

**阻塞 2：二进制清理包尚未进入 GitHub。** 当前连接没有可用的 Release asset/Git LFS 上传动作。解除条件：通过 GitHub 网页/桌面客户端或其他二进制上传方式将 v2 ZIP 放到仓库 Release，再将 HTTPS 资产地址交给已有 Actions workflow。

**阻塞 3：没有完成原生真机回归。** 解除条件：取得可构建工程并在目标 iPhone/iPad 和目标 iOS 版本上执行测试。

## 7. 本轮结论

目前已具备 build 379 的静态分析基线、清理后的 Web/NodeMobile 资源归档和自动分析 workflow。还不具备从仓库直接产出与原 IPA 等价的可签名 IPA 的条件。下一阶段应优先完成二进制资源归档入库，并向原作者取得原生工程；若原作者无法提供，再评估新 wrapper 方案。
