# 视频播放体验与性能调研

日期：2026-10-18。来源：官方文档与固定版本源码。范围：Android 本地视频、倍速、seek、预览、输出与测量；iOS 单独验证。

最新状态（2026-10-19 SGT）：`1.1.3+43` 已完成签名候选构建，实际同hash正式包已通过首画面和持触/释放运动观察，随后控件显示检查失败；只读原生诊断在插桩连接时崩溃，工具修复与不插桩流程已复现PiP和字幕反例，正在按完整原生证据定位，尚未公开发布。41/42的首次播放、PiP恢复和字幕反例尚需按各自真路径关闭；用户已明确要求继续修复并重新独立验收，通过后再发布，新一轮独立Hacker尚未开始。下方保留各快照记录，历史流程绿不表示当前验收通过。

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

快照 `0460c1d` 的[诊断运行](https://github.com/kcng0/privi/actions/runs/39134431319) 再次失败，并排除 native privacy cover：SCREEN_OFF 返回后的真实 window 诊断为 interactive=true/keyguard=false、exitAck=true/session0、cover present/attached/shown 全 false，实际 PNG 仍全黑。旧 PiP ImageReader 被 abandoned 后先在主线程报 EGL_BAD_SURFACE，随后 raster 线程持续 EGL_BAD_ACCESS；该错误恰由 [AOSP guest EGL 的跨线程 current 检查](https://android.googlesource.com/device/generic/goldfish-opengl/+/refs/heads/android13-release/system/egl/egl.cpp#1930) 返回，尚未进入 SwiftShader，不能归因于 host renderer。固定 engine83675 的 teardown 先销毁 surface 再 unmerge，Impeller GL 析构未解除原线程 context；[上游补丁](https://github.com/flutter/flutter/commit/974dc3ba062df6eb0e47570b1dd8b73a73eba054) 补齐销毁前 ClearRenderContext。核对官方 release index 及实际 engine，3.44.9 和 3.47.7 stable 均尚未包含该补丁；这条源码反例与现场吻合，尚不代表所有设备上只有此因。

只读 critic 排除了仅把 Flutter 根 View 改为 TextureView 的方案：当前 HC 仍无条件转 FlutterImageView 并合并线程。候选只在生产 manifest 显式采用当前版本[官方支持的 Skia opt-out](https://docs.flutter.dev/perf/impeller#android)，保留 LibVLC/SurfaceView/授权与生命周期合同；不能仅在测试禁用 Impeller。此选项已被上游标记 deprecated，后续升级需重查；它影响全部 Android Flutter UI，不能称为已证明的性能提升。须用相同原生全流程和实际 Shorebird 正式 APK 验证恢复、触控、锁屏/路由及视觉，再决定发布；当前候选尚未验。

同一诊断运行的外部 ASS 稳态真实图有中文字；第一次普通 seek(1000) 后 HUD1.000/frame24 已无字，此时 delay=0/无 A–B，说明导入本身可用、单次 seek 即能触发。之后 delay 阶段截图文字恢复，但同时 inputReopen 从1变2，不能把它解释为 delay 修复；A–B 再次 seek 后 HUD0.500/frame12 无字。SDK actual delay 与125000/-250000微秒 intent一致，SPU4及Surface持续有效，native作者继续定位 seek 后字幕状态。


快照 `ea38fb6` 的[作者原生运行](https://github.com/kcng0/privi/actions/runs/39135752805) 提前失败，尚未走到熄屏恢复，不能判断 Skia 候选已有效。原生日志确认 ended input 内部重开会先发 Stopped 再发 Playing；旧 facade 把这个临时 Stopped 当暂停。在长按倍率请求返回后，手势层原有的生命周期保护会在 facade 已暂停时再次 pause，因此这是可影响真实长按的生产状态反例。修复仅为有效授权与播放意图下的内部重开保留 facade 播放意图，并标明 buffering；真实 pause/revoke/failure 和既有 25 秒启动超时继续生效。该候选需下一次实际原生运行。

同一轮字幕截图后探针恰跨越 3 秒素材片尾：reopen 3→4、Playing→Opening、position 0，不能以截图完成后的单次 SDK 状态断言持续卡死。验收现保留原始 opening 时间线并有界等待 Playing；图片本身只取一次、字幕/比例/运动标准不变。长按和松手也在原有 12 秒观察窗内等待真实 2× 徽标出现/消失，不主动 pump 或重发 DOWN/UP。新增只读 gfxinfo framestats 用于现场 UI 数据，不代表视频 FPS。

旧版正式 APK 的真 UI 校准已实际完成首次图案设置、关闭 Block screenshots（之后严格要求有效 PNG）和选择内置播放器；随后停在系统照片/视频 ALLOW 弹窗识别，尚未进入播放。它仅用于校准真实首启路径，不是新版 APK 验收证据。下一版必须使用新的同一签名 APK artifact 完成实际播放、长按、PiP/熄屏返回，再将原包发布。


作者快照 `9091d80` 的[完整原生运行](https://github.com/kcng0/privi/actions/runs/39137345022) 首次流程通过，普通 CI 亦通过。实际无 pump 的 DOWN→UP持续11798ms；持触两图视频 ROI 变化15.05%/9区块，松手后25.69%/14区块；100次切片完成。Skia候选的PiP EXPAND解锁后18.54%/10区块、SCREEN_OFF唤醒解锁后18.36%/12区块，root实际查看熄屏恢复PNG确认真实testsrc画面，不再全黑。两条返回在未解锁时素材均隐藏；窗口与真实root widget witness保留。RSS前后482385920→460828672 bytes、峰值533151744，仅为debug模拟器资源探针，不能据此宣称A52性能。

此次流程绿仍不是字幕验收通过：root实际查看新 `portrait-ass-embedded-after-seek-1000.png`，源HUD1.000秒/frame24无字，reopen2→2、native1000→1587、generation1，排除了外部slave独有的解释；external A–B图HUD1.375秒/frame33亦无字，reopen5保持。外部普通seek图此次有字，但reopen3→4，不能当成修复。下一次只读字幕Surface缓冲统计及独立paused-seek对照用于定位，不改变选轨或播放的生产行为，原playing序列保留。字幕兼容反例尚未闭环，因此完整正式APK验收与发布继续等待。

旧正式APK的[第三轮入口校准](https://github.com/kcng0/privi/actions/runs/39137886958) 已真实走通图库授权、文件夹Hide、系统all-files开关、pattern解锁、Invisible album、Play playlist/In order，实际PNG确认进入PlayerScreen。随后的首次视频全黑/0:00，多色门严格失败；旧日志有Goldfish H264 decodeHeader错误，不能据此断言新版也失败，亦不放宽视频门。初始化metadata/UI控件不代表首个native frame，正式APK验收将仅在首次启动使用有界真实PNG就绪观察，不重发任何播放命令或造Flutter帧；后续长按、恢复和字幕仍保持原门。

### 正式签名候选41与第2轮独立验收

`b4110cc` 的[签名候选构建39139579043](https://github.com/kcng0/privi/actions/runs/39139579043) 成功，Shorebird登记 `1.1.3+41` 基础版本；stage-only跳过公开tag/release。实际APK为114,818,931 bytes，较v1.1.2的232,194,147 bytes减少50.55%。SHA-256为 `45356748118c3da0827286cc1e8f8b380eb02ac1754ed71fb98cb98c96b4a74d`，正式签名证书与旧包一致，三种ABI、LibVLC模块及Noto字体保留。下载体积减少不代表安装占用同比减少。

独立`check` Hacker `/root/libvlc_hacker_round2` 使用该同hash正式包完成[真实入口smoke39141358312](https://github.com/kcng0/privi/actions/runs/39141358312)：首启pattern、系统权限、Hide、Invisible、Play playlist/In order均走通；之后一直spinner，约26秒出现真实`initialization_timeout` / Retry，未进入长按或PiP。设备日志15:42:40.371已报初始化超时，15:42:42.801才完成26,863ms字体缓存。原25秒媒体期限先于共享准备启动，随后丢弃打开的媒体，是明确本地反例，不能靠Retry或放宽截图门关闭。

同快照[原生诊断39139268901](https://github.com/kcng0/privi/actions/runs/39139268901) 的PiP EXPAND→解锁→Play后实际PNG仍为Draw your pattern。root树无锁层、native cover全部false、native playing/surface-ready均不能否定屏幕。该解锁没有新恢复请求：fullscreen view在未授权时建立，解锁时native surface已经ready。既有ready条件不保证Flutter图像消费或呈现。本次没有先前Impeller的EGL_BAD_ACCESS，不能继续按旧错误归因。下一次增加debug-only只读reader通知与window draw/commit观测，不消费图像或补帧，以真实PNG核对。

字幕反例仍在：playing内嵌ASS seek后，HUD1.750秒/frame42、delay=0无中文字；paused外挂ASS普通seek到1秒有字，但off/on再seek无字。PixelCopy正alpha与无字PNG来自不同时间，不能当成修复。负delay的静态SDK分支显示跨零时间戳有删除风险，尚不能仅凭分支断言动态根因；禁止夹零、盲重选轨或重启规避。官方[Maven元数据](https://repo1.maven.org/maven2/org/videolan/android/libvlc-all/maven-metadata.xml)中3.x稳定版最高仍为3.7.7，4.0只有EAP，不能假设存在无风险升级修复。

本轮Hacker结论partial，不满足发布前提。用户按两轮上限决定继续修复三项、再开启独立验收。候选build升至42，先分离共享准备与每媒体打开期限；30秒正式包首帧、45秒native初始化外层及全部像素门保持不变。新修复的实际APK、PiP、字幕及A52音画性能尚未验，公开Latest仍为v1.1.2。

候选42的[stage39142860597](https://github.com/kcng0/privi/actions/runs/39142860597)成功：实际APK114,824,323 bytes，SHA-256 `42a1f5a694fd1a2adc2011e906cd58d21a93eff35003ca7a095f37d3f8431f72`，原正式证书及三ABI、SDK载入段与字幕资源核对通过，analyze/既有测试通过。[同hash正式包smoke39143971377](https://github.com/kcng0/privi/actions/runs/39143971377)仍未满足30秒首帧门：本轮字体构建36,944ms、共享准备37,832ms，之后metadata及Playing到达，旧25秒initialization_timeout不再出现。该结果关闭旧超时因果，但不构成首播体验通过；采样在准备完成前已失败，也不能按此认定冷启动合成黑屏。候选43将共享准备提前到Android启动注册完成后后台执行；不创建媒体/decoder、不授权、不持有音频focus，失败不隐藏重试。实际首播仍须使用新签名包验收。

bb22的[原生诊断39142868033](https://github.com/kcng0/privi/actions/runs/39142868033)在持触两图运动19.71%/12区块后停止：大composition JSON超过logcat单行上限，helper解析失败，尚未执行松手截图或PiP。这是harness运输反例，不是新PiP结果。现采用完整UTF-8请求一次HTTP登记、logcat仅短ID、原owner串行执行；不重发不确定请求，完整数据保留，所有原期限和图像门不变。下一轮可选Frida只读trace检查exact x64 SDK的9个公开export，记录cue/clock/flush/libass/SPU/删除元数据，不把插桩吞吐或`captured`当功能通过；无真实trace前Android字幕缓存/负时间戳均仍是待验证候选。


候选43 `d2a4bfc` 的[stage39144907226](https://github.com/kcng0/privi/actions/runs/39144907226)已成功，未公开发布。实际下载APK114,824,403 bytes，SHA-256 `c09dc2da0e49a3b67650f94adb0730c32b9198619cf437211054e52f3a9f0441`，较旧232,194,147 bytes减少50.55%。核对全部侧车SHA-256/SHA-512、正式证书、非debug生产包名、1.1.3/43、min26/target36、extractNativeLibs=true及Skia配置；三ABI/24原生库、旧包6个VLC库、官方SDK所有映射载入段、Noto字体和许可证均保留，64位原生库载入段至少16KiB对齐。不能把这些身份/打包核对当作首帧或性能通过。

[同hash签名43 smoke39145783441](https://github.com/kcng0/privi/actions/runs/39145783441)与[可选只读原生诊断39144913331](https://github.com/kcng0/privi/actions/runs/39144913331)进行中。前者无Frida，验证实际首次入口、持触/释放及PiP/熄屏；后者用于定位字幕/clock/SPU与Flutter合成，不证明吞吐。普通[CI39144891835](https://github.com/kcng0/privi/actions/runs/39144891835) analyze/437项既有测试通过。当前没有新独立Hacker结论，实际画面与字幕反例未闭环前不发布。


签名43的实际[smoke39145783441](https://github.com/kcng0/privi/actions/runs/39145783441)已完成，结论仍失败：实际pattern/授权/Hide/Invisible/In order后3.9089秒出现testsrc，满足原30秒门。共享准备已在首启时完成（font9,495ms，engine9,609ms），播放前准备就绪；不能把不同runner的字体耗时差当作性能A/B。root实际查看持触两张PNG，均有2×且HUD frame62→52跨素材片尾、画面内容变化；持触ROI26.68%/13区块、松手后26.96%/13区块，释放徽标消失。该证据确认此模拟器真实画面推进，不证明A52输出FPS或声音。

流程随后在`controls(True)`失败，尚未进入PiP。故障截图和accessibility均无控件，但helper在点击后先运行会等待idle的`uiautomator dump`，再取PNG；产品既有自动隐藏为3秒，慢采样可能错过短暂控件。当前仅为运输/观察候选，不能据此认定真实tap已成功，也不改产品计时来迎合脚本。下一次需无idle的原生accessibility快照和点击后即时PNG，再判定是否产品触控故障；全部原像素门及同APK身份保持。


SDK源码取证（只读，未修改/重建SDK）：官方`libvlc-3.7.7`标签`7a7c8f14be6759f9bb1b9a934fd086259473e20e`的[compile.sh](https://code.videolan.org/videolan/vlc-android/-/raw/libvlc-3.7.7/buildsystem/compile.sh)固定JNI `0b8dc65efb203c86a0476bc337ddd99ecf1c0ef6`；其[get-vlc.sh](https://code.videolan.org/videolan/libvlcjni/-/raw/0b8dc65efb203c86a0476bc337ddd99ecf1c0ef6/buildsystem/get-vlc.sh)固定VLC `84177b2273abc5c4300234e6e18b55a4d2dd5a03`再应用20个官方patch。临时源码已实际成功应用全部patch。AAR不同ABI的`3.0.24-35-g…`哈希包含git-am产生的本地commit，单独上游hash不可解析不等于源码不可得；当前确认内容重建路径，不声称字节级可复现。

后续若真实trace确认为SDK缺陷，可在该固定源码和官方patch队列后维护小范围修复。20个patch不改Android字幕显示缓存与core decoder路径；patch0008只改libass字体附件释放，不能泛称libass完全未改。静态cache/order、NULL清除及lock失败候选仍需动态证据。官方固定[CI recipe](https://code.videolan.org/videolan/vlc-android/-/raw/libvlc-3.7.7/buildsystem/gitlab/.gitlab-ci.yml)为64位NDK29、armv7 NDK21e；三ABI需配套JNI/C++runtime/codec/font。对应预构建contrib目前404，完整源码构建和耗时未验，不据此承诺升级或省略兼容ABI。


只读诊断39144913331结束失败，不能作为字幕/HTTP/合成结论：server handshake正常，但只有15条trace，hooks_ready=false、无cue、无agent正常停止；drive最终1200秒超时，没有第一action或业务PNG。真实tombstone在build-accepted同毫秒显示bionic linker `Load CHECK did_read_ failed`，栈为do_dlopen→frida-agent，随后Android自动重启进程、drive仍等旧VM。固定Frida17.24.2源码确认find_export_by_name→lazy module handle→`__loader_dlopen(RTLD_NOLOAD)`；同步module-observer加载回调内首次findExport是匹配现场的重入点。工具修复将发现与安装分开，回调返回后再核module身份并采用不获取handle的ELF导出枚举；未ready之前不宣称调用覆盖，不重启/重试掩盖。未修改官方SDK。

root另行启动[不插桩原生39146944141](https://github.com/kcng0/privi/actions/runs/39146944141)，使用相同d2a4bfc业务快照，先获取完整HTTP传输、PiP/composition及字幕真实画面。签名控件观察也确认固定AOSP13 `UiDevice.dumpWindowHierarchy`会使用`Display.getSize`，Dumper把每节点屏幕坐标裁到应用可用尺寸；这可制造底部零bounds，故不能用旧XML认定产品布局坏。瞬时观察工具采用独立临时instrumentation目标自身，经public UiAutomation读取原始getBoundsInScreen；不target/修改Privi、不跨持触窗口保留连接、不改自动隐藏计时或真实ADB输入。实际Android快照与点击尚待验。


[普通原生39146944141](https://github.com/kcng0/privi/actions/runs/39146944141)已完成失败，但70个完整HTTP action、metrics及PNG均到达，关闭了原logcat截断阻碍。首次初始化、持触/释放、100次切片、比例/旋转/SAR/codec、暂停与用户Play路径均执行；action70仍为EXPAND解锁后的pattern旧图，SCREEN_OFF未进入。新的窗口/reader事件显示解锁后root新图像到达、overlay移除和window commit；SurfaceFlinger现场有解锁前旧root SurfaceView buffer及解锁后window透明视频洞，而当前video/subtitle层无activeBuffer。因此不能继续仅凭旧pattern判定FlutterImageView未消费，应优先定位native buffer/绑定与各层真实身份；具体像素来源仍待独立对应。

本次ASS paused对照更强：ordinary seek@HUD1.000有中文字，off/on再seek@相同1.000无字；native position1000、reopen0、surface generation1保持。当前subtitleSurface在两条暂停路径前后PixelCopy均31412非透明像素、同bbox与CRC31e114fd，采样跨2.35秒仍稳定。这不支持直接把无字归为缓存清空/时间错位；需定位其buffer与屏幕layer的关系。root实际看过两张暂停图及playing seek图（HUD2.833无字），保持字幕反例开放。

诊断工具修复`5bca013`已推送；新的[可选Frida39147687212](https://github.com/kcng0/privi/actions/runs/39147687212)进行中，普通业务APK仍43。修复的临时真实Frida17 API与进程组隔离探针通过，Android hook/runtime尚未验。瞬时UI helper亦已通过API33 javac/D8/封包/签名探针；真实Android安装、连接耗时和3秒内控件采样须继续用同签名43验证，不以运输桩或编译成功判产品通过。


新的Frida39147687212已结束：旧loader abort未复现，hooks-ready实际到达，531条记录覆盖字幕阶段；随后action49运动检查失败、app退场，agent未正常stop，故coverage=partial，不能标captured或当性能证据。独立只读`ass_trace_analysis`核同轮paused两张PNG：普通seek@1.000有字、off/on再seek@1.000无字。新track40/sub14实际经过cue decode、clock转换、vout-put/spu-put，renderer41在990ms has_images=true，SPU持续region_count1；PixelCopy仍31412alpha/同CRC。这关闭“未解码/cue外/无SPU输出”的解释，但还不能把新sub14对应到已latch的Surface buffer。playing embedded seek本轮@1.875有字，不可拿来解释普通无插桩@2.833缺字；两路径保持区分。

同trace另有独立时钟反例：负delay−250000us把合法cue start2us变−249998us，clock因符号跳过start转换，stop却转到system域，随后在vout-put前delete。官方3.7.7 core源码匹配。将delay纳入clock映射而不损失原validity可关闭stream跨零，但低uptime/大负delay仍可映射为有效signed system日期，被后续SPU符号判断丢弃。完整修复需分离“转换成功/日期已知”与符号，不能夹0/1/now或宣称三文件patch覆盖所有合法输入；尚未改/构建SDK。

[signed43即时helper验收39148303329](https://github.com/kcng0/privi/actions/runs/39148303329)再次首画面3.6386秒、held画面推进，但controls-before连续root-unavailable，未发PiP。固定AOSP13源码及真实log说明：服务connected不等于Privi ViewRoot已注册accessibility window；旧helper读一次null便finish，22–126ms内销毁仍建立中的连接。修正改同连接内有界只读poll，最长2秒且扣入原8秒host预算，不waitIdle/造帧/重复tap。实际Android新poll时序待验。

下一次原生观察保留原失败：三个paused ASS截图紧邻保存SF层dump；EXPAND原检查失败后，仅在真实seekable、授权、input身份与实际位置有效时，可诊断性seek同位置并另存PNG/SF，最终始终重抛原错误。它用于检验SDK detachViews重建decoder后从GOP中段续播的候选，不能当产品自动fallback，也不能仅凭PNG恢复认定关键帧因果。Host新增只读native-is-seekable字段并通过官方AAR Kotlin编译，现有immutable签名43不包含该新字段；最终后续native生产构建需新build号≥44。


2026-10-19 后续实现（未发布）：用户追问最近改动主要是诊断、字幕仍存在后，已将修复落到固定 SDK 源码。`7aa28b4` 的两个下游 patch 位于 `third_party/libvlc/patches/`：0001 分离 raw cue validity、clock 转换成功与 known stop，支持合法跨零点时间，维护 ephemeral/OSD/暂停语义，并对真正不可表示的时间/缓冲运算走明确 fatal 事件；0002 使清空字幕、format变化、failed lock不再保留旧 order/region cache hit。它们不是已验证的画面成功声明。修改内部 subpicture ABI，三个 ABI 必须全量重编 core、全部 modules 与 JNI；原 Java/资源保留，不能混旧 SO。App 未启用 sub-filter，`subsdelay` 的未启用历史问题不属于此修复范围。

新的[固定源码 SDK 构建39152889983](https://github.com/kcng0/privi/actions/runs/39152889983)已从 `6d5cc2d` 启动：真实 fresh fetch、20个官方 git-am、0001→0002、upstream get-vlc检查及官方 AAR hash完成，patched tree `dbcefa869c26f667d09dfb792c537ee359d2d065`。三ABI正在实际源码编译，尚无 SDK/字幕画面通过结论。显式 --license g 沿用官方实际功能配置；不采用会改变现有模块集合的 a 分支。完整 SDK/source/licenses/provenance bundle需与最终 APK 一起公开；默认 Maven尚未切到新永久artifact，不能漏掉最终cutover。

[作者原生39151899430](https://github.com/kcng0/privi/actions/runs/39151899430)使用 `5d505fd` 和旧官方SDK：实际完成100次controller handoff、持按11641ms，RSS457297920→460701696 bytes；本轮未复现上一轮原生释放阻塞，不能据单轮证明所有设备不存在。Host现在等待真实资源清理再答dispose，Playing前同generation的启动token不会因SDK play返回而提前清除。EXPAND action70仍是旧pattern，SCREEN_OFF未进入；same-position诊断seek因原4分钟scene已用163718ms、不足预留预算而没有执行，不能记为恢复或keyframe实验成功。原native backtrace在drive退场后已无app PID，明确记录diagnostic-failed，没有替换原业务失败。

[signed43即时root-poll39149914381](https://github.com/kcng0/privi/actions/runs/39149914381)首画面4.156秒、持触/松手画面继续推进。038原PNG在显示tap后1.75秒内已保存却无top/center/bottom chrome，039 XML有控件；PiP点击已距显示tap3.72秒，不能区分过期输入与native拒绝。该PNG是真实呈现反例，不能用XML visible=true替代。`a9d3259`将三条视频入口的chrome归一组，仅出现时180ms自然淡入，隐藏即时卸载；没有退出fade、常驻ticker或重建native viewport，既有4项即时隐藏反例已按较小实现关闭而未改测试。原生HC效果仍待图像验收。正式smoke将A原始blank tap→PNG与B新的fresh reveal→普通单击分开，保留3s/8s期限与过期拒绝；等待PNG的button DOWN方案因Tooltip长按抢arena而明确否决。

用户授权的新独立验收周期第1轮已启动SDK模块对抗审查；Host的Surface恢复及最终native/签名APK尚未完成，公开v1.1.3仍未发布，build43仅为旧SDK暂存包，最终native行为需build44或更高。A52实际FPS、声音、温度与功耗仍未验。


2026-10-19 固定源码字幕实现已推进到 `4a79757`，不是仅诊断：0001 改为明确的私有 clock result enum，修正首轮三 ABI 均发现的未定义 `VLC_EINVAL`；保留原 SPU decoder preroll 过滤。0003 统一 slave seek/barrier 时间域，恢复 active overlap/latest unknown group，并跳过 seek cutoff 前已过期历史；SPU known packet end 用 delayed domain 判断 preroll，unknown/zero duration 不新增过期判断。新检查到的时间溢出经专用 input query 进入优先 TIMING_ERROR，不被 slave EOF 吞掉。0004 修正 JNI `nativeSetTime` 的 void/Java long 不匹配；返回当前查询位置，Host 不再把它当 seek 接受或完成确认。

新周期第1轮 Hacker 在真实函数边界复验关闭正 delay、overlap、100 expired queue及release publish输入忽略反例。独立218组Control/Demux、作者20k cue+40k算术、root70k clock与70k preroll+20k AV对照均只是探针。fresh official20patch→4patch准备完成，14个VLC文件和1个JNI文件与owner副本一致，VLC tree `99ae209afc7d29e476eff33bf03b95eac337bb58`、JNI tree `3063bf30974cb795b13076bb5ae142c6d02f5c30`。新的[三ABI SDK构建39155522179](https://github.com/kcng0/privi/actions/runs/39155522179)已进入真实编译，尚无新SDK字幕呈现通过结论。

[普通原生39154250229](https://github.com/kcng0/privi/actions/runs/39154250229)使用 `f4c3775`、旧官方SDK。实际100handoff完成、held23.70%/10块、released24.43%/14块；本轮paused baseline/seek/reselect三图均有中文字，但不能替代此前同路径无字反例的新SDK验收。action40 menu2×两PNG均为HUD2.958/frame71，motion0/16，原门严格失败。真实action markers08.640与13.751分别落在input14/16 reopen后、first-picture前，存在短clip循环末帧采样别名候选；中间只有decode/vout活动记录、没有中间上屏帧证据，不能据reopen或时钟认定流畅，也不直接认定持续freeze。PiP/SCREEN_OFF尚未进入。本轮公开版本仍40，签名新native候选需build44以上。

现有原生字幕用例在原3分钟期限内增加三张独立输入PNG：正delay seek、overlap、长A/100expired/B。保留旧素材及所有旧路径；实际图中文字与独立cue区间才作为通过依据，native paused/position/reopen/gen/PixelCopy仅为诊断。新SDK编译、三图、PiP/锁屏、实际签名APK均尚未验，当前不发布。

SDK `39155522179` 的三个 ABI 原生任务随后全部编译成功，但 package 严格失败，未产生可供消费者使用的 bundle：不同 ABI 的 `fluidlite-b0f187b404e393ee0a495b277154d55d7d03cbeb.tar.xz` 同名、原始 SHA-256 不同，旧源码 offer 合并逻辑要求同名归档逐字节一致。不能跳过校验、覆盖其中一份或据此声称源码内容相同。修复将按内容保存全部原归档，以每 ABI 的实际 inventory 恢复构建输入。独立 Hacker 另确认上游 `download_git`/`check_githash` 需要同名 `.githash`，必须一并采集原字节；否则已有 tarball 会跳过下载却在校验时报缺文件。此项属于对应源码复建合同，不能用编译成功代替复建检查。

实际 arm64 产物保留 271 个 built-in modules，包含 MediaCodec、Android display/window、avcodec、dav1d、vpx、libass、freetype、subtitle、Matroska/MP4/AVI 和 Android 音频输出。其 configure 功能开关与官方 arm64 库相同；官方额外的 debug/branch-protection 参数不作为功能裁剪。真实三库的 64-bit PT_LOAD 均为 16KiB 对齐。这些是构建与兼容性探针，尚不能证明字幕呈现、Samsung A52 输出 FPS 或声音。默认 SDK 消费路径已在 `e822ed7` 统一且移除 Maven fallback；永久 manifest 仍待成功 bundle 的真实哈希，不填占位值。

对应源码归档修复随后用旧 run 的三个真实 source-part 检查：同名字节差异包含 fluidlite/postproc/x264；fluidlite 的三个压缩文件解开后 tar SHA 相同，确认该包差异来自压缩层。按内容存储共 70 个对象、349,183,267 bytes，保留各 ABI 原字节且不按文件名任选变体。旧产物未采集 `.githash`，只用于归档探针，不作为新 SDK 或完整 source-offer 复建成功证据。修正后的 producer 将捕获真实 sidecar，并通过对应源码包的 `inputs/scripts/build-libvlc-sdk.sh build --abi …` 在编译前校验并恢复该 ABI 的输入；仍需新的完整三 ABI 构建与实际播放验收。


`e344a6c` 的[完整 SDK 39158862339](https://github.com/kcng0/privi/actions/runs/39158862339) 已全成功：prepare、三个 ABI native、package 均成功。20:02:28 UTC 的真实 package 输出为 whole-bundle SHA-256 `e8a8f5e5e4762f5c392f58645ce730e0315a0ea4a22ca4ff90f2782bb5a1de6b`、AAR SHA-256 `2d257e4a9665ff3cf8137fecb7df4edd7ab1ba2bb4dddd785787e44c6a4d8231`，已据此固定生产 manifest，候选升至 `1.1.3+44`。Actions SDK artifact 为 547,363,580 bytes；这是包括对应源码的构建资产，不是 APK 体积。消费者随后必须真实下载并校验全包；当前本地资产复核、字幕实际文字、PiP/熄屏与最终签名 APK 仍待验，不能称已发布。

对应源码文档修正首次解包的 ownership 边界：由宿主普通用户解包、再进入 UID0 容器会被 Git 拒绝。公开 README 现将首次 `tar --no-same-owner` 与 build 放在同 UID0 容器中，不改全局 safe.directory。固定 e344 bundle 保留该源提交的 inputs 文档快照；发布说明链接 app tag 的修正说明。此文档修正不篡改 SDK/native provenance。
