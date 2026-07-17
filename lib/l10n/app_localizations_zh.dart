// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Privi';

  @override
  String get visible => '可见';

  @override
  String get invisible => '私密';

  @override
  String get settings => '设置';

  @override
  String get more => '更多';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get create => '创建';

  @override
  String get continueAction => '继续';

  @override
  String get enable => '启用';

  @override
  String get notNow => '暂不';

  @override
  String get close => '关闭';

  @override
  String get retry => '重试';

  @override
  String get done => '完成';

  @override
  String get next => '下一步';

  @override
  String get clear => '清除';

  @override
  String get select => '选择';

  @override
  String get selectAll => '全选';

  @override
  String get search => '搜索';

  @override
  String get searchNameHint => '搜索名称…';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get sort => '排序';

  @override
  String get style => '样式';

  @override
  String get layoutStyle => '布局样式';

  @override
  String columnsCount(int count) {
    return '$count 列';
  }

  @override
  String get multiSelectItems => '多选项目';

  @override
  String get photosOnly => '仅照片';

  @override
  String get videosOnly => '仅视频';

  @override
  String get photosOnlyTapVideos => '仅照片 · 点按切换视频';

  @override
  String get videosOnlyTapPhotos => '仅视频 · 点按切换照片';

  @override
  String get newAlbum => '新建相册';

  @override
  String get newVaultAlbum => '新建私密相册';

  @override
  String get albumNameHint => '相册名称';

  @override
  String get rename => '重命名';

  @override
  String get renameAlbum => '重命名相册';

  @override
  String get deleteAlbum => '删除相册';

  @override
  String get deleteAlbumSubtitle => '媒体仍保留在“全部媒体”中';

  @override
  String get shuffle => '随机播放';

  @override
  String get restore => '还原';

  @override
  String get restoreAlbumTitle => '还原相册？';

  @override
  String restoreAlbumBody(int count, String name) {
    return '将“$name”中的 $count 项取消隐藏并还原到系统图库。';
  }

  @override
  String get unhideAllInAlbum => '还原此相册中的全部项目';

  @override
  String get pinToTop => '置顶';

  @override
  String get unpin => '取消置顶';

  @override
  String get pinnedToTop => '已置顶';

  @override
  String get unpinned => '已取消置顶';

  @override
  String get noMediaToPlay => '没有可播放的媒体';

  @override
  String get nothingToRestore => '没有可还原的内容';

  @override
  String restoredItems(int count) {
    return '已还原 $count 项';
  }

  @override
  String itemsCount(int count) {
    return '$count 项';
  }

  @override
  String errorWithDetails(String error) {
    return '错误：$error';
  }

  @override
  String get hide => '隐藏';

  @override
  String get hiding => '正在隐藏…';

  @override
  String get resolvingMedia => '正在准备媒体…';

  @override
  String get unhiding => '正在取消隐藏…';

  @override
  String hidingParallel(int workers) {
    return '正在隐藏（×$workers）…';
  }

  @override
  String get hideFolderTitle => '隐藏文件夹？';

  @override
  String hideFolderBody(String name, int count) {
    return '将“$name”中的媒体从系统图库隐藏（共 $count 项）。';
  }

  @override
  String get moveFolderToVault => '将此文件夹移入私密保险库';

  @override
  String get permissionNeeded => '需要权限';

  @override
  String get permissionNeededBody => 'Privi 需要权限才能从系统图库隐藏照片和视频。请在设置中允许后重试。';

  @override
  String get openSettings => '打开设置';

  @override
  String get openSystemSettings => '打开系统设置';

  @override
  String get grantPermission => '授予权限';

  @override
  String get allowGalleryAccess => '允许访问图库';

  @override
  String get allowGalleryAccessBody => '“可见”会列出你的照片或视频文件夹。请授予权限以便浏览和隐藏。';

  @override
  String get noPhotoFolders => '未找到照片文件夹';

  @override
  String get noVideoFolders => '未找到视频文件夹';

  @override
  String couldNotLoadGallery(String error) {
    return '无法加载图库：$error';
  }

  @override
  String get noMediaToHide => '没有可隐藏的媒体';

  @override
  String get couldNotOpenFilesToHide => '无法打开要隐藏的文件';

  @override
  String get couldNotOpenPathsToRename => '无法打开要重命名的文件路径。';

  @override
  String get couldNotHideMedia => '无法隐藏媒体，请重试。';

  @override
  String get nothingHidden => '未隐藏任何内容';

  @override
  String hiddenToAlbum(String name) {
    return '已隐藏 → 私密 / $name';
  }

  @override
  String hiddenCountToAlbum(int count, String name) {
    return '已隐藏 $count 项 → 私密 / $name';
  }

  @override
  String hiddenSharedItems(int count) {
    return '已隐藏 $count 个分享项';
  }

  @override
  String get unlockToHideShared => '解锁后即可隐藏分享的媒体';

  @override
  String get unhide => '取消隐藏';

  @override
  String unhiddenItems(int count) {
    return '已取消隐藏 $count 项';
  }

  @override
  String get share => '分享';

  @override
  String get delete => '删除';

  @override
  String get deleteFromDeviceTitle => '从设备删除？';

  @override
  String deleteFromDeviceBody(int count) {
    return '将从系统图库永久删除 $count 项。此操作无法撤销。';
  }

  @override
  String deleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String get noItemsDeleted => '未删除任何项目';

  @override
  String deletedItems(int count) {
    return '已删除 $count 项';
  }

  @override
  String selectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get noMatches => '无匹配结果';

  @override
  String get noPhotosInFolder => '此文件夹中没有照片';

  @override
  String get noVideosInFolder => '此文件夹中没有视频';

  @override
  String get playPlaylist => '播放列表';

  @override
  String get playPlaylistShuffleOn => '以随机播放开始？';

  @override
  String get playPlaylistShuffleOff => '以顺序播放开始？可在播放器中切换。';

  @override
  String get inOrder => '顺序';

  @override
  String get noExternalPlayer => '未找到外部播放器 — 改用应用内播放';

  @override
  String get openedExternalPlayer => '已在外部播放器中打开';

  @override
  String get rate => '评分';

  @override
  String get details => '详情';

  @override
  String get moveToAlbum => '移到相册';

  @override
  String get moveToRecycleBin => '移到回收站';

  @override
  String get deleteForever => '永久删除';

  @override
  String get setAsCover => '设为封面';

  @override
  String get coverUpdated => '封面已更新';

  @override
  String get unhideRestoreOriginal => '取消隐藏（还原原始名称）';

  @override
  String restoredCount(int count) {
    return '已还原 $count';
  }

  @override
  String movedToRecycleBinCount(int count) {
    return '已将 $count 项移到回收站';
  }

  @override
  String deletedForeverCount(int count) {
    return '已永久删除 $count 项';
  }

  @override
  String movedToAlbumCount(int count) {
    return '已将 $count 项移到相册';
  }

  @override
  String get createUserAlbumFirst => '请先创建用户相册';

  @override
  String get openUserAlbumToSetCover => '打开用户相册以设置封面';

  @override
  String get noMediaYet => '暂无媒体';

  @override
  String get noFavoritesYet => '暂无收藏';

  @override
  String get recycleBinEmpty => '回收站为空';

  @override
  String get noFavoritesHint => '长按媒体并用爱心评分。';

  @override
  String get recycleEmptyHint => '软删除的项目会出现在这里。';

  @override
  String get noMediaHint => '从“可见”标签隐藏媒体。';

  @override
  String get favorites => '收藏';

  @override
  String get allMedia => '全部媒体';

  @override
  String get recycleBin => '回收站';

  @override
  String get hearts => '爱心';

  @override
  String get unrated => '未评分';

  @override
  String get all => '全部';

  @override
  String get emptyRecycleBin => '清空回收站';

  @override
  String get emptyRecycleBinTitle => '清空回收站？';

  @override
  String get emptyRecycleBinBody => '永久删除所有软删除项目。';

  @override
  String purgedItems(int count) {
    return '已清理 $count 项';
  }

  @override
  String get sortNewestFirst => '最新优先';

  @override
  String get sortOldestFirst => '最早优先';

  @override
  String get sortNameAsc => '名称 A–Z';

  @override
  String get sortNameDesc => '名称 Z–A';

  @override
  String get sortHighestRating => '评分从高到低';

  @override
  String get sortLowestRating => '评分从低到高';

  @override
  String sortsCount(int count) {
    return '$count 项排序';
  }

  @override
  String progressOkSkipFail(int imported, int skipped, int failed) {
    return '成功 $imported · 跳过 $skipped · 失败 $failed';
  }

  @override
  String failedItems(int count) {
    return '失败 $count 项';
  }

  @override
  String get drawPattern => '绘制图案';

  @override
  String get confirmPattern => '确认图案';

  @override
  String get redrawPattern => '重新绘制图案';

  @override
  String get drawYourPattern => '绘制你的图案';

  @override
  String get enterYourPin => '输入 PIN';

  @override
  String get connectAtLeast4Dots => '至少连接 4 个点';

  @override
  String get unlockWithBiometric => '使用生物识别解锁';

  @override
  String get forgotPattern => '忘记图案？';

  @override
  String get forgotPatternTitle => '忘记图案？';

  @override
  String get forgotPatternBody =>
      '请使用手机的指纹、面容或屏幕锁验证身份，然后可绘制新的保险库图案。\n\n媒体仍保留在设备上；仅重置保险库解锁图案。';

  @override
  String get enableBiometricTitle => '启用生物识别解锁？';

  @override
  String get enableBiometricBody => '使用指纹或面容更快解锁。图案仍可作为备用解锁方式。';

  @override
  String get biometricNotEnabled => '未启用生物识别 — 可在设置中重试';

  @override
  String get patternsDidNotMatch => '图案不匹配 — 请重试';

  @override
  String get drawNewPatternProtect => '绘制新图案以保护保险库';

  @override
  String get sectionSecurity => '安全';

  @override
  String get sectionDisplay => '显示';

  @override
  String get sectionPlayback => '播放';

  @override
  String get sectionStorage => '存储';

  @override
  String get sectionAbout => '关于';

  @override
  String get lockNow => '立即锁定';

  @override
  String get changePattern => '更改图案';

  @override
  String get rootUnlockCredential => '主解锁凭据';

  @override
  String get biometricUnlock => '生物识别解锁';

  @override
  String get autoLock => '自动锁定';

  @override
  String get autoLockImmediately => '立即';

  @override
  String autoLockSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String autoLockMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String autoLockMinutesPlural(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get blockScreenshots => '阻止截屏';

  @override
  String get blockScreenshotsSubtitle => 'FLAG_SECURE — 在最近任务中隐藏内容';

  @override
  String get mediaGridColumns => '媒体网格列数';

  @override
  String get albumColumns => '相册列数';

  @override
  String get preferExternalPlayer => '优先使用外部播放器';

  @override
  String get shuffleByDefault => '默认随机播放';

  @override
  String get slideshowDelay => '幻灯片间隔';

  @override
  String get recycleRetention => '回收站保留时间';

  @override
  String get vaultSize => '保险库大小';

  @override
  String get exportVault => '导出保险库…';

  @override
  String get exportVaultSubtitle => '将媒体与元数据导出到文件夹';

  @override
  String get importVault => '导入保险库…';

  @override
  String get importVaultSubtitle => '从先前的导出文件夹导入';

  @override
  String get scanOrphans => '扫描孤立隐藏文件';

  @override
  String get scanningOrphans => '正在扫描孤立隐藏文件…';

  @override
  String get recoverVault => '重装后恢复保险库';

  @override
  String get recoverVaultSubtitle => '重新索引仍在 .privateheart_vault 中的媒体';

  @override
  String get recoverVaultBody =>
      '扫描磁盘上的保险库文件夹，把缺失项带回 Invisible。卸载重装后文件仍在手机上时使用。';

  @override
  String get recoverAndUnhide => '恢复并还原到图库';

  @override
  String get recoverAndUnhideSubtitle => '重新索引保险库文件并取消隐藏';

  @override
  String get recoverAndUnhideBody =>
      '重新索引保险库文件夹中的文件，再移回公共目录（下载/已知原路径）。重装后若希望图库再次可见时使用。';

  @override
  String get recoveringVault => '正在恢复保险库文件…';

  @override
  String get repairCaptureDates => '修复拍摄日期';

  @override
  String get repairCaptureDatesSubtitle => '按原始拍摄时间修正保险库排序（非隐藏时间）';

  @override
  String get repairingCaptureDates => '正在修复拍摄日期…';

  @override
  String get author => '作者';

  @override
  String get license => '许可证';

  @override
  String get couldNotOpenBrowser => '无法打开浏览器';

  @override
  String versionLabel(String version) {
    return '版本 $version';
  }

  @override
  String authorLabel(String author) {
    return '作者：$author';
  }

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String scanFailed(String error) {
    return '扫描失败：$error';
  }

  @override
  String exportedMedia(int count) {
    return '已导出 $count 个媒体文件及清单';
  }

  @override
  String get playing => '正在播放';

  @override
  String get emptyPlaylist => '播放列表为空';

  @override
  String get openExternal => '外部打开';

  @override
  String get typeLabel => '类型';

  @override
  String get typeVideo => '视频';

  @override
  String get typeImage => '图片';

  @override
  String get nameLabel => '名称';

  @override
  String get sizeLabel => '大小';

  @override
  String get pathLabel => '路径';

  @override
  String get ratingLabel => '评分';

  @override
  String get currentPattern => '当前图案';

  @override
  String get newPattern => '新图案';

  @override
  String get confirmNewPattern => '确认新图案';

  @override
  String get patternUpdated => '图案已更新';

  @override
  String get newPatternsDidNotMatch => '新图案不匹配';

  @override
  String get drawCurrentPattern => '绘制当前图案以继续';

  @override
  String get drawSamePatternAgain => '请再次绘制相同图案';

  @override
  String get currentPin => '当前 PIN';

  @override
  String get enterPinThenPattern => '输入 PIN，然后设置新图案';

  @override
  String get pin => 'PIN';

  @override
  String get retention => '保留时间';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageZhCn => '简体中文';

  @override
  String get languageZhHk => '繁體中文（香港）';

  @override
  String get verifyIdentity => '验证身份';

  @override
  String get unlockPrivi => '解锁 Privi';

  @override
  String get biometricAvailable => '可用时使用指纹 / 面容';

  @override
  String get biometricUnavailable => '此设备不可用';

  @override
  String get biometricCancelled => '未启用生物识别（已取消或失败）';

  @override
  String get biometricUpdateFailed => '无法更新生物识别设置';

  @override
  String get externalPlayerSubtitle => '将视频交给 VLC / 系统播放器';

  @override
  String get scanOrphansSubtitle => '查找库中缺失的保险库文件';

  @override
  String retentionDays(int days) {
    return '$days 天';
  }

  @override
  String get retention1Day => '1 天';

  @override
  String secondsCount(int n) {
    return '$n 秒';
  }

  @override
  String secondCount(int n) {
    return '$n 秒';
  }

  @override
  String get empty => '清空';

  @override
  String get couldNotOpenExternally => '无法用外部应用打开 — 改用应用内预览';

  @override
  String get openWith => '打开方式';

  @override
  String get playVideoWith => '播放视频';

  @override
  String get calculating => '计算中…';

  @override
  String get cancelled => '已取消';

  @override
  String get restoredToGallery => '已还原到图库';

  @override
  String get couldNotUnhideFile => '无法取消隐藏文件';

  @override
  String get favoriteToggle => '收藏';

  @override
  String ratedHearts(int rating) {
    return '已评 $rating / 3 心';
  }

  @override
  String get confirmBiometricEnable => '确认以启用生物识别解锁';

  @override
  String get confirmResetPattern => '确认身份以重置 Privi 图案';

  @override
  String get wrongPattern => '图案错误';

  @override
  String get wrongPin => 'PIN 错误';

  @override
  String get noSystemLock => '请先在 Android 设置中启用屏幕锁定';

  @override
  String get systemAuthCancelled => '系统验证已取消';

  @override
  String get scanFailedShort => '扫描失败';

  @override
  String get screenshotSettingFailed => '无法更新截屏保护';

  @override
  String get noOrphanVaultFiles => '未找到保险库文件';

  @override
  String recoveryResult(int recovered, int skipped, int failed) {
    return '已恢复 $recovered · 跳过 $skipped · 失败 $failed';
  }

  @override
  String galleryRecoveryResult(int restored, int skipped, int failed) {
    return '已还原 $restored · 跳过 $skipped · 失败 $failed';
  }

  @override
  String get noVaultMediaToRepair => '没有需要修复的媒体';

  @override
  String captureDateRepairResult(int fixed, int skipped, int failed) {
    return '已修复 $fixed · 跳过 $skipped · 失败 $failed';
  }

  @override
  String unlockLockout(int seconds) {
    return '请在 $seconds 秒后重试';
  }
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get appName => 'Privi';

  @override
  String get visible => '可见';

  @override
  String get invisible => '私密';

  @override
  String get settings => '设置';

  @override
  String get more => '更多';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get create => '创建';

  @override
  String get continueAction => '继续';

  @override
  String get enable => '启用';

  @override
  String get notNow => '暂不';

  @override
  String get close => '关闭';

  @override
  String get retry => '重试';

  @override
  String get done => '完成';

  @override
  String get next => '下一步';

  @override
  String get clear => '清除';

  @override
  String get select => '选择';

  @override
  String get selectAll => '全选';

  @override
  String get search => '搜索';

  @override
  String get searchNameHint => '搜索名称…';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get sort => '排序';

  @override
  String get style => '样式';

  @override
  String get layoutStyle => '布局样式';

  @override
  String columnsCount(int count) {
    return '$count 列';
  }

  @override
  String get multiSelectItems => '多选项目';

  @override
  String get photosOnly => '仅照片';

  @override
  String get videosOnly => '仅视频';

  @override
  String get photosOnlyTapVideos => '仅照片 · 点按切换视频';

  @override
  String get videosOnlyTapPhotos => '仅视频 · 点按切换照片';

  @override
  String get newAlbum => '新建相册';

  @override
  String get newVaultAlbum => '新建私密相册';

  @override
  String get albumNameHint => '相册名称';

  @override
  String get rename => '重命名';

  @override
  String get renameAlbum => '重命名相册';

  @override
  String get deleteAlbum => '删除相册';

  @override
  String get deleteAlbumSubtitle => '媒体仍保留在“全部媒体”中';

  @override
  String get shuffle => '随机播放';

  @override
  String get restore => '还原';

  @override
  String get restoreAlbumTitle => '还原相册？';

  @override
  String restoreAlbumBody(int count, String name) {
    return '将“$name”中的 $count 项取消隐藏并还原到系统图库。';
  }

  @override
  String get unhideAllInAlbum => '还原此相册中的全部项目';

  @override
  String get pinToTop => '置顶';

  @override
  String get unpin => '取消置顶';

  @override
  String get pinnedToTop => '已置顶';

  @override
  String get unpinned => '已取消置顶';

  @override
  String get noMediaToPlay => '没有可播放的媒体';

  @override
  String get nothingToRestore => '没有可还原的内容';

  @override
  String restoredItems(int count) {
    return '已还原 $count 项';
  }

  @override
  String itemsCount(int count) {
    return '$count 项';
  }

  @override
  String errorWithDetails(String error) {
    return '错误：$error';
  }

  @override
  String get hide => '隐藏';

  @override
  String get hiding => '正在隐藏…';

  @override
  String get resolvingMedia => '正在准备媒体…';

  @override
  String get unhiding => '正在取消隐藏…';

  @override
  String hidingParallel(int workers) {
    return '正在隐藏（×$workers）…';
  }

  @override
  String get hideFolderTitle => '隐藏文件夹？';

  @override
  String hideFolderBody(String name, int count) {
    return '将“$name”中的媒体从系统图库隐藏（共 $count 项）。';
  }

  @override
  String get moveFolderToVault => '将此文件夹移入私密保险库';

  @override
  String get permissionNeeded => '需要权限';

  @override
  String get permissionNeededBody => 'Privi 需要权限才能从系统图库隐藏照片和视频。请在设置中允许后重试。';

  @override
  String get openSettings => '打开设置';

  @override
  String get openSystemSettings => '打开系统设置';

  @override
  String get grantPermission => '授予权限';

  @override
  String get allowGalleryAccess => '允许访问图库';

  @override
  String get allowGalleryAccessBody => '“可见”会列出你的照片或视频文件夹。请授予权限以便浏览和隐藏。';

  @override
  String get noPhotoFolders => '未找到照片文件夹';

  @override
  String get noVideoFolders => '未找到视频文件夹';

  @override
  String couldNotLoadGallery(String error) {
    return '无法加载图库：$error';
  }

  @override
  String get noMediaToHide => '没有可隐藏的媒体';

  @override
  String get couldNotOpenFilesToHide => '无法打开要隐藏的文件';

  @override
  String get couldNotOpenPathsToRename => '无法打开要重命名的文件路径。';

  @override
  String get couldNotHideMedia => '无法隐藏媒体，请重试。';

  @override
  String get nothingHidden => '未隐藏任何内容';

  @override
  String hiddenToAlbum(String name) {
    return '已隐藏 → 私密 / $name';
  }

  @override
  String hiddenCountToAlbum(int count, String name) {
    return '已隐藏 $count 项 → 私密 / $name';
  }

  @override
  String hiddenSharedItems(int count) {
    return '已隐藏 $count 个分享项';
  }

  @override
  String get unlockToHideShared => '解锁后即可隐藏分享的媒体';

  @override
  String get unhide => '取消隐藏';

  @override
  String unhiddenItems(int count) {
    return '已取消隐藏 $count 项';
  }

  @override
  String get share => '分享';

  @override
  String get delete => '删除';

  @override
  String get deleteFromDeviceTitle => '从设备删除？';

  @override
  String deleteFromDeviceBody(int count) {
    return '将从系统图库永久删除 $count 项。此操作无法撤销。';
  }

  @override
  String deleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String get noItemsDeleted => '未删除任何项目';

  @override
  String deletedItems(int count) {
    return '已删除 $count 项';
  }

  @override
  String selectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get noMatches => '无匹配结果';

  @override
  String get noPhotosInFolder => '此文件夹中没有照片';

  @override
  String get noVideosInFolder => '此文件夹中没有视频';

  @override
  String get playPlaylist => '播放列表';

  @override
  String get playPlaylistShuffleOn => '以随机播放开始？';

  @override
  String get playPlaylistShuffleOff => '以顺序播放开始？可在播放器中切换。';

  @override
  String get inOrder => '顺序';

  @override
  String get noExternalPlayer => '未找到外部播放器 — 改用应用内播放';

  @override
  String get openedExternalPlayer => '已在外部播放器中打开';

  @override
  String get rate => '评分';

  @override
  String get details => '详情';

  @override
  String get moveToAlbum => '移到相册';

  @override
  String get moveToRecycleBin => '移到回收站';

  @override
  String get deleteForever => '永久删除';

  @override
  String get setAsCover => '设为封面';

  @override
  String get coverUpdated => '封面已更新';

  @override
  String get unhideRestoreOriginal => '取消隐藏（还原原始名称）';

  @override
  String restoredCount(int count) {
    return '已还原 $count';
  }

  @override
  String movedToRecycleBinCount(int count) {
    return '已将 $count 项移到回收站';
  }

  @override
  String deletedForeverCount(int count) {
    return '已永久删除 $count 项';
  }

  @override
  String movedToAlbumCount(int count) {
    return '已将 $count 项移到相册';
  }

  @override
  String get createUserAlbumFirst => '请先创建用户相册';

  @override
  String get openUserAlbumToSetCover => '打开用户相册以设置封面';

  @override
  String get noMediaYet => '暂无媒体';

  @override
  String get noFavoritesYet => '暂无收藏';

  @override
  String get recycleBinEmpty => '回收站为空';

  @override
  String get noFavoritesHint => '长按媒体并用爱心评分。';

  @override
  String get recycleEmptyHint => '软删除的项目会出现在这里。';

  @override
  String get noMediaHint => '从“可见”标签隐藏媒体。';

  @override
  String get favorites => '收藏';

  @override
  String get allMedia => '全部媒体';

  @override
  String get recycleBin => '回收站';

  @override
  String get hearts => '爱心';

  @override
  String get unrated => '未评分';

  @override
  String get all => '全部';

  @override
  String get emptyRecycleBin => '清空回收站';

  @override
  String get emptyRecycleBinTitle => '清空回收站？';

  @override
  String get emptyRecycleBinBody => '永久删除所有软删除项目。';

  @override
  String purgedItems(int count) {
    return '已清理 $count 项';
  }

  @override
  String get sortNewestFirst => '最新优先';

  @override
  String get sortOldestFirst => '最早优先';

  @override
  String get sortNameAsc => '名称 A–Z';

  @override
  String get sortNameDesc => '名称 Z–A';

  @override
  String get sortHighestRating => '评分从高到低';

  @override
  String get sortLowestRating => '评分从低到高';

  @override
  String sortsCount(int count) {
    return '$count 项排序';
  }

  @override
  String progressOkSkipFail(int imported, int skipped, int failed) {
    return '成功 $imported · 跳过 $skipped · 失败 $failed';
  }

  @override
  String failedItems(int count) {
    return '失败 $count 项';
  }

  @override
  String get drawPattern => '绘制图案';

  @override
  String get confirmPattern => '确认图案';

  @override
  String get redrawPattern => '重新绘制图案';

  @override
  String get drawYourPattern => '绘制你的图案';

  @override
  String get enterYourPin => '输入 PIN';

  @override
  String get connectAtLeast4Dots => '至少连接 4 个点';

  @override
  String get unlockWithBiometric => '使用生物识别解锁';

  @override
  String get forgotPattern => '忘记图案？';

  @override
  String get forgotPatternTitle => '忘记图案？';

  @override
  String get forgotPatternBody =>
      '请使用手机的指纹、面容或屏幕锁验证身份，然后可绘制新的保险库图案。\n\n媒体仍保留在设备上；仅重置保险库解锁图案。';

  @override
  String get enableBiometricTitle => '启用生物识别解锁？';

  @override
  String get enableBiometricBody => '使用指纹或面容更快解锁。图案仍可作为备用解锁方式。';

  @override
  String get biometricNotEnabled => '未启用生物识别 — 可在设置中重试';

  @override
  String get patternsDidNotMatch => '图案不匹配 — 请重试';

  @override
  String get drawNewPatternProtect => '绘制新图案以保护保险库';

  @override
  String get sectionSecurity => '安全';

  @override
  String get sectionDisplay => '显示';

  @override
  String get sectionPlayback => '播放';

  @override
  String get sectionStorage => '存储';

  @override
  String get sectionAbout => '关于';

  @override
  String get lockNow => '立即锁定';

  @override
  String get changePattern => '更改图案';

  @override
  String get rootUnlockCredential => '主解锁凭据';

  @override
  String get biometricUnlock => '生物识别解锁';

  @override
  String get autoLock => '自动锁定';

  @override
  String get autoLockImmediately => '立即';

  @override
  String autoLockSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String autoLockMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String autoLockMinutesPlural(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get blockScreenshots => '阻止截屏';

  @override
  String get blockScreenshotsSubtitle => 'FLAG_SECURE — 在最近任务中隐藏内容';

  @override
  String get mediaGridColumns => '媒体网格列数';

  @override
  String get albumColumns => '相册列数';

  @override
  String get preferExternalPlayer => '优先使用外部播放器';

  @override
  String get shuffleByDefault => '默认随机播放';

  @override
  String get slideshowDelay => '幻灯片间隔';

  @override
  String get recycleRetention => '回收站保留时间';

  @override
  String get vaultSize => '保险库大小';

  @override
  String get exportVault => '导出保险库…';

  @override
  String get exportVaultSubtitle => '将媒体与元数据导出到文件夹';

  @override
  String get importVault => '导入保险库…';

  @override
  String get importVaultSubtitle => '从先前的导出文件夹导入';

  @override
  String get scanOrphans => '扫描孤立隐藏文件';

  @override
  String get scanningOrphans => '正在扫描孤立隐藏文件…';

  @override
  String get recoverVault => '重装后恢复保险库';

  @override
  String get recoverVaultSubtitle => '重新索引仍在 .privateheart_vault 中的媒体';

  @override
  String get recoverVaultBody =>
      '扫描磁盘上的保险库文件夹，把缺失项带回 Invisible。卸载重装后文件仍在手机上时使用。';

  @override
  String get recoverAndUnhide => '恢复并还原到图库';

  @override
  String get recoverAndUnhideSubtitle => '重新索引保险库文件并取消隐藏';

  @override
  String get recoverAndUnhideBody =>
      '重新索引保险库文件夹中的文件，再移回公共目录（下载/已知原路径）。重装后若希望图库再次可见时使用。';

  @override
  String get recoveringVault => '正在恢复保险库文件…';

  @override
  String get repairCaptureDates => '修复拍摄日期';

  @override
  String get repairCaptureDatesSubtitle => '按原始拍摄时间修正保险库排序（非隐藏时间）';

  @override
  String get repairingCaptureDates => '正在修复拍摄日期…';

  @override
  String get author => '作者';

  @override
  String get license => '许可证';

  @override
  String get couldNotOpenBrowser => '无法打开浏览器';

  @override
  String versionLabel(String version) {
    return '版本 $version';
  }

  @override
  String authorLabel(String author) {
    return '作者：$author';
  }

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String scanFailed(String error) {
    return '扫描失败：$error';
  }

  @override
  String exportedMedia(int count) {
    return '已导出 $count 个媒体文件及清单';
  }

  @override
  String get playing => '正在播放';

  @override
  String get emptyPlaylist => '播放列表为空';

  @override
  String get openExternal => '外部打开';

  @override
  String get typeLabel => '类型';

  @override
  String get typeVideo => '视频';

  @override
  String get typeImage => '图片';

  @override
  String get nameLabel => '名称';

  @override
  String get sizeLabel => '大小';

  @override
  String get pathLabel => '路径';

  @override
  String get ratingLabel => '评分';

  @override
  String get currentPattern => '当前图案';

  @override
  String get newPattern => '新图案';

  @override
  String get confirmNewPattern => '确认新图案';

  @override
  String get patternUpdated => '图案已更新';

  @override
  String get newPatternsDidNotMatch => '新图案不匹配';

  @override
  String get drawCurrentPattern => '绘制当前图案以继续';

  @override
  String get drawSamePatternAgain => '请再次绘制相同图案';

  @override
  String get currentPin => '当前 PIN';

  @override
  String get enterPinThenPattern => '输入 PIN，然后设置新图案';

  @override
  String get pin => 'PIN';

  @override
  String get retention => '保留时间';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageZhCn => '简体中文';

  @override
  String get languageZhHk => '繁體中文（香港）';

  @override
  String get verifyIdentity => '验证身份';

  @override
  String get unlockPrivi => '解锁 Privi';

  @override
  String get biometricAvailable => '可用时使用指纹 / 面容';

  @override
  String get biometricUnavailable => '此设备不可用';

  @override
  String get biometricCancelled => '未启用生物识别（已取消或失败）';

  @override
  String get biometricUpdateFailed => '无法更新生物识别设置';

  @override
  String get externalPlayerSubtitle => '将视频交给 VLC / 系统播放器';

  @override
  String get scanOrphansSubtitle => '查找库中缺失的保险库文件';

  @override
  String retentionDays(int days) {
    return '$days 天';
  }

  @override
  String get retention1Day => '1 天';

  @override
  String secondsCount(int n) {
    return '$n 秒';
  }

  @override
  String secondCount(int n) {
    return '$n 秒';
  }

  @override
  String get empty => '清空';

  @override
  String get couldNotOpenExternally => '无法用外部应用打开 — 改用应用内预览';

  @override
  String get openWith => '打开方式';

  @override
  String get playVideoWith => '播放视频';

  @override
  String get calculating => '计算中…';

  @override
  String get cancelled => '已取消';

  @override
  String get restoredToGallery => '已还原到图库';

  @override
  String get couldNotUnhideFile => '无法取消隐藏文件';

  @override
  String get favoriteToggle => '收藏';

  @override
  String ratedHearts(int rating) {
    return '已评 $rating / 3 心';
  }

  @override
  String get confirmBiometricEnable => '确认以启用生物识别解锁';

  @override
  String get confirmResetPattern => '确认身份以重置 Privi 图案';

  @override
  String get wrongPattern => '图案错误';

  @override
  String get wrongPin => 'PIN 错误';

  @override
  String get noSystemLock => '请先在 Android 设置中启用屏幕锁定';

  @override
  String get systemAuthCancelled => '系统验证已取消';

  @override
  String get scanFailedShort => '扫描失败';

  @override
  String get screenshotSettingFailed => '无法更新截屏保护';

  @override
  String get noOrphanVaultFiles => '未找到保险库文件';

  @override
  String recoveryResult(int recovered, int skipped, int failed) {
    return '已恢复 $recovered · 跳过 $skipped · 失败 $failed';
  }

  @override
  String galleryRecoveryResult(int restored, int skipped, int failed) {
    return '已还原 $restored · 跳过 $skipped · 失败 $failed';
  }

  @override
  String get noVaultMediaToRepair => '没有需要修复的媒体';

  @override
  String captureDateRepairResult(int fixed, int skipped, int failed) {
    return '已修复 $fixed · 跳过 $skipped · 失败 $failed';
  }

  @override
  String unlockLockout(int seconds) {
    return '请在 $seconds 秒后重试';
  }
}

/// The translations for Chinese, as used in Hong Kong (`zh_HK`).
class AppLocalizationsZhHk extends AppLocalizationsZh {
  AppLocalizationsZhHk() : super('zh_HK');

  @override
  String get appName => 'Privi';

  @override
  String get visible => '可見';

  @override
  String get invisible => '私密';

  @override
  String get settings => '設定';

  @override
  String get more => '更多';

  @override
  String get cancel => '取消';

  @override
  String get save => '儲存';

  @override
  String get create => '建立';

  @override
  String get continueAction => '繼續';

  @override
  String get enable => '啟用';

  @override
  String get notNow => '暫時不要';

  @override
  String get close => '關閉';

  @override
  String get retry => '重試';

  @override
  String get done => '完成';

  @override
  String get next => '下一步';

  @override
  String get clear => '清除';

  @override
  String get select => '選擇';

  @override
  String get selectAll => '全選';

  @override
  String get search => '搜尋';

  @override
  String get searchNameHint => '搜尋名稱…';

  @override
  String get closeSearch => '關閉搜尋';

  @override
  String get sort => '排序';

  @override
  String get style => '樣式';

  @override
  String get layoutStyle => '版面樣式';

  @override
  String columnsCount(int count) {
    return '$count 欄';
  }

  @override
  String get multiSelectItems => '多選項目';

  @override
  String get photosOnly => '只限相片';

  @override
  String get videosOnly => '只限影片';

  @override
  String get photosOnlyTapVideos => '只限相片 · 點按切換影片';

  @override
  String get videosOnlyTapPhotos => '只限影片 · 點按切換相片';

  @override
  String get newAlbum => '新增相簿';

  @override
  String get newVaultAlbum => '新增私密相簿';

  @override
  String get albumNameHint => '相簿名稱';

  @override
  String get rename => '重新命名';

  @override
  String get renameAlbum => '重新命名相簿';

  @override
  String get deleteAlbum => '刪除相簿';

  @override
  String get deleteAlbumSubtitle => '媒體仍保留在「全部媒體」中';

  @override
  String get shuffle => '隨機播放';

  @override
  String get restore => '還原';

  @override
  String get restoreAlbumTitle => '還原相簿？';

  @override
  String restoreAlbumBody(int count, String name) {
    return '將「$name」中的 $count 項取消隱藏並還原到系統圖庫。';
  }

  @override
  String get unhideAllInAlbum => '還原此相簿中的全部項目';

  @override
  String get pinToTop => '置頂';

  @override
  String get unpin => '取消置頂';

  @override
  String get pinnedToTop => '已置頂';

  @override
  String get unpinned => '已取消置頂';

  @override
  String get noMediaToPlay => '沒有可播放的媒體';

  @override
  String get nothingToRestore => '沒有可還原的內容';

  @override
  String restoredItems(int count) {
    return '已還原 $count 項';
  }

  @override
  String itemsCount(int count) {
    return '$count 項';
  }

  @override
  String errorWithDetails(String error) {
    return '錯誤：$error';
  }

  @override
  String get hide => '隱藏';

  @override
  String get hiding => '正在隱藏…';

  @override
  String get resolvingMedia => '正在準備媒體…';

  @override
  String get unhiding => '正在取消隱藏…';

  @override
  String hidingParallel(int workers) {
    return '正在隱藏（×$workers）…';
  }

  @override
  String get hideFolderTitle => '隱藏資料夾？';

  @override
  String hideFolderBody(String name, int count) {
    return '將「$name」中的媒體從系統圖庫隱藏（共 $count 項）。';
  }

  @override
  String get moveFolderToVault => '將此資料夾移入私密保險庫';

  @override
  String get permissionNeeded => '需要權限';

  @override
  String get permissionNeededBody => 'Privi 需要權限才能從系統圖庫隱藏相片和影片。請在設定中允許後再試。';

  @override
  String get openSettings => '開啟設定';

  @override
  String get openSystemSettings => '開啟系統設定';

  @override
  String get grantPermission => '授予權限';

  @override
  String get allowGalleryAccess => '允許存取圖庫';

  @override
  String get allowGalleryAccessBody => '「可見」會列出你的相片或影片資料夾。請授予權限以便瀏覽和隱藏。';

  @override
  String get noPhotoFolders => '找不到相片資料夾';

  @override
  String get noVideoFolders => '找不到影片資料夾';

  @override
  String couldNotLoadGallery(String error) {
    return '無法載入圖庫：$error';
  }

  @override
  String get noMediaToHide => '沒有可隱藏的媒體';

  @override
  String get couldNotOpenFilesToHide => '無法開啟要隱藏的檔案';

  @override
  String get couldNotOpenPathsToRename => '無法開啟要重新命名的檔案路徑。';

  @override
  String get couldNotHideMedia => '無法隱藏媒體，請再試一次。';

  @override
  String get nothingHidden => '未隱藏任何內容';

  @override
  String hiddenToAlbum(String name) {
    return '已隱藏 → 私密 / $name';
  }

  @override
  String hiddenCountToAlbum(int count, String name) {
    return '已隱藏 $count 項 → 私密 / $name';
  }

  @override
  String hiddenSharedItems(int count) {
    return '已隱藏 $count 個分享項目';
  }

  @override
  String get unlockToHideShared => '解鎖後即可隱藏分享的媒體';

  @override
  String get unhide => '取消隱藏';

  @override
  String unhiddenItems(int count) {
    return '已取消隱藏 $count 項';
  }

  @override
  String get share => '分享';

  @override
  String get delete => '刪除';

  @override
  String get deleteFromDeviceTitle => '從裝置刪除？';

  @override
  String deleteFromDeviceBody(int count) {
    return '將從系統圖庫永久刪除 $count 項。此操作無法復原。';
  }

  @override
  String deleteFailed(String error) {
    return '刪除失敗：$error';
  }

  @override
  String get noItemsDeleted => '未刪除任何項目';

  @override
  String deletedItems(int count) {
    return '已刪除 $count 項';
  }

  @override
  String selectedCount(int count) {
    return '已選 $count 項';
  }

  @override
  String get noMatches => '沒有相符結果';

  @override
  String get noPhotosInFolder => '此資料夾沒有相片';

  @override
  String get noVideosInFolder => '此資料夾沒有影片';

  @override
  String get playPlaylist => '播放清單';

  @override
  String get playPlaylistShuffleOn => '以隨機播放開始？';

  @override
  String get playPlaylistShuffleOff => '以順序播放開始？可在播放器中切換。';

  @override
  String get inOrder => '順序';

  @override
  String get noExternalPlayer => '找不到外部播放器 — 改用應用程式內播放';

  @override
  String get openedExternalPlayer => '已在外部播放器開啟';

  @override
  String get rate => '評分';

  @override
  String get details => '詳細資料';

  @override
  String get moveToAlbum => '移至相簿';

  @override
  String get moveToRecycleBin => '移至回收站';

  @override
  String get deleteForever => '永久刪除';

  @override
  String get setAsCover => '設為封面';

  @override
  String get coverUpdated => '封面已更新';

  @override
  String get unhideRestoreOriginal => '取消隱藏（還原原始名稱）';

  @override
  String restoredCount(int count) {
    return '已還原 $count';
  }

  @override
  String movedToRecycleBinCount(int count) {
    return '已將 $count 項移至回收站';
  }

  @override
  String deletedForeverCount(int count) {
    return '已永久刪除 $count 項';
  }

  @override
  String movedToAlbumCount(int count) {
    return '已將 $count 項移至相簿';
  }

  @override
  String get createUserAlbumFirst => '請先建立使用者相簿';

  @override
  String get openUserAlbumToSetCover => '開啟使用者相簿以設定封面';

  @override
  String get noMediaYet => '暫無媒體';

  @override
  String get noFavoritesYet => '暫無收藏';

  @override
  String get recycleBinEmpty => '回收站是空的';

  @override
  String get noFavoritesHint => '長按媒體並以愛心評分。';

  @override
  String get recycleEmptyHint => '已軟刪除的項目會出現在這裡。';

  @override
  String get noMediaHint => '從「可見」分頁隱藏媒體。';

  @override
  String get favorites => '收藏';

  @override
  String get allMedia => '全部媒體';

  @override
  String get recycleBin => '回收站';

  @override
  String get hearts => '愛心';

  @override
  String get unrated => '未評分';

  @override
  String get all => '全部';

  @override
  String get emptyRecycleBin => '清空回收站';

  @override
  String get emptyRecycleBinTitle => '清空回收站？';

  @override
  String get emptyRecycleBinBody => '永久刪除所有已軟刪除的項目。';

  @override
  String purgedItems(int count) {
    return '已清理 $count 項';
  }

  @override
  String get sortNewestFirst => '最新優先';

  @override
  String get sortOldestFirst => '最舊優先';

  @override
  String get sortNameAsc => '名稱 A–Z';

  @override
  String get sortNameDesc => '名稱 Z–A';

  @override
  String get sortHighestRating => '評分由高至低';

  @override
  String get sortLowestRating => '評分由低至高';

  @override
  String sortsCount(int count) {
    return '$count 項排序';
  }

  @override
  String progressOkSkipFail(int imported, int skipped, int failed) {
    return '成功 $imported · 略過 $skipped · 失敗 $failed';
  }

  @override
  String failedItems(int count) {
    return '失敗 $count 項';
  }

  @override
  String get drawPattern => '繪製圖案';

  @override
  String get confirmPattern => '確認圖案';

  @override
  String get redrawPattern => '重新繪製圖案';

  @override
  String get drawYourPattern => '繪製你的圖案';

  @override
  String get enterYourPin => '輸入 PIN';

  @override
  String get connectAtLeast4Dots => '至少連接 4 個點';

  @override
  String get unlockWithBiometric => '使用生物認證解鎖';

  @override
  String get forgotPattern => '忘記圖案？';

  @override
  String get forgotPatternTitle => '忘記圖案？';

  @override
  String get forgotPatternBody =>
      '請使用手機的指紋、面容或螢幕鎖驗證身分，然後可繪製新的保險庫圖案。\n\n媒體仍保留在裝置上；只會重設保險庫解鎖圖案。';

  @override
  String get enableBiometricTitle => '啟用生物認證解鎖？';

  @override
  String get enableBiometricBody => '使用指紋或面容更快解鎖。圖案仍可作為後備解鎖方式。';

  @override
  String get biometricNotEnabled => '未啟用生物認證 — 可在設定中再試';

  @override
  String get patternsDidNotMatch => '圖案不相符 — 請再試';

  @override
  String get drawNewPatternProtect => '繪製新圖案以保護保險庫';

  @override
  String get sectionSecurity => '保安';

  @override
  String get sectionDisplay => '顯示';

  @override
  String get sectionPlayback => '播放';

  @override
  String get sectionStorage => '儲存空間';

  @override
  String get sectionAbout => '關於';

  @override
  String get lockNow => '立即鎖定';

  @override
  String get changePattern => '更改圖案';

  @override
  String get rootUnlockCredential => '主解鎖憑證';

  @override
  String get biometricUnlock => '生物認證解鎖';

  @override
  String get autoLock => '自動鎖定';

  @override
  String get autoLockImmediately => '立即';

  @override
  String autoLockSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String autoLockMinutes(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String autoLockMinutesPlural(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String get blockScreenshots => '阻止截圖';

  @override
  String get blockScreenshotsSubtitle => 'FLAG_SECURE — 在最近工作中隱藏內容';

  @override
  String get mediaGridColumns => '媒體網格欄數';

  @override
  String get albumColumns => '相簿欄數';

  @override
  String get preferExternalPlayer => '優先使用外部播放器';

  @override
  String get shuffleByDefault => '預設隨機播放';

  @override
  String get slideshowDelay => '投影片間隔';

  @override
  String get recycleRetention => '回收站保留時間';

  @override
  String get vaultSize => '保險庫大小';

  @override
  String get exportVault => '匯出保險庫…';

  @override
  String get exportVaultSubtitle => '將媒體與中繼資料匯出至資料夾';

  @override
  String get importVault => '匯入保險庫…';

  @override
  String get importVaultSubtitle => '從先前的匯出資料夾匯入';

  @override
  String get scanOrphans => '掃描孤立隱藏檔案';

  @override
  String get scanningOrphans => '正在掃描孤立隱藏檔案…';

  @override
  String get recoverVault => '重裝後復原保險庫';

  @override
  String get recoverVaultSubtitle => '重新索引仍在 .privateheart_vault 中的媒體';

  @override
  String get recoverVaultBody =>
      '掃描磁碟上的保險庫資料夾，把缺失項目帶回 Invisible。解除安裝重裝後檔案仍在手機上時使用。';

  @override
  String get recoverAndUnhide => '復原並還原到相簿';

  @override
  String get recoverAndUnhideSubtitle => '重新索引保險庫檔案並取消隱藏';

  @override
  String get recoverAndUnhideBody =>
      '重新索引保險庫資料夾中的檔案，再移回公共目錄（下載/已知原路徑）。重裝後若希望相簿再次可見時使用。';

  @override
  String get recoveringVault => '正在復原保險庫檔案…';

  @override
  String get repairCaptureDates => '修復拍攝日期';

  @override
  String get repairCaptureDatesSubtitle => '按原始拍攝時間修正保險庫排序（非隱藏時間）';

  @override
  String get repairingCaptureDates => '正在修復拍攝日期…';

  @override
  String get author => '作者';

  @override
  String get license => '授權條款';

  @override
  String get couldNotOpenBrowser => '無法開啟瀏覽器';

  @override
  String versionLabel(String version) {
    return '版本 $version';
  }

  @override
  String authorLabel(String author) {
    return '作者：$author';
  }

  @override
  String exportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String importFailed(String error) {
    return '匯入失敗：$error';
  }

  @override
  String scanFailed(String error) {
    return '掃描失敗：$error';
  }

  @override
  String exportedMedia(int count) {
    return '已匯出 $count 個媒體檔案及清單';
  }

  @override
  String get playing => '正在播放';

  @override
  String get emptyPlaylist => '播放清單是空的';

  @override
  String get openExternal => '以外部開啟';

  @override
  String get typeLabel => '類型';

  @override
  String get typeVideo => '影片';

  @override
  String get typeImage => '圖片';

  @override
  String get nameLabel => '名稱';

  @override
  String get sizeLabel => '大小';

  @override
  String get pathLabel => '路徑';

  @override
  String get ratingLabel => '評分';

  @override
  String get currentPattern => '目前圖案';

  @override
  String get newPattern => '新圖案';

  @override
  String get confirmNewPattern => '確認新圖案';

  @override
  String get patternUpdated => '圖案已更新';

  @override
  String get newPatternsDidNotMatch => '新圖案不相符';

  @override
  String get drawCurrentPattern => '繪製目前圖案以繼續';

  @override
  String get drawSamePatternAgain => '請再次繪製相同圖案';

  @override
  String get currentPin => '目前 PIN';

  @override
  String get enterPinThenPattern => '輸入 PIN，然後設定新圖案';

  @override
  String get pin => 'PIN';

  @override
  String get retention => '保留時間';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageZhCn => '简体中文';

  @override
  String get languageZhHk => '繁體中文（香港）';

  @override
  String get verifyIdentity => '驗證身分';

  @override
  String get unlockPrivi => '解鎖 Privi';

  @override
  String get biometricAvailable => '可用時使用指紋 / 面容';

  @override
  String get biometricUnavailable => '此裝置不可用';

  @override
  String get biometricCancelled => '未啟用生物認證（已取消或失敗）';

  @override
  String get biometricUpdateFailed => '無法更新生物認證設定';

  @override
  String get externalPlayerSubtitle => '將影片交予 VLC / 系統播放器';

  @override
  String get scanOrphansSubtitle => '查找資料庫中缺失的保險庫檔案';

  @override
  String retentionDays(int days) {
    return '$days 日';
  }

  @override
  String get retention1Day => '1 日';

  @override
  String secondsCount(int n) {
    return '$n 秒';
  }

  @override
  String secondCount(int n) {
    return '$n 秒';
  }

  @override
  String get empty => '清空';

  @override
  String get couldNotOpenExternally => '無法以外部應用程式開啟 — 改用應用程式內預覽';

  @override
  String get openWith => '開啟方式';

  @override
  String get playVideoWith => '播放影片';

  @override
  String get calculating => '計算中…';

  @override
  String get cancelled => '已取消';

  @override
  String get restoredToGallery => '已還原到圖庫';

  @override
  String get couldNotUnhideFile => '無法取消隱藏檔案';

  @override
  String get favoriteToggle => '收藏';

  @override
  String ratedHearts(int rating) {
    return '已評 $rating / 3 心';
  }

  @override
  String get confirmBiometricEnable => '確認以啟用生物認證解鎖';

  @override
  String get confirmResetPattern => '確認身分以重設 Privi 圖案';

  @override
  String get wrongPattern => '圖案錯誤';

  @override
  String get wrongPin => 'PIN 錯誤';

  @override
  String get noSystemLock => '請先在 Android 設定中啟用螢幕鎖定';

  @override
  String get systemAuthCancelled => '系統驗證已取消';

  @override
  String get scanFailedShort => '掃描失敗';

  @override
  String get screenshotSettingFailed => '無法更新截圖保護';

  @override
  String get noOrphanVaultFiles => '未找到保險庫檔案';

  @override
  String recoveryResult(int recovered, int skipped, int failed) {
    return '已恢復 $recovered · 略過 $skipped · 失敗 $failed';
  }

  @override
  String galleryRecoveryResult(int restored, int skipped, int failed) {
    return '已還原 $restored · 略過 $skipped · 失敗 $failed';
  }

  @override
  String get noVaultMediaToRepair => '沒有需要修復的媒體';

  @override
  String captureDateRepairResult(int fixed, int skipped, int failed) {
    return '已修復 $fixed · 略過 $skipped · 失敗 $failed';
  }

  @override
  String unlockLockout(int seconds) {
    return '請在 $seconds 秒後重試';
  }
}
