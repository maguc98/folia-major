# Folia iOS 3.0.6 (build 379) — 前端模块与视觉引擎架构图

> 分析对象：用户提供的 `iPad-Folia-3.0.6-build379-正式版.ipa` 中的 `Payload/App.app/public` 前端产物。本文描述的是对打包后 JavaScript/CSS 的静态分析，不代表已取得上游完整 TypeScript/React 源码，也不代表已完成真机运行验证。

## 1. 前端启动与模块分层

从 `public/index.html` 可见，页面入口加载运行时配置与主 bundle。主 bundle 再通过 Vite/Rolldown 生成的动态依赖映射按需加载功能模块。当前包内可确认的主要层次：

1. **启动层**：`index.html`、`runtime-config.js`、`assets/main-D3qKLyAO.js`。
2. **应用/状态层**：播放状态、视觉设置状态、语言/主题、应用表面与播放器 UI。
3. **注册与扩展层**：`registry-Bz6vMSgM.js` 提供按模块 ID 注册、注销、订阅的通用注册表；`providerRegistry-H9rGE1g_.js` 管理音乐服务提供方。
4. **视觉器宿主层**：`visualizerRender-7g3yQ2HV.js`、`VisualizerShell-pwlsfb6R.js`、`FoliumMountHost-DRdJZquh.js`、`stageContext-I-Zv8dj6.js`。
5. **具体视觉引擎层**：各个 Visualizer 组件及其动态导入的 Pixi runtime。
6. **图形基础设施层**：Pixi 加载器、纹理预算、场景缓存、歌曲切换、滤镜/后处理、RenderTargetSystem/WebGPU 相关 bundle。

这意味着视觉引擎并非全部写在一个主 bundle 中；具体引擎有独立模块，且由宿主/注册机制承载。

## 2. 视觉模式清单

`visualizerModes-BLSl_Jg6.js` 导出的模式白名单包含以下 17 项：

`cadenza`, `cappella`, `claddagh`, `classic`, `diorama`, `fume`, `hanabi`, `lumiere`, `machi`, `monet`, `nebbia`, `partita`, `pendolo`, `sonnet`, `still`, `tempera`, `tilt`。

同一模块还定义了背景来源白名单：`common`, `latent`, `monet`, `nomand`, `sora`, `url`；默认视觉模式标识为 `classic`，默认背景来源标识为 `latent`。该模块包含清单一致性校验：模式目录与类型清单不一致时会抛出错误。因此新增/删除模式时，不能只增加 UI 选项，还要同步模式白名单及对应目录/注册项。

## 3. 视觉引擎调用链

可从 bundle 的静态依赖关系确认以下调用链：

```text
主应用 / 视觉设置
  └─ visualizerRender
       ├─ VisualizerShell
       ├─ stageContext（把歌词、播放时间、主题、歌曲元数据、显示设置整理为上下文）
       ├─ FoliumMountHost（以 modId / entryKind / entryId 挂载注册项）
       └─ VisualizerSubtitleOverlay（宿主侧字幕叠层）

具体 Visualizer 组件
  └─ 动态导入各自的 Pixi runtime
       ├─ Tempera → createTemperaPixiRuntime → TemperaPixiRuntime
       ├─ Sonnet  → createSonnetPixiRuntime  → SonnetPixiRuntime
       └─ Hanabi  → createHanabiPixiRuntime  → HanabiPixiRuntime
```

上述三个 runtime 文件均有独立导出类，且有自己的生命周期方法。静态代码中可见共同的生命周期形态：创建/维护 Pixi Application 与场景；响应尺寸/旋转、调谐参数、暂停状态和歌曲切换；在销毁时停止 ticker、断开 ResizeObserver、清理场景/纹理并销毁 renderer。各引擎的具体场景和资源管理并不相同，不能把它们视为同一套渲染实现的简单换皮。

### 3.1 Tempera

- 入口组件：`VisualizerTempera-DFp2mVg4.js`。
- runtime：`createTemperaPixiRuntime-Bp9vMtyn.js`，导出 `TemperaPixiRuntime`。
- 依赖包括 `pixiDisplayResources`、`pixiTextureBudget`、`stageLayers`、`wordColoring`、`visualSeedHash`、`layout`、滤镜/后处理、Pixi loader、旋转暂停辅助、场景缓存与歌曲切换模块。
- runtime 的 `setTuning` 会根据调谐配置决定是否清空/重建场景，并更新 renderer resolution；`setPaused` 会停止或启动 ticker；`destroy` 会清理场景缓存、credits、overlay、纹理与 Pixi Application。

### 3.2 Sonnet

- 入口组件：`VisualizerSonnet-D1_NnFeq.js`。
- runtime：`createSonnetPixiRuntime-CWaPqi02.js`，导出 `SonnetPixiRuntime`。
- 依赖包括歌词段落结构、字素/词语时间、字幕字号、滤镜与后处理、纹理预算、Pixi loader、旋转暂停辅助、场景缓存和歌曲切换。
- runtime 具有独立的调谐、调制、暂停、歌曲切换与销毁处理；其代码还管理活动镜头/段落状态及图标纹理 URL。
- Sonnet 不只是普通 DOM 排版：其 runtime 依赖 Pixi 与后处理模块，属于图形渲染路径。

### 3.3 Hanabi

- runtime：`createHanabiPixiRuntime-07zHvtwV.js`，导出 `HanabiPixiRuntime`。
- 该 runtime 体量明显较大，并动态依赖 Pixi 核心 bundle、Shader、RenderTargetSystem、VividLightBlend 等图形模块。
- 静态代码可见其处理歌曲切换、场景缓存、屏幕 Bloom、纹理回收，以及 iOS 原生环境下的 orientationchange/resize 事件。
- 销毁阶段会清理重建/旋转定时器、监听器、场景、滤镜、纹理和 Pixi Application。

> 说明：本次提取到的文件可明确证明 Tempera、Sonnet、Hanabi 的 runtime 文件和导出类。其他模式名称虽在白名单中，但不能仅凭白名单断言它们都使用同一种 Pixi runtime；需要逐个追踪对应入口与动态依赖。

## 4. Pixi 图形基础设施

### 4.1 纹理预算

`pixiTextureBudget-DiET7mUc.js` 提供纹理尺寸取整和分辨率选择逻辑。其核心函数会在候选分辨率之间比较纹理像素总量，并在给定预算比例内选择可行值。它是性能控制的一个明确切入点，但不应未经测量就直接降低全局分辨率，因为不同引擎的画面质量/内存占用不同。

### 4.2 场景与歌曲切换

多个 runtime 引用了 `pixiSceneCache` 与 `pixiSongSwap`。从调用关系看，场景缓存、歌曲切换过渡与引擎自身场景对象相互协作。修改切歌、暂停、旋转或纹理释放时，应同时检查这些共享模块，避免只修单个视觉器造成生命周期不一致。

### 4.3 RenderTarget / WebGPU

包内存在独立的 `RenderTargetSystem-D03dw60A.js`，并被 Hanabi 相关图形依赖引用。该模块实现 render target 绑定、viewport/frame 计算、mip/layer 选择、render pass 启动与清理等底层工作。它属于 Pixi 图形基础设施，不是 Folia 的业务 UI 组件。对其做补丁风险较高，应先确认问题是否来自上层资源尺寸/生命周期，再考虑改动底层。

## 5. 音乐 Provider 注册与能力

`providerRegistry-H9rGE1g_.js` 是体积很大的独立模块，负责在线音乐源的注册、查询和能力判断。静态代码中可见统一的 provider 对象形态，包括 `id`、显示名、`getAvailability`、`capabilities`，以及按需提供的 `search`、`playback`、`lyrics`、`library`、`mutations`、`auth` 等接口。注册表通过 `registerProvider` 类似的内部注册流程收集 provider，并提供按 ID 获取、枚举和订阅变化的函数。

在当前包中明确识别到的 provider ID 包括：

- `netease`：网易云音乐。能力对象包含搜索、播放、歌词、认证、用户库、歌单、专辑、艺人、推荐、变更、逐字歌词、云盘等多项能力。
- `kugou`：酷狗音乐。包含搜索、播放、歌词、认证、用户库、歌单、专辑、艺人、推荐、逐字歌词、云盘等能力。
- `qq`：QQ 音乐。包含搜索、播放、歌词、认证、用户库、歌单、专辑、艺人、变更、逐字歌词等能力；该对象的推荐能力在代码中为 false。
- `bodian`：波点音乐。代码中提供搜索、播放、歌词、认证、歌单、专辑、艺人、推荐、用户库、收藏和歌单曲目变更等能力。
- `appleMusic`：Apple Music。能力对象包含搜索、播放、歌词、逐字歌词、认证、用户库、歌单、专辑、艺人、推荐、收藏和歌单曲目变更等；其请求通过 `appleMusicRequest` 原生桥接动作执行。
- 汽水音乐 provider：通过原生桥接请求；能力对象包括搜索、播放、歌词、逐字歌词、认证、用户库、歌单、专辑、艺人、推荐和收藏等。
- 飞牛音乐：能力对象声明了搜索、歌词、认证、用户库、歌单、专辑、艺人、收藏等，但 `playback` 能力为 false；其实现通过原生桥接调用飞牛服务端。

Provider 能力字段表示应用层声明/可用接口，不等同于某个用户已登录、某首歌一定可播放或远端服务当前可用。实际可用性还要看 `getAvailability`、登录状态、后端响应和具体曲目。

## 6. 与 iOS 原生桥接 / NodeMobile 的关系

当前 iOS bundle 还通过独立桥接接口访问原生能力。已确认的前端消息 handler：

- `window.webkit.messageHandlers.foliaPlayer`：原生播放控制命令与事件回传。
- `window.webkit.messageHandlers.foliaProviderAuth`：Apple Music、飞牛音乐等认证/请求桥接。

Provider 层中的汽水音乐、飞牛音乐和 Apple Music 相关调用会经由请求 Promise/ID 回调封装转入原生桥接；NodeMobile 后端则承载本机服务端口与部分第三方音乐 API 适配。两条路径不能混为一谈：某个 provider 请求走原生消息 handler，并不意味着该请求必然由 NodeMobile 的本机 HTTP 服务处理。

## 7. 可安全推进的修改切入点

按风险从低到高建议：

1. **配置/展示层**：视觉设置默认值、模式说明、字幕显示参数等；先验证设置 store 与具体 runtime 的参数传递。
2. **单个视觉器 runtime**：对 Tempera/Sonnet/Hanabi 做局部性能或生命周期修复，先保持接口和共享模块不变。
3. **共享视觉基础设施**：纹理预算、场景缓存、歌曲切换、旋转暂停；必须做跨引擎回归。
4. **Pixi/WebGPU 底层**：RenderTargetSystem、shader、renderer 适配；最后处理，需有设备矩阵与真机日志。
5. **Provider 层**：先核对 capability、availability、auth、playback 与本机桥接映射，再修改 provider；不要只改 UI 的能力开关。

## 8. 当前证据边界与下一步工程建议

- 当前证据来自 IPA 内的打包 JavaScript 静态分析；没有 sourcemap，无法直接恢复原始 TypeScript/React 项目结构和注释。
- 这些文件名与模块关系适合做“补丁定位图”，但不能替代作者提供的原始前端工程。
- IPA 中缺少完整 Xcode/Swift 工程，因此即使前端资源可替换，也不能据此独立重建原作者的完整 iOS App。
- 下一步应向原作者取得 iOS 原生工程、签名/构建配置说明（私钥不应进入仓库）以及前端原始源码/构建脚本。若无法取得，则另建可维护的 Capacitor/WKWebView wrapper，并明确标记为新 wrapper，而非声称复刻原生工程。
- 当前建议把本文件作为 build 379 的架构基线；任何修改都记录原始文件 SHA、补丁、测试设备/iOS 版本与回归结果。
