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

Hacker 本轮结论为部分验收：无已建立的新产品正确性反例，新增功能与 A52 性能仍有上述未验项。本轮部署使用 `1.1.2-rc.1+39` 候选完整 APK，供真实设备核对选路、画质与倍速表现；不标记为已验证流畅的稳定版本。


## A52 实机回报与会话级对照草案（1.1.2+40，未发布）

用户安装候选版后确认画面和声音仍一起卡顿，同片在 VLC 倍速顺畅。其真实诊断为 H.264 1920×1080、60fps、speed=2、`hwdec=auto-safe` / `hwdec-current=mediacodec-copy`；raw NV12 的 matrix/primaries/gamma 均为 auto，normalized 为 BT.709/BT.1886。采样时 seeking、cache wait、core-idle 均为 no，累计 VO drop=3054、decoder drop=0、avsync=8.484234 秒，ao=opensles。累计计数没有时间窗口，不能据此计算 FPS；实际音画卡顿和同步偏离说明持续播放仍未满足要求。

这证明上一版没有切换该片的解码路径，不能据其未改善推断 direct 无效。1080p60 的 2× 每秒约处理 120 个源帧，但屏幕无法呈现全部源帧不应被用来解释如此严重的失步。

新增入口为内置播放 → 设置 → 轨道与高级播放 → 硬件加速。用户可明确选择直接硬解实验，暂停后变更当前控制器的 hwdec，再手动播放原片；也可恢复兼容模式。默认策略不变，不持久化、不自动恢复、不同时修改音频或倍率。请求的偏好和实际 hwdec-current 分别显示，配置被接受不等于直接输出成功。开关仅供同片段因果对照，A52 改善仍需实际操作确认。

保护边界需准确表述：实验仅接受当前报告为常见 8-bit 解码输出、没有已报告 HDR/广色域/高位深特征的硬件 copy-back；原始颜色为 auto 可在明确选择后尝试，缺失属性仍拒绝。**NV12 不证明原片本身是 8-bit。** Android 允许高位深解码器输出 8-bit，未知来源因此不能获得无损或 HDR 保护保证。UI 在选项前说明色彩、亮度、动态范围及性能风险，观察到的未标色状态在本控制器内保留；没有把 normalized 猜值当成源信息。[Android 13 CDD §5.1.7](https://source.android.com/docs/compatibility/13/android-13-cdd#517_video_codecs)。

音频方面，本包强制 OpenSL ES；固定 mpv 的实现按默认 250ms 块估算时钟。这是可疑差异，尚非根因证明。也不能直接切 AudioTrack：本包虽包含驱动和 JavaVM 入口，但固定旧版会由一个实例释放另一个实例还在使用的全局 JNI 引用，与 current+preload 冲突，可造成原生进程崩溃。修复晚于当前 bundle，因此本轮不改音频输出。[维护者说明](https://github.com/media-kit/media-kit/issues/1061#issuecomment-2585963757)、[mpv 上游修复 #15213](https://github.com/mpv-player/mpv/pull/15213)。VLC Android 3.6.5 配置默认 AAudio，用户当前 VLC 实际 driver 未取到；不能把 VLC 流畅归因为 AudioTrack。[VLC 配置](https://github.com/videolan/vlc-android/blob/3.6.5/application/resources/src/main/java/org/videolan/resources/VLCOptions.kt#L222)。

Hacker 首轮发现的源位深保护合同反证已用于收窄上述声明；新入口真实 UI、A52 direct 的音画改善与颜色、失败恢复和锁屏竞态仍未验。没有新增入库测试；已有探针仅检查改动和回归，不代替这些实际行为。


### 第二轮失败恢复反例与发布阻塞

新增会话开关提交 `6d1459e` 已推送可审阅，但没有打版本标签或发布。第二轮 Hacker 定位到恢复设计反例：direct codec open 失败后，即使 mpv 自行回退成功，`vd/error: Could not open codec.` 仍被 media_kit 转成错误流；当前桥接无条件转成 video_player 致命事件，已初始化的 facade 会变为未初始化。随后切回兼容或刷新 Advanced 状态不能恢复同一 facade；重复发送 initialized 也会被依赖拒绝。该反例依据固定版本源码的完整传播链，尚没有真实设备失败复现；因此不能将其记为实机观察，也不能据未复现忽略恢复合同。

两轮审查已到上限，新增开关的发布被阻止，现有已部署版本没有这次开关。用户已通过真实入口复制并提供 JSON，诊断导出这条真路径已有实机回报；新的硬件切换、音画改善、颜色和失败恢复仍未验。接下来向用户提交重大底层选型：内置 LibVLC + 原生 SurfaceView，或保留 mpv 并升级内核、输出与错误边界。仅更换 Dart 开关、吞掉日志或把同一 facade 重新标为 initialized，都不作为根因修复。


### 用户选定 LibVLC + 原生 SurfaceView

用户明确选择内置 LibVLC 与原生 SurfaceView。Android 生产入口改为官方稳定 `org.videolan.android:libvlc-all:3.7.7`，由 Flutter hybrid composition 嵌入 `VLCVideoLayout`，调用 `attachViews(..., true, false)` 同时挂载视频与字幕 Surface。原生负责完整有界 viewport 内的缩放、SAR 和旋转；Flutter 保留既有控件与手势。稳定版本与许可证按实际 Maven 元数据核实；4.0.0-eap 是预览版，本轮不用。[Maven 元数据](https://repo.maven.apache.org/maven2/org/videolan/android/libvlc-all/maven-metadata.xml)、[3.7.7 发布 POM](https://repo.maven.apache.org/maven2/org/videolan/android/libvlc-all/3.7.7/libvlc-all-3.7.7.pom)、[实际 SDK 源码](https://repo.maven.apache.org/maven2/org/videolan/android/libvlc-all/3.7.7/libvlc-all-3.7.7-sources.jar)。

该迁移消除旧 mpv copy-back → GPU → Flutter Texture 的生产视频路径，不能据此先声称 A52 性能已达 VLC。官方 LibVLC 自动选择硬解并允许软件回退；不再显示旧 mpv 会话 direct 实验。预加载只异步读取媒体信息，真正开始播放、具备 Surface 且应用授权后才创建播放/解码实例。倍速直接修改当前 LibVLC player.rate，开启音调保持。

锁屏权限与 view 生命周期分开：root lock/PiP 仍是唯一授权 owner；原生默认隐藏，锁屏/后台/熄屏撤授权并暂停，临时 PiP view 重挂不会获得额外权限。各 view 单独保存 fit 模式。原生错误仅由明确的 fatal player 事件传播，调试日志不会再次污染 video_player facade。iOS 保留 AVFoundation。

旧 mpv 原生回归和 profile 代码都显式安装旧 adapter，不能作为 LibVLC 真路径证据。当前环境没有连接 Android 手机，也无可运行模拟器；源码/SDK 编译及既有 Flutter tests 只作探针。验收必须保留“native 真播放、字幕与 Surface 叠层、PiP/屏幕遮挡、A52 2×音画和持续温度未验”的明确边界，直到取得实际输出。最终验收与发布结果随交付补记。


本轮独立 Hacker 为 `/root/libvlc_hacker`，两轮最终适用代码快照 `dc70d5e907328c236cfdaed3377b19d86f0e5646`，结论 partial。首轮建立两个实现反例：facade 自然完成会先发 pause/seek，旧 completed 标志因此丢失、LibVLC ended input 不能重播；新 SurfaceView 路径也漏掉默认防休眠。现已分离 nativeEnded 并重开 Media、保留控制意图；仅授权且真播放的当前 Surface 保持亮屏，暂停/撤权清除。Hacker 第二轮确认实现原因消除，无新的确定性反例。临时边界探针还确认 init barrier、创建失败可 dispose、睡眠开关传递，以及 grant 等待期间锁定不会下发 play；它们不构成 Android 实播证据。

[最终 CI](https://github.com/kcng0/privi/actions/runs/39122616315) 静态分析及 437 项既有测试通过；[正式构建](https://github.com/kcng0/privi/actions/runs/39122686064) 已成功发布 [v1.1.2 (40)](https://github.com/kcng0/privi/releases/tag/v1.1.2)。下载的实际 APK 已核对包名 com.privi.app、非 debug、正式签名与上一版一致；不含 libmpv，ARM64 libvlc.so/libvlcjni.so 与官方 3.7.7 AAR 内容一致。APK 232194147 bytes；SHA-256 `77143bfff97408a351fef1c54857e769d06211e1f00ea0ef1b80037f384d514e`。匿名 `/releases/latest` 已返回 v1.1.2，因此用户可沿“设置 → 检查更新”取得完整安装包。

真实验收入口：Visible/Invisible → 内置视频播放 → 菜单/长按 2×、回 1×、横向拖动释放；高级字幕/音轨/延迟/AB；PiP → 返回/熄屏/解锁。Android 实际画面和声音、字幕层级、Surface 重挂、熄屏及 A52 同片性能仍未验，继续由 issue #59 跟踪；本次交付是可安装对照版本，不能以发布成功宣称卡顿已解决。

### v1.1.3 触控、Surface 恢复与体积修正（原生验收中）

用户回报 v1.1.2 空白区域点击不能显示控件，部分影片长按显示 2× 但画面停住，松手后才恢复；同片通过菜单 2× 可以播放。生产 adapter 的同输入前后对照确认：透明度为 translucent 的原生手势队伍在 Flutter 等待第二次点击期间抢到单击；改为 display-only 的 transparent 后，单击交由既有 Flutter 手势处理。双击、长按与拖动仍由同一个手势 owner 处理。

固定 Flutter engine 的 hybrid composition 可能把仍挂载的 platform-view 父节点设为 GONE，LibVLC 此时会自动解绑 Surface 回调；原桥接只观察 attach/size，存在恢复缺口。修正分别监听祖先可见性及真实 Surface，清理失效 VideoHelper，并区分授权、播放意图和临时 Surface suspension。静止 HUD 也可能没有下一帧来消费 overlay image，因此增加仅在恢复期间请求 Flutter paint 的 view/generation 握手，恢复、撤权、换 view 和超时时停止。暂停恢复不获得播放权限，不自动播放。这是源码支持的修复方向，尚不能直接等同于已证明 A52 原片的完整因果链。[Flutter 手动失效说明](https://docs.flutter.dev/platform-integration/android/platform-views#manual-view-invalidation)

v1.1.2 实际 APK 为 232194147 bytes，其中原生库 217055864 bytes 全部按 stored 打包；没有重复 libmpv。新包采用 AGP 的 `useLegacyPackaging=true` 压缩原生库，保留所有已提供 ABI、codec 和字幕功能。Android 会在安装时解压当前 ABI，安装后占用与下载大小应分开报告；最终体积以正式 APK 实测为准。[AGP JniLibsPackaging](https://developer.android.com/reference/tools/gradle-api/9.0/com/android/build/api/dsl/JniLibsPackaging)

用户明确允许将既有原生验收迁移到 LibVLC 并补充真点击、持触期间视频画面推进及暂停 Surface 恢复，要求完成后再发布。验收保留原合成 codec/rotation/SAR/ASS 素材、100 次切片及 PiP/锁屏边界。独立 Hacker 在第一轮指出测试等待时 pump 和 fullyLive 自动续帧均会掩盖此故障；现已改为只允许应用请求的帧，真实 DOWN→持触截图→UP 不主动 pump。独立引擎探针确认 idle/停止均 0 个多余帧，应用 ticker 与 forced frame 正常。该探针不替代 Android 视频输出。

业务快照 `185a3ca` 的普通 CI 通过。原生运行 [5e81af2](https://github.com/kcng0/privi/actions/runs/39126311123) 与 [52c36ae](https://github.com/kcng0/privi/actions/runs/39126937726) 均失败，不能作为验收通过证据：截图被 Pixel Launcher ANR 弹窗遮挡，未覆盖长按/PiP；约 40 次切片后还实际触发 `video_player` 异步 position 在 dispose 后更新的断言。后者是确定的生产生命周期反例，不能归因为系统弹窗或通过调慢切片掩盖。

已增加统一生产 `VaultVideoPlayerController.file`：release 同步取消迟到 position，等待已接收的 play/seek 收尾后调用原有 dispose，阻止新命令。活跃查询错误、命令错误和释放失败仍传播。Hacker 用锁定依赖独立复现 late seek 的同类断言，并对实际新类复验迟到值/错误、play/seek、重复 dispose 及失败释放；31 项既有切片/返回 widget 探针通过。官方 2.14.1 源码中这几个 await 后仍无 disposed 检查，单纯升级不能替代修正。[官方 2.14.1 源码归档](https://pub.dev/api/archives/video_player-2.14.1.tar.gz)

验收现用官方 AOSP API33 x86_64 镜像，运行时要求真实 PiP feature、稳定 HOME 焦点及可响应 UI hierarchy；任何 Launcher 或 Privi ANR 都保存现场并失败，不点掉弹窗。输入/截图每次读取现有原生 FlutterView screen offset，按 logical×dpr+physical offset 转换，日志记录原始坐标。保留 boot logs 时另用随机日志 fence 排除旧测试动作重放。环境与上述生产修正快照 `3fce837` 已执行 [Android Playback Validation](https://github.com/kcng0/privi/actions/runs/39127936940)，其结果与后续修正记录如下。原生验收不通过时不打发布标签。

`3fce837` 的原生结果仍失败，但 100 次真实 controller 切片已经完成，不再出现 disposed 更新断言。AOSP 没有 Launcher ANR。实际图片及日志又定位两项验收缺口：红色 DEBUG 标识污染视频边界；LiveTest binding 默认把真实设备事件交给 WidgetTester 打印 Finder，而非产品手势。已在 harness 关闭 debug banner 并允许 device pointer 进入应用。独立探针确认真实 device-source tap 能触发产品 GestureDetector，且 idle/停止仍不造帧。

首幅全黑同时暴露新的生产冷启动互锁：该 test 截图前完全没有 decoder 启动记录，首次分配在后续 test；`maybePlay` 要先可见才建 player，恢复帧请求又要求 player 已存在。已改为已初始化、获授权且有播放意图的 active view 可在创建 decoder 前请求帧；未播放预载仍禁止。没有通过延长截图等待绕过此反例。包含该修正的快照 `34ec5ba` 正在运行 [新的原生验收](https://github.com/kcng0/privi/actions/runs/39129035107)，截图等待与外部像素标准保持原值，待真实结果再决定发布。

Hacker 第 1 轮在 `34ec5ba` 的实际原生结果中确认：真实 ADB 点击成功、100 次切片完成，但不能发布。长按首图为 frame55，第二张及松手后两张均为 frame0，视频区域逐像素相同；native position、decoded/displayed 均停止而 Playing/play intent 仍为 true，Surface generation/loss/attach 没有反复变化。这是片尾重开后停帧，不能把两张截图不同解读为持续播放通过。ASS 截图的1.875秒处没有应显示的0–3秒文字，API组绿不代表字幕呈现。首图仍黑，但该次已通过冷启动门控并请求audio focus，后续字体扫描活动意味着不能继续断言同一门控死锁。

作者侧候选 `3a27346` 去掉新 input 重开时多余的 pending seek(0)，保留运行中的用户 seek 与非零 A 点。初次 LibVLC 构造在后台调用官方 `buildFontCache()`，把数秒系统字体扫描放到初始化阶段；false 只说明磁盘缓存无效，官方客户端同样告警后继续，不伪报缓存成功也不使正常渲染失败。[官方 JNI](https://code.videolan.org/videolan/libvlcjni/-/blob/a498cf1fefd93c4a2ec7253ac33cd6dd5b344dde/libvlc/jni/libvlcjni.c)、[官方 Android FontCache](https://github.com/videolan/vlc-android/blob/ba316c9819ee24678ff56fd21600e0cf6259e828/application/vlc-android/src/org/videolan/vlc/util/FontCache.kt#L117)。已移除把字体文件路径传给 Android FreeType font-family 选项的错误覆盖，ASS 继续用 `ssa-fontsdir`。日志曾确认 Noto 文件及 fontconfig provider 已加载，所以没有把 ASS 无字直接归因于字体；新增真实 spuTrack/track IDs 与字幕 Surface 状态，在截图前保存诊断。

该快照的[作者原生运行](https://github.com/kcng0/privi/actions/runs/39130426888) 仍失败，普通 CI 则通过。实际缓存构建成功，耗时 8989ms；首次视频以及 H264、VP9、HEVC、AV1、旋转/SAR、各比例模式的真实画面通过。100 次切片完成。真实长按持续 10.6 秒、跨多次片尾重开，持触/松手/菜单 2×/回 1× 均有视频 ROI 持续变化；横竖屏运动、暂停后控件切换和旋转静帧、恢复 Play 后运动均通过。作者同时补齐已结束输入的显式 replay seek(0)，运行中 seek(0) 不受影响；该边界待下一次原生运行。

剩余两项需要区分源问题与验收呈现：ASS 实际已选 track4，字幕 Surface 有效且可见，但原截图处于首次 seek(1000) 与窄 A–B 的连续 flush 期间，图片 HUD 仍为 frame0，没有中文字，不能据 API 绿宣称字幕通过。PiP 第一次返回并锁定时黑屏保护通过；随后测试解锁后的两张图实际仍是相同的“Draw your pattern”界面，旧多色边界误把锁图标和 Forgot pattern 按钮算成视频。此处没有视频冻结的像素证据；需检查真实锁层撤出及合成结果，并强化素材识别防止假阳性。作者侧关闭这些反例后才提交第 2 轮 Hacker 复验，原生验收未通过前不发布。

作者快照 `a4c1f35` 的[原生运行](https://github.com/kcng0/privi/actions/runs/39132675632) 增加了独立稳态内嵌 ASS 对照、解锁真实 widget/交互 witness 和锁/PiP timeline；候选视频 bounds 内须有大面积、多色段 testsrc2 特征，旧锁屏图不再算视频。35 张旧真实视频图保留原比例、Original 物理尺寸与运动阈值通过，2 张 pattern 图明确被拒绝。本轮实际内嵌字幕 PNG 已显示 `Privi 中文字幕測試`，源 HUD 为 0.917 秒/frame22，字幕和视频 Surface 本身可用；显式 seek 请求 0、无 A–B。原外部导入＋seek/A–B 路径两张图仍无文字，later 图源 HUD 已到1.708秒/frame41，须继续定位，不能以稳态内嵌通过替代外部字幕合同。

该次长按持续11.59秒、100次切片及先前交互/比例检查仍通过。PiP EXPAND 后单次解锁的真实树已无锁层且恢复交互，两张视频图 ROI 变化16.78%、9/16区块，通过；没有出现晚到 relock。随后实际 SCREEN_OFF→唤醒返回，真实树同样解锁/已resumed，首张截图却全黑，测试据此失败。Flutter raster 线程在该熄屏阶段开始持续报 `EGL_BAD_ACCESS: context current to another thread`，不能按时钟或 widget 树宣称恢复成功，也不能直接把该图形上下文失败归给 LibVLC。作者分别定位外部字幕与此图形恢复问题；发布及第2轮 Hacker继续等待。
