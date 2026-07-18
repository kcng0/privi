// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Privi';

  @override
  String get visible => 'Visible';

  @override
  String get invisible => 'Invisible';

  @override
  String get settings => 'Settings';

  @override
  String get more => 'More';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get continueAction => 'Continue';

  @override
  String get enable => 'Enable';

  @override
  String get notNow => 'Not now';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get done => 'Done';

  @override
  String get next => 'Next';

  @override
  String get clear => 'Clear';

  @override
  String get select => 'Select';

  @override
  String get selectAll => 'Select all';

  @override
  String get search => 'Search';

  @override
  String get searchNameHint => 'Search name…';

  @override
  String get closeSearch => 'Close search';

  @override
  String get sort => 'Sort';

  @override
  String get multiSort => 'Multi-sort';

  @override
  String get style => 'Style';

  @override
  String get layoutStyle => 'Layout style';

  @override
  String columnsCount(int count) {
    return '$count columns';
  }

  @override
  String get multiSelectItems => 'Multi-select items';

  @override
  String get photosOnly => 'Photos only';

  @override
  String get videosOnly => 'Videos only';

  @override
  String get photosOnlyTapVideos => 'Photos only · tap for videos';

  @override
  String get videosOnlyTapPhotos => 'Videos only · tap for photos';

  @override
  String get newAlbum => 'New album';

  @override
  String get newVaultAlbum => 'New vault album';

  @override
  String get albumNameHint => 'Album name';

  @override
  String get rename => 'Rename';

  @override
  String get renameAlbum => 'Rename album';

  @override
  String get deleteAlbum => 'Delete album';

  @override
  String get deleteAlbumSubtitle => 'Media stays in All Media';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get restore => 'Restore';

  @override
  String get restoreAlbumTitle => 'Restore album?';

  @override
  String restoreAlbumBody(int count, String name) {
    return 'Unhide $count item(s) from “$name” back to the system gallery.';
  }

  @override
  String get unhideAllInAlbum => 'Unhide all items in this album';

  @override
  String get pinToTop => 'Pin to top';

  @override
  String get unpin => 'Unpin';

  @override
  String get pinnedToTop => 'Pinned to top';

  @override
  String get unpinned => 'Unpinned';

  @override
  String get noMediaToPlay => 'No media to play';

  @override
  String get nothingToRestore => 'Nothing to restore';

  @override
  String restoredItems(int count) {
    return 'Restored $count item(s)';
  }

  @override
  String itemsCount(int count) {
    return '$count items';
  }

  @override
  String errorWithDetails(String error) {
    return 'Error: $error';
  }

  @override
  String get hide => 'Hide';

  @override
  String get hiding => 'Hiding…';

  @override
  String get resolvingMedia => 'Preparing media…';

  @override
  String get unhiding => 'Unhiding…';

  @override
  String hidingParallel(int workers) {
    return 'Hiding (×$workers)…';
  }

  @override
  String get hideFolderTitle => 'Hide folder?';

  @override
  String hideFolderBody(String name, int count) {
    return 'Hide media in “$name” from the system gallery ($count item(s)).';
  }

  @override
  String get moveFolderToVault => 'Move this folder into the vault';

  @override
  String get permissionNeeded => 'Permission needed';

  @override
  String get permissionNeededBody =>
      'Privi needs permission to hide photos and videos from your gallery. Open Settings to allow it, then try again.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get openSystemSettings => 'Open system settings';

  @override
  String get grantPermission => 'Grant permission';

  @override
  String get allowGalleryAccess => 'Allow gallery access';

  @override
  String get allowGalleryAccessBody =>
      'Visible lists your photo or video folders. Grant permission to browse and hide them.';

  @override
  String get noPhotoFolders => 'No photo folders found';

  @override
  String get noVideoFolders => 'No video folders found';

  @override
  String couldNotLoadGallery(String error) {
    return 'Could not load gallery: $error';
  }

  @override
  String get noMediaToHide => 'No media to hide';

  @override
  String get couldNotOpenFilesToHide => 'Could not open files to hide';

  @override
  String get couldNotOpenPathsToRename =>
      'Could not open file paths to rename.';

  @override
  String get couldNotHideMedia => 'Could not hide media. Please try again.';

  @override
  String get nothingHidden => 'Nothing hidden';

  @override
  String hiddenToAlbum(String name) {
    return 'Hidden → Invisible / $name';
  }

  @override
  String hiddenCountToAlbum(int count, String name) {
    return 'Hidden $count → Invisible / $name';
  }

  @override
  String hiddenSharedItems(int count) {
    return 'Hidden $count shared items';
  }

  @override
  String get unlockToHideShared => 'Unlock to hide shared media';

  @override
  String get unhide => 'Unhide';

  @override
  String unhiddenItems(int count) {
    return 'Unhidden $count item(s)';
  }

  @override
  String get share => 'Share';

  @override
  String get delete => 'Delete';

  @override
  String get deleteFromDeviceTitle => 'Delete from device?';

  @override
  String deleteFromDeviceBody(int count) {
    return 'Permanently delete $count item(s) from the system gallery. This cannot be undone.';
  }

  @override
  String deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get noItemsDeleted => 'No items deleted';

  @override
  String deletedItems(int count) {
    return 'Deleted $count item(s)';
  }

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get noMatches => 'No matches';

  @override
  String get noPhotosInFolder => 'No photos in this folder';

  @override
  String get noVideosInFolder => 'No videos in this folder';

  @override
  String get playPlaylist => 'Play playlist';

  @override
  String get playPlaylistShuffleOn => 'Start with shuffle on?';

  @override
  String get playPlaylistShuffleOff =>
      'Start with shuffle off? You can toggle in the player.';

  @override
  String get inOrder => 'In order';

  @override
  String get noExternalPlayer => 'No external player found — opening in-app';

  @override
  String get openedExternalPlayer => 'Opened in external player';

  @override
  String get rate => 'Rate';

  @override
  String get details => 'Details';

  @override
  String get moveToAlbum => 'Move to album';

  @override
  String get moveToRecycleBin => 'Move to Recycle Bin';

  @override
  String get deleteForever => 'Delete forever';

  @override
  String get setAsCover => 'Set as cover';

  @override
  String get coverUpdated => 'Cover updated';

  @override
  String get unhideRestoreOriginal => 'Unhide (restore original name)';

  @override
  String restoredCount(int count) {
    return 'Restored $count';
  }

  @override
  String movedToRecycleBinCount(int count) {
    return 'Moved $count to Recycle Bin';
  }

  @override
  String deletedForeverCount(int count) {
    return 'Deleted $count forever';
  }

  @override
  String movedToAlbumCount(int count) {
    return 'Moved $count to album';
  }

  @override
  String get createUserAlbumFirst => 'Create a user album first';

  @override
  String get createAnotherAlbumFirst => 'Create another album first';

  @override
  String get noMediaYet => 'No media yet';

  @override
  String get noFavoritesYet => 'No favorites yet';

  @override
  String get recycleBinEmpty => 'Recycle Bin is empty';

  @override
  String get noFavoritesHint => 'Long-press media and Rate with hearts.';

  @override
  String get recycleEmptyHint => 'Soft-deleted items appear here.';

  @override
  String get noMediaHint => 'Hide media from the Visible tab.';

  @override
  String get favorites => 'Favorites';

  @override
  String get allMedia => 'All Media';

  @override
  String get recycleBin => 'Recycle Bin';

  @override
  String get hearts => 'Hearts';

  @override
  String get unrated => 'Unrated';

  @override
  String get all => 'All';

  @override
  String get emptyRecycleBin => 'Empty Recycle Bin';

  @override
  String get emptyRecycleBinTitle => 'Empty Recycle Bin?';

  @override
  String get emptyRecycleBinBody =>
      'Permanently delete all soft-deleted items.';

  @override
  String purgedItems(int count) {
    return 'Purged $count items';
  }

  @override
  String get sortNewestFirst => 'Newest first';

  @override
  String get sortOldestFirst => 'Oldest first';

  @override
  String get sortNameAsc => 'Name A–Z';

  @override
  String get sortNameDesc => 'Name Z–A';

  @override
  String get sortHighestRating => 'Highest rating';

  @override
  String get sortLowestRating => 'Lowest rating';

  @override
  String sortsCount(int count) {
    return '$count sorts';
  }

  @override
  String progressOkSkipFail(int imported, int skipped, int failed) {
    return 'ok $imported · skip $skipped · fail $failed';
  }

  @override
  String failedItems(int count) {
    return '$count failed';
  }

  @override
  String get drawPattern => 'Draw a pattern';

  @override
  String get confirmPattern => 'Confirm pattern';

  @override
  String get redrawPattern => 'Redraw pattern';

  @override
  String get drawYourPattern => 'Draw your pattern';

  @override
  String get enterYourPin => 'Enter your PIN';

  @override
  String get connectAtLeast4Dots => 'Connect at least 4 dots';

  @override
  String get unlockWithBiometric => 'Unlock with biometric';

  @override
  String get forgotPattern => 'Forgot pattern?';

  @override
  String get forgotPatternTitle => 'Forgot pattern?';

  @override
  String get forgotPatternBody =>
      'Use your phone’s fingerprint, face, or screen lock to prove it is you. Then you can draw a new vault pattern.\n\nYour media stays on the device; only the vault unlock pattern is reset.';

  @override
  String get enableBiometricTitle => 'Enable biometric unlock?';

  @override
  String get enableBiometricBody =>
      'Use fingerprint or face for faster unlock. Your pattern remains the backup unlock.';

  @override
  String get biometricNotEnabled =>
      'Biometric not enabled — you can try again in Settings';

  @override
  String get patternsDidNotMatch => 'Patterns did not match — try again';

  @override
  String get drawNewPatternProtect => 'Draw a new pattern to protect the vault';

  @override
  String get sectionSecurity => 'Security';

  @override
  String get sectionDisplay => 'Display';

  @override
  String get sectionPlayback => 'Playback';

  @override
  String get sectionStorage => 'Storage';

  @override
  String get sectionAbout => 'About';

  @override
  String get lockNow => 'Lock now';

  @override
  String get changePattern => 'Change pattern';

  @override
  String get rootUnlockCredential => 'Root unlock credential';

  @override
  String get biometricUnlock => 'Biometric unlock';

  @override
  String get autoLock => 'Auto-lock';

  @override
  String get autoLockImmediately => 'Immediately';

  @override
  String autoLockSeconds(int seconds) {
    return '$seconds seconds';
  }

  @override
  String autoLockMinutes(int minutes) {
    return '$minutes minute';
  }

  @override
  String autoLockMinutesPlural(int minutes) {
    return '$minutes minutes';
  }

  @override
  String get blockScreenshots => 'Block screenshots';

  @override
  String get blockScreenshotsSubtitle =>
      'FLAG_SECURE — hide content in recents';

  @override
  String get mediaGridColumns => 'Default grid columns';

  @override
  String get albumColumns => 'Album columns';

  @override
  String get preferExternalPlayer => 'Prefer external player';

  @override
  String get shuffleByDefault => 'Shuffle by default';

  @override
  String get slideshowDelay => 'Slideshow delay';

  @override
  String get recycleRetention => 'Recycle Bin retention';

  @override
  String get vaultSize => 'Vault size';

  @override
  String get exportVault => 'Export vault…';

  @override
  String get exportVaultSubtitle => 'Media + metadata to a folder';

  @override
  String get importVault => 'Import vault…';

  @override
  String get importVaultSubtitle => 'From a previous export folder';

  @override
  String get scanOrphans => 'Scan orphan hidden files';

  @override
  String get scanningOrphans => 'Scanning for orphan hidden files…';

  @override
  String get recoverVault => 'Recover vault after reinstall';

  @override
  String get recoverVaultSubtitle =>
      'Re-index media left in .privateheart_vault';

  @override
  String get recoverVaultBody =>
      'Scan the on-disk vault folder and bring missing items back into Invisible. Use this after reinstalling Privi when files are still on the phone.';

  @override
  String get recoverAndUnhide => 'Recover & restore to Gallery';

  @override
  String get recoverAndUnhideSubtitle => 'Re-index vault files and unhide them';

  @override
  String get recoverAndUnhideBody =>
      'Re-index files under the vault folder, then move them back to public folders (Downloads / original when known). Use after reinstall if you want media visible in Gallery again.';

  @override
  String get recoveringVault => 'Recovering vault files…';

  @override
  String get repairCaptureDates => 'Repair capture dates';

  @override
  String get repairCaptureDatesSubtitle =>
      'Fix vault sort order from original capture time (not hide time)';

  @override
  String get repairingCaptureDates => 'Repairing capture dates…';

  @override
  String get author => 'Author';

  @override
  String get license => 'License';

  @override
  String get couldNotOpenBrowser => 'Could not open browser';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String patchLabel(int number) {
    return 'Patch $number';
  }

  @override
  String get checkUpdates => 'Check updates';

  @override
  String get updateAvailableTitle => 'Update available';

  @override
  String get updateDownloadPrompt => 'Download and restart now?';

  @override
  String appReleasePrompt(String version) {
    return 'Privi $version is available on GitHub.';
  }

  @override
  String get later => 'Later';

  @override
  String get updateAction => 'Update';

  @override
  String get viewRelease => 'View';

  @override
  String get upToDate => 'Up to date';

  @override
  String get updateRestartFailed => 'Restart failed. Reopen Privi.';

  @override
  String get updatesUnavailable => 'Updates unavailable';

  @override
  String get updateCheckFailed => 'Check failed';

  @override
  String get updateDownloadFailed => 'Update failed';

  @override
  String authorLabel(String author) {
    return 'Author: $author';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String scanFailed(String error) {
    return 'Scan failed: $error';
  }

  @override
  String exportedMedia(int count) {
    return 'Exported $count media files + manifest';
  }

  @override
  String get playing => 'Playing';

  @override
  String get emptyPlaylist => 'Empty playlist';

  @override
  String get openExternal => 'Open external';

  @override
  String get typeLabel => 'Type';

  @override
  String get typeVideo => 'Video';

  @override
  String get typeImage => 'Image';

  @override
  String get nameLabel => 'Name';

  @override
  String get sizeLabel => 'Size';

  @override
  String get pathLabel => 'Path';

  @override
  String get ratingLabel => 'Rating';

  @override
  String get currentPattern => 'Current pattern';

  @override
  String get newPattern => 'New pattern';

  @override
  String get confirmNewPattern => 'Confirm new pattern';

  @override
  String get patternUpdated => 'Pattern updated';

  @override
  String get newPatternsDidNotMatch => 'New patterns did not match';

  @override
  String get drawCurrentPattern => 'Draw your current pattern to continue';

  @override
  String get drawSamePatternAgain => 'Draw the same pattern again';

  @override
  String get currentPin => 'Current PIN';

  @override
  String get enterPinThenPattern => 'Enter PIN, then set a new pattern';

  @override
  String get pin => 'PIN';

  @override
  String get retention => 'Retention';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageZhCn => '简体中文';

  @override
  String get languageZhHk => '繁體中文（香港）';

  @override
  String get verifyIdentity => 'Verify identity';

  @override
  String get unlockPrivi => 'Unlock Privi';

  @override
  String get biometricAvailable => 'Fingerprint / face when available';

  @override
  String get biometricUnavailable => 'Not available on this device';

  @override
  String get biometricCancelled =>
      'Biometric not enabled (cancelled or failed)';

  @override
  String get biometricUpdateFailed => 'Could not update biometric setting';

  @override
  String get externalPlayerSubtitle => 'Hand off videos to VLC / system player';

  @override
  String get scanOrphansSubtitle => 'Find vault files missing from the library';

  @override
  String retentionDays(int days) {
    return '$days days';
  }

  @override
  String get retention1Day => '1 day';

  @override
  String secondsCount(int n) {
    return '$n seconds';
  }

  @override
  String secondCount(int n) {
    return '$n second';
  }

  @override
  String get empty => 'Empty';

  @override
  String get couldNotOpenExternally =>
      'Could not open externally — preview in-app';

  @override
  String get openWith => 'Open with';

  @override
  String get playVideoWith => 'Play video with';

  @override
  String get calculating => 'Calculating…';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get restoredToGallery => 'Restored to Gallery';

  @override
  String get couldNotUnhideFile => 'Could not unhide file';

  @override
  String get favoriteToggle => 'Favorite';

  @override
  String ratedHearts(int rating) {
    return 'Rated $rating of 3 hearts';
  }

  @override
  String get confirmBiometricEnable => 'Confirm to enable biometric unlock';

  @override
  String get confirmResetPattern => 'Confirm it is you to reset Privi pattern';

  @override
  String get wrongPattern => 'Wrong pattern';

  @override
  String get wrongPin => 'Wrong PIN';

  @override
  String get noSystemLock => 'Set up a screen lock in Android Settings first';

  @override
  String get systemAuthCancelled => 'System authentication cancelled';

  @override
  String get scanFailedShort => 'Scan failed';

  @override
  String get screenshotSettingFailed =>
      'Could not update screenshot protection';

  @override
  String get noOrphanVaultFiles => 'No vault files found';

  @override
  String recoveryResult(int recovered, int skipped, int failed) {
    return 'Recovered $recovered · skipped $skipped · failed $failed';
  }

  @override
  String galleryRecoveryResult(int restored, int skipped, int failed) {
    return 'Restored $restored · skipped $skipped · failed $failed';
  }

  @override
  String get noVaultMediaToRepair => 'No vault media to repair';

  @override
  String captureDateRepairResult(int fixed, int skipped, int failed) {
    return 'Fixed $fixed · skipped $skipped · failed $failed';
  }

  @override
  String unlockLockout(int seconds) {
    return 'Try again in ${seconds}s';
  }
}
