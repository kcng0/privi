# 视频播放体验与性能调研

日期：2026-10-18。来源：官方文档与固定版本源码。范围：Android 本地视频、倍速、seek、预览、输出与测量；iOS 单独验证。

目前应优先处理真实解码和视频输出路径。用户已确认 Samsung A52 上的 1080p 视频在菜单 2× 和长按 2× 都严重掉帧，松手恢复也会停顿。上一轮减少手势回调、重建和预览开销，没有消除这个实际症状。不能再用调用次数正确或一次播放成功来证明流畅。

## 结论与实施顺序

| 优先级 | 做法 | 对 Privi 的含义 |
|---|---|---|
| P0 | 确认实际 decoder、hwdec 和输出路径 | “开启硬件加速”不表示使用直接硬解；记录选中结果 |
| P0 | 对已知格式优先低拷贝路径 | 旧 mpv 的直接输出有 8-bit 限制，必须保护 HDR、10-bit 和未知格式 |
| P0 | 同片段比较 1×、2×、长按和恢复 | 分别记录媒体时间、原生掉帧、命令耗时和实际画面 |
| P0 | 预加载和预览让位于当前播放 | 当前加一个 controller 是上限，不是始终占两个 decoder 的性能目标 |
| P1 | 评估旧 native 的倍速能力缺口 | codec operating-rate、音频时间伸缩与输出 deadline 不等于一个 speed 属性 |
| P1 | 有 GPU 瓶颈证据后再做原生 Surface 原型 | 验证控件叠层、字幕、画幅、旋转、PiP 和锁屏，不直接替换架构 |

## 直接硬解和格式兼容

成熟播放器区分“硬件解码”和“直接输出”。VLC Android 3.7.2 的仅解码模式显式禁用 MediaCodec direct rendering；mpv-android 2026-09-17 默认依次尝试 `mediacodec,mediacodec-copy`，并使用移动设备 `fast` profile。这些是产品源码中的实践，不是对旧 native 和 Flutter 输出的性能承诺。[VLCOptions](https://github.com/videolan/vlc-android/blob/3.7.2/application/resources/src/main/java/org/videolan/resources/VLCOptions.kt#L293-L314)、[mpv-android 配置](https://github.com/mpv-android/mpv-android/blob/2026-09-17/app/src/main/java/is/xyz/mpv/MPVView.kt#L18-L35)、[硬解列表](https://github.com/mpv-android/mpv-android/blob/2026-09-17/app/src/main/java/is/xyz/mpv/MPVView.kt#L396-L400)

Privi 当前锁定的 mpv 是 `78d43740f52db817d98bcf24fb30a76ab6fa13ff`。该版本将 `mediacodec-copy` 列入 `auto-safe` 名单，而直接 `mediacodec` 不在名单中。media_kit_video 的实体设备默认 `auto-safe` 因而排除了直接路径；可能使用拷贝式硬解，也可能软解。A52 实际选择哪条路径，仍需 `hwdec-current` 证据。[固定 mpv 的选择逻辑](https://github.com/mpv-player/mpv/blob/78d43740f52db817d98bcf24fb30a76ab6fa13ff/video/decode/vd_lavc.c#L237-L255)

直接路径经 MediaCodec、AImageReader、AHardwareBuffer 导入 EGL，避免拷回 CPU 内存，但仍有颜色转换、GPU 渲染、Flutter 合成和同步成本。这个旧版本还明确把 direct 输出改为 RGB0/8-bit；HDR、10-bit、广色域可能发生不报解码错误的画质退化。不能依靠软件回退自动发现颜色错误。[固定 mpv 的 AImageReader 实现](https://github.com/mpv-player/mpv/blob/78d43740f52db817d98bcf24fb30a76ab6fa13ff/video/out/hwdec/hwdec_aimagereader.c#L254-L272)

本轮实现因此限定为：暂停初始化时，只有 SDK 选择 `auto-safe`、实际为 `mediacodec-copy`，且原始 `video-dec-params` 明确表示常见 8-bit SDR，才尝试 `mediacodec,auto-safe`。未知、软件解码、模拟器、10-bit/HDR 和广色域保持原路径。不能用平均 bpp 判断分量位深：8-bit YUV420 的平均 bpp 本来就是 12。

这里必须读取原始解码参数。`video-params` 已经经过 mpv 颜色补值，未知 1080p 会被补成 BT.709 / BT.1886，不能据此宣称源信息已知。独立审查发现并纠正了这个区别，回归用例覆盖 raw unknown / normalized SDR 的组合。[decoder wrapper](https://github.com/mpv-player/mpv/blob/78d43740f52db817d98bcf24fb30a76ab6fa13ff/filters/f_decoder_wrapper.c#L624-L637)、[颜色猜值](https://github.com/mpv-player/mpv/blob/78d43740f52db817d98bcf24fb30a76ab6fa13ff/video/mp_image.c#L889-L929)

修改 `hwdec` 会重建 decoder 并排队 seek，所以不能在每次长按、菜单改速或松手时切换。初始化期间的一次选择也要测启动时延和预加载成本。[固定 mpv 的运行时切换](https://github.com/mpv-player/mpv/blob/78d43740f52db817d98bcf24fb30a76ab6fa13ff/player/command.c#L7100-L7107)

## 倍速要处理整条链路

Media3 1.11.1 按已知流帧率乘目标播放速度计算 codec operating rate，并把倍速传给 frame-release 控制。Android `KEY_OPERATING_RATE` 是资源规划和运行点提示，不保证吞吐，也不是强制提频。[运行速率计算](https://github.com/androidx/media/blob/1.11.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/video/MediaCodecVideoRenderer.java#L1614-L1635)、[更新 codec](https://github.com/androidx/media/blob/1.11.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/mediacodec/MediaCodecRenderer.java#L846-L852)、[更新输出节奏](https://github.com/androidx/media/blob/1.11.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/video/MediaCodecVideoRenderer.java#L1470-L1480)、[Android MediaFormat](https://developer.android.com/reference/android/media/MediaFormat#KEY_OPERATING_RATE)

当前发布 APK 的 libmpv 没有发现 `operating-rate` / `operating_rate` 字符串。这是二进制检查结果，不是完整的 API 不存在证明；至少不能假定通过 mpv `setProperty` 就能获得 Media3 的行为。升级 native 或修改 FFmpeg MediaCodec 桥，需要独立验证 ABI、codec、字幕、颜色与生命周期。

保持音调需要时间伸缩。media_kit 的 `pitch=false` 仅表示没有启用其独立 pitch 控制，不表示关闭 mpv 音高校正。旧 mpv 在倍率变化时自动插入、drain 和移除 scaletempo2；它和已有音频输出缓冲是回速停顿的候选，尚未被测量确认为根因。不能先关闭音调、盲调音频缓冲或改变同步方式来宣称修复。[固定 mpv 滤镜切换](https://github.com/mpv-player/mpv/blob/78d43740f52db817d98bcf24fb30a76ab6fa13ff/filters/f_auto_filters.c#L315-L355)、[Media3 的默认 pitch](https://github.com/androidx/media/blob/1.11.1/libraries/common/src/main/java/androidx/media3/common/PlaybackParameters.java#L41-L58)

长按应保存原倍率，开始和结束各提交必要的变化，取消、后台和切媒体时防止旧异步请求覆盖恢复。VLC 的保存和恢复行为是现成参考；Privi 还必须保留自身锁屏/PiP 权限合同。[VLC 长按与恢复](https://github.com/videolan/vlc-android/blob/3.7.2/application/vlc-android/src/org/videolan/vlc/gui/video/VideoTouchDelegate.kt#L197-L250)

## decoder 资源与预览

Android 明确区分格式支持与实时性能：`getSupportedFrameRatesFor()` 不是性能指标；厂商提供的 achievable frame rates / performance points 也可能缺失。PerformancePoint 需要考虑活跃实例总负荷，`getMaxSupportedInstances()` 只是上界提示，不保证当前资源可用。[VideoCapabilities](https://developer.android.com/reference/android/media/MediaCodecInfo.VideoCapabilities)、[PerformancePoint](https://developer.android.com/reference/android/media/MediaCodecInfo.VideoCapabilities#getSupportedPerformancePoints())、[最大实例数](https://developer.android.com/reference/android/media/MediaCodecInfo.CodecCapabilities#getMaxSupportedInstances())

Media3 将预取元数据/压缩数据与额外 renderer 预热分开。Privi 应比较仅当前、加下一个、加缩略图三种状态，只有证明竞争后才调整后台工作策略；不能只增加 controller 池或缓存。[预加载概念](https://developer.android.com/media/media3/exoplayer/preloading-media/preloadmanager/concepts)、[renderer 预热](https://github.com/androidx/media/blob/1.11.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/DefaultRenderersFactory.java#L288-L312)

准确 seek 通常要从前面的 I-frame 开始解码，再丢弃到目标前的画面。长 GOP 的成本无法通过减少 Dart 回调消除。VLC 横划在移动时只更新目标，抬手才提交跳转，符合本项目已经采用的交互方向。[Media3 seek 原理](https://developer.android.com/media/media3/exoplayer/troubleshooting#why-is-seeking-in-my-video-slow)、[VLC MOVE/UP 与提交](https://github.com/videolan/vlc-android/blob/3.7.2/application/vlc-android/src/org/videolan/vlc/gui/video/VideoTouchDelegate.kt#L229-L267)

时间轴缩略图可用 `OPTION_CLOSEST_SYNC` 与 scaled frame API；`OPTION_CLOSEST` 通常更贵。小 bitmap 只减少结果内存/传输，SDK 不保证底层按小分辨率解码。Privi 的 110ms 节流、单活跃任务、只保留最新目标、16 帧/2MiB 是项目调度选择，不是官方最优数字，也不覆盖 MMR 内部全部资源。[MediaMetadataRetriever](https://developer.android.com/reference/android/media/MediaMetadataRetriever#getScaledFrameAtTime(long,int,int,int))

## 输出路径与体验

Media3 优先推荐 SurfaceView，原因包括较低功耗、帧时序、HDR 和安全输出；mpv-android 也直接继承 SurfaceView。但 Flutter Texture 不能直接等同 Android TextureView，更不能直接套用其固定功耗差值。必须实测当前 SurfaceProducer、mpv GPU 与 Flutter 合成。[Media3 Surface](https://developer.android.com/media/media3/ui/surface)、[AOSP 合成架构](https://source.android.com/docs/core/graphics/arch-tv)、[mpv-android BaseMPVView](https://github.com/mpv-android/mpv-android/blob/2026-09-17/app/src/main/java/is/xyz/mpv/BaseMPVView.kt#L11)、[Flutter SurfaceProducer](https://api.flutter.dev/javadoc/io/flutter/view/TextureRegistry.SurfaceProducer.html)

若 direct 后仍有合成瓶颈，再原型比较原生 surface。验收必须包含字幕、Flutter 控件叠层、旋转/SAR、contain/cover/fill、裁剪、PiP、锁屏黑屏与退出恢复。方向和画幅按既有合同处理，不能借优化改变图片比例。

手势每次只能由一个操作持有；横向 seek、纵向调节、长按和双击不能并发提交。保留系统边缘手势区域，并提供可见按钮替代操作；Android 推荐触摸目标至少 48×48dp。[VLC 手势状态](https://github.com/videolan/vlc-android/blob/3.7.2/application/vlc-android/src/org/videolan/vlc/gui/video/VideoTouchDelegate.kt#L392-L435)、[Android 无障碍](https://developer.android.com/guide/topics/ui/accessibility/apps)

## 如何证明改善

三种证据要分别解释：

1. Flutter `FrameTiming` 说明 UI build/raster 耗时，不是视频输出 FPS；使用 profile/release。[FrameTiming](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html)
2. mpv decoder/VO 掉帧和真实 `speed`、`hwdec-current`、`avsync` 描述 native 状态。缺失指标明确标未知；源 FPS、估计帧号和媒体时钟前进都不能替代最终视频帧。[mpv 属性](https://mpv.io/manual/stable/#properties)
3. 实际呈现需要核对视频 PTS、surface/合成层或画面记录。Media3 rendered 计数在释放 buffer 后递增；MediaCodec frame 回调可延迟/批量，Android 14 以前可能漏报；Perfetto FrameTimeline 也有 SurfaceView 覆盖限制。[Media3 提交计数](https://github.com/androidx/media/blob/1.11.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/video/MediaCodecVideoRenderer.java#L2438-L2477)、[MediaCodec 回调](https://developer.android.com/reference/android/media/MediaCodec.OnFrameRenderedListener)、[Perfetto 限制](https://perfetto.dev/docs/data-sources/frametimeline)

29.97fps 的影片 2× 每秒约处理 59.94 个源帧；59.94fps 的影片 2× 则约处理 119.88 个。60Hz 屏幕无法展示后者全部帧，合理的输出省帧与积压造成的冻结需要分开判断。不要把“1080p”单独当作负载说明。

分别记录首帧等待、seek 到正确画面的等待和正常播放再缓冲，避免用一个总卡顿数掩盖原因。[Media3 Analytics](https://developer.android.com/media/media3/exoplayer/analytics)

### 本仓库的独立 profile

实机用户还可在播放设置的“高级”面板点击“复制播放诊断信息”，按需复制实际倍率、hwdec、原始/归一化色彩参数、源帧率和 native 掉帧计数。它不读取影片路径、文件名、字幕内容或设备名称，不自动发送，也不在播放期间轮询。累计掉帧仍不能单独代表最终屏幕 FPS。

`scripts/run-playback-rate-profile.sh` 使用 60 秒合成 1080p24 BT.709 SDR H.264/AAC，执行 1×、菜单等价 2×、真实 Android 持触 1→2×、2×下不改变速率的持触，以及释放后的测量。它保存命令耗时、native 属性、掉帧增量、surface 变化、Flutter 帧耗时和截图。可选录屏会额外增加编码负载，录屏 PTS/framemd5 不能直接解释为无干扰的视频 FPS。

profile APK 使用独立包名 `com.privi.app.playbackprofile`；脚本在安装前核对实际 APK，不覆盖已安装的私密库。仅使用测试临时目录和合成媒体，不读取用户影片，不上传测试设备数据。

```bash
# 已配置本地 Flutter/Android SDK，且已连接自己的测试设备。
ANDROID_SERIAL=<serial> PROFILE_HWDEC=auto-safe bash scripts/run-playback-rate-profile.sh
ANDROID_SERIAL=<serial> PROFILE_HWDEC=auto bash scripts/run-playback-rate-profile.sh
```

上述 override 是诊断实验，特别是 `auto` 不适合作为所有格式的生产配置。正式策略应继续保护 HDR/10-bit。profile 工具不设置武断的模拟器 FPS 门槛，也不把零 VO drop 当作最终没有掉帧的证明。

### A52 最小验收矩阵

固定亮度、供电、刷新率和后台负载，记录准确型号、Android/One UI、构建、native 版本和媒体编码/帧率。同片段基线与候选交错，每格至少三次；增加同文件 VLC 对照。

| 场景 | 检查 |
|---|---|
| 用户原片 1×、2×各 30s，回 1× 10s | 实际 hwdec/codec、媒体时间斜率、视频输出间隔、decode/VO drop、音画同步 |
| 原本 1×/1.5×，长按 5s，重复 10 次 | 原倍率恢复、命令提交/完成、恢复后首个稳定画面、无旧请求覆盖 |
| 仅当前 / 加下一项 / 加预览 | 活跃 decoder、峰值内存和吞吐差异 |
| 前中后位置 seek、取消和快速连续拖动 | seek 到正确首帧、目标反馈、缩略图归属、原播放状态 |
| AVC/HEVC SDR、10-bit、HDR、未知格式 | 实际选路、回退、颜色/亮度、比例、黑屏和错误可诊断性 |
| 初始化中连续 Previous/Next，含 shuffle | 实例上限、stale dispose、最终媒体、Retry |
| 长按时后台/锁屏、PiP进入退出、旋转 | 临时倍率结束、无私密帧泄露、方向和亮度恢复 |
| 2×持续 10 分钟后重复基础操作 | 热状态、CPU/GPU、内存、掉帧趋势、受控耗电 |

模拟器可以验证命令、真实触摸、取消、释放与部分渲染；不能证明 A52 厂商 codec、direct 导入、HDR、功耗或热降频。Power Profiler 的 ODPM 仅支持 Pixel 6 及以后，不能承诺 A52 有 rail 级数据；Thermal API 也可能不可用，按官方建议限制采样频率并处理 NaN。[Power Profiler](https://developer.android.com/studio/profile/power-profiler)、[Thermal API](https://developer.android.com/games/optimize/adpf/thermal)

iOS 继续单独验证 AVFoundation。Apple 的 `canPlayFastForward == false` 不表示 ReadyToPlay 的内容不能以 1–2×播放；access log 的负掉帧数表示未知，不能改为零。[Apple QA1772](https://developer.apple.com/library/archive/qa/qa1772/_index.html)、[AccessLogEvent](https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent/numberofdroppedvideoframes)

## 当前证据边界

已确认旧默认排除直接硬解，且行业方案会分别处理解码、输出与资源竞争。尚缺 A52 原片准确参数、实际 decoder/输出日志，以及候选版持续实机对照。本文支持修复方向和验证方法，不代表已经消除 A52 的 2×掉帧或回速卡顿。


## 本轮执行记录与独立验收

候选提交 `4ca02791858bfeaaaf033c4502cd8cbf62e4b814` 的既有 437 项测试、analyze 和原生回归均通过。这些是探针，不构成 A52 流畅证明。[原生操作产物](https://github.com/kcng0/privi/actions/runs/39108921121)、[两组选路实验](https://github.com/kcng0/privi/actions/runs/39108923119)。

原生流程运行真实 `PlayerScreen`，保留横竖屏控件、旋转/SAR/字幕、PiP 返回和熄屏截图，以及 100 次连续切片的过程记录。独立 `check` Hacker 查看这些产物和真实 Android DOWN/UP；长按截图出现 2×，释放后徽标消失且 native 倍率最终恢复。此前触控漏掉了 FlutterView 相对屏幕的偏移，本轮通过原生读取实际偏移纠正，未硬编码设备值。

选路实验的实际结果分别为 `mediacodec-copy` 和 `mediacodec`，但不可据此比较稳定吞吐或最终视频 FPS：

- override 在初始化后施加，绕过了新增自动策略；不能证明常见 SDR 的生产初始化会选中 direct。
- copy 组的 baseline、menu 和 hold 采样起点仍在 `seeking=yes`；释放采样还混入了 native 速度从 2 到 1 的变化。固定等待 1.5 秒不保证寻址完成。
- direct 组采样起点没有寻址，但两组都有 audio underrun / AV desynchronisation。direct 的 2× 窗口媒体时钟每墙钟秒只推进约 0.73–0.90 秒，显示该模拟环境仍明显失步，不能称为顺畅播放。
- 不同 runner 的单次记录既不是受控实机 A/B，也不能据媒体时钟进度推导屏幕帧率。

真实用户入口为：内置播放影片 → 播放设置 → 高级 →「复制播放诊断信息」；倍速菜单与画面长按分别触发持续和临时倍速。**新增复制入口的真实手机 Clipboard 读回、A52 原片的自动 direct 选择、画质、持续帧率及回速停顿均未验。** 当前服务器没有连接 Android 实机。测试绿色不填补这些证据缺口。
