import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'HK')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Privi'**
  String get appName;

  /// No description provided for @visible.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get visible;

  /// No description provided for @invisible.
  ///
  /// In en, this message translates to:
  /// **'Invisible'**
  String get invisible;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchNameHint.
  ///
  /// In en, this message translates to:
  /// **'Search name…'**
  String get searchNameHint;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @multiSort.
  ///
  /// In en, this message translates to:
  /// **'Multi-sort'**
  String get multiSort;

  /// No description provided for @style.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get style;

  /// No description provided for @layoutStyle.
  ///
  /// In en, this message translates to:
  /// **'Layout style'**
  String get layoutStyle;

  /// No description provided for @columnsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} columns'**
  String columnsCount(int count);

  /// No description provided for @multiSelectItems.
  ///
  /// In en, this message translates to:
  /// **'Multi-select items'**
  String get multiSelectItems;

  /// No description provided for @photosOnly.
  ///
  /// In en, this message translates to:
  /// **'Photos only'**
  String get photosOnly;

  /// No description provided for @videosOnly.
  ///
  /// In en, this message translates to:
  /// **'Videos only'**
  String get videosOnly;

  /// No description provided for @photosOnlyTapVideos.
  ///
  /// In en, this message translates to:
  /// **'Photos only · tap for videos'**
  String get photosOnlyTapVideos;

  /// No description provided for @videosOnlyTapPhotos.
  ///
  /// In en, this message translates to:
  /// **'Videos only · tap for photos'**
  String get videosOnlyTapPhotos;

  /// No description provided for @newAlbum.
  ///
  /// In en, this message translates to:
  /// **'New album'**
  String get newAlbum;

  /// No description provided for @newVaultAlbum.
  ///
  /// In en, this message translates to:
  /// **'New vault album'**
  String get newVaultAlbum;

  /// No description provided for @albumNameHint.
  ///
  /// In en, this message translates to:
  /// **'Album name'**
  String get albumNameHint;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renameAlbum.
  ///
  /// In en, this message translates to:
  /// **'Rename album'**
  String get renameAlbum;

  /// No description provided for @deleteAlbum.
  ///
  /// In en, this message translates to:
  /// **'Delete album'**
  String get deleteAlbum;

  /// No description provided for @deleteAlbumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Media stays in All Media'**
  String get deleteAlbumSubtitle;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restoreAlbumTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore album?'**
  String get restoreAlbumTitle;

  /// No description provided for @restoreAlbumBody.
  ///
  /// In en, this message translates to:
  /// **'Unhide {count} item(s) from “{name}” back to the system gallery.'**
  String restoreAlbumBody(int count, String name);

  /// No description provided for @unhideAllInAlbum.
  ///
  /// In en, this message translates to:
  /// **'Unhide all items in this album'**
  String get unhideAllInAlbum;

  /// No description provided for @pinToTop.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get pinToTop;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @pinnedToTop.
  ///
  /// In en, this message translates to:
  /// **'Pinned to top'**
  String get pinnedToTop;

  /// No description provided for @unpinned.
  ///
  /// In en, this message translates to:
  /// **'Unpinned'**
  String get unpinned;

  /// No description provided for @noMediaToPlay.
  ///
  /// In en, this message translates to:
  /// **'No media to play'**
  String get noMediaToPlay;

  /// No description provided for @nothingToRestore.
  ///
  /// In en, this message translates to:
  /// **'Nothing to restore'**
  String get nothingToRestore;

  /// No description provided for @restoredItems.
  ///
  /// In en, this message translates to:
  /// **'Restored {count} item(s)'**
  String restoredItems(int count);

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemsCount(int count);

  /// No description provided for @errorWithDetails.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithDetails(String error);

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @hiding.
  ///
  /// In en, this message translates to:
  /// **'Hiding…'**
  String get hiding;

  /// No description provided for @resolvingMedia.
  ///
  /// In en, this message translates to:
  /// **'Preparing media…'**
  String get resolvingMedia;

  /// No description provided for @unhiding.
  ///
  /// In en, this message translates to:
  /// **'Unhiding…'**
  String get unhiding;

  /// No description provided for @hidingParallel.
  ///
  /// In en, this message translates to:
  /// **'Hiding (×{workers})…'**
  String hidingParallel(int workers);

  /// No description provided for @hideFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide folder?'**
  String get hideFolderTitle;

  /// No description provided for @hideFolderBody.
  ///
  /// In en, this message translates to:
  /// **'Hide media in “{name}” from the system gallery ({count} item(s)).'**
  String hideFolderBody(String name, int count);

  /// No description provided for @moveFolderToVault.
  ///
  /// In en, this message translates to:
  /// **'Move this folder into the vault'**
  String get moveFolderToVault;

  /// No description provided for @permissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get permissionNeeded;

  /// No description provided for @permissionNeededBody.
  ///
  /// In en, this message translates to:
  /// **'Privi needs permission to hide photos and videos from your gallery. Open Settings to allow it, then try again.'**
  String get permissionNeededBody;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @openSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get openSystemSettings;

  /// No description provided for @grantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant permission'**
  String get grantPermission;

  /// No description provided for @allowGalleryAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow gallery access'**
  String get allowGalleryAccess;

  /// No description provided for @allowGalleryAccessBody.
  ///
  /// In en, this message translates to:
  /// **'Visible lists your photo or video folders. Grant permission to browse and hide them.'**
  String get allowGalleryAccessBody;

  /// No description provided for @noPhotoFolders.
  ///
  /// In en, this message translates to:
  /// **'No photo folders found'**
  String get noPhotoFolders;

  /// No description provided for @noVideoFolders.
  ///
  /// In en, this message translates to:
  /// **'No video folders found'**
  String get noVideoFolders;

  /// No description provided for @couldNotLoadGallery.
  ///
  /// In en, this message translates to:
  /// **'Could not load gallery: {error}'**
  String couldNotLoadGallery(String error);

  /// No description provided for @noMediaToHide.
  ///
  /// In en, this message translates to:
  /// **'No media to hide'**
  String get noMediaToHide;

  /// No description provided for @couldNotOpenFilesToHide.
  ///
  /// In en, this message translates to:
  /// **'Could not open files to hide'**
  String get couldNotOpenFilesToHide;

  /// No description provided for @couldNotOpenPathsToRename.
  ///
  /// In en, this message translates to:
  /// **'Could not open file paths to rename.'**
  String get couldNotOpenPathsToRename;

  /// No description provided for @couldNotHideMedia.
  ///
  /// In en, this message translates to:
  /// **'Could not hide media. Please try again.'**
  String get couldNotHideMedia;

  /// No description provided for @nothingHidden.
  ///
  /// In en, this message translates to:
  /// **'Nothing hidden'**
  String get nothingHidden;

  /// No description provided for @hiddenToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Hidden → Invisible / {name}'**
  String hiddenToAlbum(String name);

  /// No description provided for @hiddenCountToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Hidden {count} → Invisible / {name}'**
  String hiddenCountToAlbum(int count, String name);

  /// No description provided for @hiddenSharedItems.
  ///
  /// In en, this message translates to:
  /// **'Hidden {count} shared items'**
  String hiddenSharedItems(int count);

  /// No description provided for @unlockToHideShared.
  ///
  /// In en, this message translates to:
  /// **'Unlock to hide shared media'**
  String get unlockToHideShared;

  /// No description provided for @unhide.
  ///
  /// In en, this message translates to:
  /// **'Unhide'**
  String get unhide;

  /// No description provided for @unhiddenItems.
  ///
  /// In en, this message translates to:
  /// **'Unhidden {count} item(s)'**
  String unhiddenItems(int count);

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteFromDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete from device?'**
  String get deleteFromDeviceTitle;

  /// No description provided for @deleteFromDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete {count} item(s) from the system gallery. This cannot be undone.'**
  String deleteFromDeviceBody(int count);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(String error);

  /// No description provided for @noItemsDeleted.
  ///
  /// In en, this message translates to:
  /// **'No items deleted'**
  String get noItemsDeleted;

  /// No description provided for @deletedItems.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} item(s)'**
  String deletedItems(int count);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatches;

  /// No description provided for @noPhotosInFolder.
  ///
  /// In en, this message translates to:
  /// **'No photos in this folder'**
  String get noPhotosInFolder;

  /// No description provided for @noVideosInFolder.
  ///
  /// In en, this message translates to:
  /// **'No videos in this folder'**
  String get noVideosInFolder;

  /// No description provided for @playPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Play playlist'**
  String get playPlaylist;

  /// No description provided for @playPlaylistShuffleOn.
  ///
  /// In en, this message translates to:
  /// **'Start with shuffle on?'**
  String get playPlaylistShuffleOn;

  /// No description provided for @playPlaylistShuffleOff.
  ///
  /// In en, this message translates to:
  /// **'Start with shuffle off? You can toggle in the player.'**
  String get playPlaylistShuffleOff;

  /// No description provided for @inOrder.
  ///
  /// In en, this message translates to:
  /// **'In order'**
  String get inOrder;

  /// No description provided for @noExternalPlayer.
  ///
  /// In en, this message translates to:
  /// **'No external player found — opening in-app'**
  String get noExternalPlayer;

  /// No description provided for @openedExternalPlayer.
  ///
  /// In en, this message translates to:
  /// **'Opened in external player'**
  String get openedExternalPlayer;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @moveToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Move to album'**
  String get moveToAlbum;

  /// No description provided for @moveToRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Move to Recycle Bin'**
  String get moveToRecycleBin;

  /// No description provided for @deleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get deleteForever;

  /// No description provided for @setAsCover.
  ///
  /// In en, this message translates to:
  /// **'Set as cover'**
  String get setAsCover;

  /// No description provided for @coverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Cover updated'**
  String get coverUpdated;

  /// No description provided for @unhideRestoreOriginal.
  ///
  /// In en, this message translates to:
  /// **'Unhide (restore original name)'**
  String get unhideRestoreOriginal;

  /// No description provided for @restoredCount.
  ///
  /// In en, this message translates to:
  /// **'Restored {count}'**
  String restoredCount(int count);

  /// No description provided for @movedToRecycleBinCount.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} to Recycle Bin'**
  String movedToRecycleBinCount(int count);

  /// No description provided for @deletedForeverCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} forever'**
  String deletedForeverCount(int count);

  /// No description provided for @movedToAlbumCount.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} to album'**
  String movedToAlbumCount(int count);

  /// No description provided for @createUserAlbumFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a user album first'**
  String get createUserAlbumFirst;

  /// No description provided for @createAnotherAlbumFirst.
  ///
  /// In en, this message translates to:
  /// **'Create another album first'**
  String get createAnotherAlbumFirst;

  /// No description provided for @noMediaYet.
  ///
  /// In en, this message translates to:
  /// **'No media yet'**
  String get noMediaYet;

  /// No description provided for @noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavoritesYet;

  /// No description provided for @recycleBinEmpty.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin is empty'**
  String get recycleBinEmpty;

  /// No description provided for @noFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press media and Rate with hearts.'**
  String get noFavoritesHint;

  /// No description provided for @recycleEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Soft-deleted items appear here.'**
  String get recycleEmptyHint;

  /// No description provided for @noMediaHint.
  ///
  /// In en, this message translates to:
  /// **'Hide media from the Visible tab.'**
  String get noMediaHint;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @allMedia.
  ///
  /// In en, this message translates to:
  /// **'All Media'**
  String get allMedia;

  /// No description provided for @recycleBin.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin'**
  String get recycleBin;

  /// No description provided for @hearts.
  ///
  /// In en, this message translates to:
  /// **'Hearts'**
  String get hearts;

  /// No description provided for @unrated.
  ///
  /// In en, this message translates to:
  /// **'Unrated'**
  String get unrated;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @emptyRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Empty Recycle Bin'**
  String get emptyRecycleBin;

  /// No description provided for @emptyRecycleBinTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty Recycle Bin?'**
  String get emptyRecycleBinTitle;

  /// No description provided for @emptyRecycleBinBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all soft-deleted items.'**
  String get emptyRecycleBinBody;

  /// No description provided for @purgedItems.
  ///
  /// In en, this message translates to:
  /// **'Purged {count} items'**
  String purgedItems(int count);

  /// No description provided for @sortNewestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get sortNewestFirst;

  /// No description provided for @sortOldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get sortOldestFirst;

  /// No description provided for @sortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get sortNameAsc;

  /// No description provided for @sortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get sortNameDesc;

  /// No description provided for @sortHighestRating.
  ///
  /// In en, this message translates to:
  /// **'Highest rating'**
  String get sortHighestRating;

  /// No description provided for @sortLowestRating.
  ///
  /// In en, this message translates to:
  /// **'Lowest rating'**
  String get sortLowestRating;

  /// No description provided for @sortsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sorts'**
  String sortsCount(int count);

  /// No description provided for @progressOkSkipFail.
  ///
  /// In en, this message translates to:
  /// **'ok {imported} · skip {skipped} · fail {failed}'**
  String progressOkSkipFail(int imported, int skipped, int failed);

  /// No description provided for @failedItems.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String failedItems(int count);

  /// No description provided for @drawPattern.
  ///
  /// In en, this message translates to:
  /// **'Draw a pattern'**
  String get drawPattern;

  /// No description provided for @confirmPattern.
  ///
  /// In en, this message translates to:
  /// **'Confirm pattern'**
  String get confirmPattern;

  /// No description provided for @redrawPattern.
  ///
  /// In en, this message translates to:
  /// **'Redraw pattern'**
  String get redrawPattern;

  /// No description provided for @drawYourPattern.
  ///
  /// In en, this message translates to:
  /// **'Draw your pattern'**
  String get drawYourPattern;

  /// No description provided for @enterYourPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get enterYourPin;

  /// No description provided for @connectAtLeast4Dots.
  ///
  /// In en, this message translates to:
  /// **'Connect at least 4 dots'**
  String get connectAtLeast4Dots;

  /// No description provided for @unlockWithBiometric.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometric'**
  String get unlockWithBiometric;

  /// No description provided for @forgotPattern.
  ///
  /// In en, this message translates to:
  /// **'Forgot pattern?'**
  String get forgotPattern;

  /// No description provided for @forgotPatternTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot pattern?'**
  String get forgotPatternTitle;

  /// No description provided for @forgotPatternBody.
  ///
  /// In en, this message translates to:
  /// **'Use your phone’s fingerprint, face, or screen lock to prove it is you. Then you can draw a new vault pattern.\n\nYour media stays on the device; only the vault unlock pattern is reset.'**
  String get forgotPatternBody;

  /// No description provided for @enableBiometricTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric unlock?'**
  String get enableBiometricTitle;

  /// No description provided for @enableBiometricBody.
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint or face for faster unlock. Your pattern remains the backup unlock.'**
  String get enableBiometricBody;

  /// No description provided for @biometricNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric not enabled — you can try again in Settings'**
  String get biometricNotEnabled;

  /// No description provided for @patternsDidNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Patterns did not match — try again'**
  String get patternsDidNotMatch;

  /// No description provided for @drawNewPatternProtect.
  ///
  /// In en, this message translates to:
  /// **'Draw a new pattern to protect the vault'**
  String get drawNewPatternProtect;

  /// No description provided for @sectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get sectionSecurity;

  /// No description provided for @sectionDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get sectionDisplay;

  /// No description provided for @sectionPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get sectionPlayback;

  /// No description provided for @sectionStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get sectionStorage;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @lockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get lockNow;

  /// No description provided for @changePattern.
  ///
  /// In en, this message translates to:
  /// **'Change pattern'**
  String get changePattern;

  /// No description provided for @rootUnlockCredential.
  ///
  /// In en, this message translates to:
  /// **'Root unlock credential'**
  String get rootUnlockCredential;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricUnlock;

  /// No description provided for @autoLock.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock'**
  String get autoLock;

  /// No description provided for @autoLockImmediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get autoLockImmediately;

  /// No description provided for @autoLockSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds'**
  String autoLockSeconds(int seconds);

  /// No description provided for @autoLockMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minute'**
  String autoLockMinutes(int minutes);

  /// No description provided for @autoLockMinutesPlural.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String autoLockMinutesPlural(int minutes);

  /// No description provided for @blockScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Block screenshots'**
  String get blockScreenshots;

  /// No description provided for @blockScreenshotsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'FLAG_SECURE — hide content in recents'**
  String get blockScreenshotsSubtitle;

  /// No description provided for @mediaGridColumns.
  ///
  /// In en, this message translates to:
  /// **'Default grid columns'**
  String get mediaGridColumns;

  /// No description provided for @albumColumns.
  ///
  /// In en, this message translates to:
  /// **'Album columns'**
  String get albumColumns;

  /// No description provided for @preferExternalPlayer.
  ///
  /// In en, this message translates to:
  /// **'Prefer external player'**
  String get preferExternalPlayer;

  /// No description provided for @shuffleByDefault.
  ///
  /// In en, this message translates to:
  /// **'Shuffle by default'**
  String get shuffleByDefault;

  /// No description provided for @slideshowDelay.
  ///
  /// In en, this message translates to:
  /// **'Slideshow delay'**
  String get slideshowDelay;

  /// No description provided for @recycleRetention.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin retention'**
  String get recycleRetention;

  /// No description provided for @vaultSize.
  ///
  /// In en, this message translates to:
  /// **'Vault size'**
  String get vaultSize;

  /// No description provided for @exportVault.
  ///
  /// In en, this message translates to:
  /// **'Export vault…'**
  String get exportVault;

  /// No description provided for @exportVaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Media + metadata to a folder'**
  String get exportVaultSubtitle;

  /// No description provided for @importVault.
  ///
  /// In en, this message translates to:
  /// **'Import vault…'**
  String get importVault;

  /// No description provided for @importVaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From a previous export folder'**
  String get importVaultSubtitle;

  /// No description provided for @scanOrphans.
  ///
  /// In en, this message translates to:
  /// **'Scan orphan hidden files'**
  String get scanOrphans;

  /// No description provided for @scanningOrphans.
  ///
  /// In en, this message translates to:
  /// **'Scanning for orphan hidden files…'**
  String get scanningOrphans;

  /// No description provided for @recoverVault.
  ///
  /// In en, this message translates to:
  /// **'Recover vault after reinstall'**
  String get recoverVault;

  /// No description provided for @recoverVaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-index media left in .privateheart_vault'**
  String get recoverVaultSubtitle;

  /// No description provided for @recoverVaultBody.
  ///
  /// In en, this message translates to:
  /// **'Scan the on-disk vault folder and bring missing items back into Invisible. Use this after reinstalling Privi when files are still on the phone.'**
  String get recoverVaultBody;

  /// No description provided for @recoverAndUnhide.
  ///
  /// In en, this message translates to:
  /// **'Recover & restore to Gallery'**
  String get recoverAndUnhide;

  /// No description provided for @recoverAndUnhideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-index vault files and unhide them'**
  String get recoverAndUnhideSubtitle;

  /// No description provided for @recoverAndUnhideBody.
  ///
  /// In en, this message translates to:
  /// **'Re-index files under the vault folder, then move them back to public folders (Downloads / original when known). Use after reinstall if you want media visible in Gallery again.'**
  String get recoverAndUnhideBody;

  /// No description provided for @recoveringVault.
  ///
  /// In en, this message translates to:
  /// **'Recovering vault files…'**
  String get recoveringVault;

  /// No description provided for @repairCaptureDates.
  ///
  /// In en, this message translates to:
  /// **'Repair capture dates'**
  String get repairCaptureDates;

  /// No description provided for @repairCaptureDatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fix vault sort order from original capture time (not hide time)'**
  String get repairCaptureDatesSubtitle;

  /// No description provided for @repairingCaptureDates.
  ///
  /// In en, this message translates to:
  /// **'Repairing capture dates…'**
  String get repairingCaptureDates;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @license.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get license;

  /// No description provided for @couldNotOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Could not open browser'**
  String get couldNotOpenBrowser;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @patchLabel.
  ///
  /// In en, this message translates to:
  /// **'Patch {number}'**
  String patchLabel(int number);

  /// No description provided for @checkUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check updates'**
  String get checkUpdates;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailableTitle;

  /// No description provided for @updateDownloadPrompt.
  ///
  /// In en, this message translates to:
  /// **'Download and restart now?'**
  String get updateDownloadPrompt;

  /// No description provided for @appReleasePrompt.
  ///
  /// In en, this message translates to:
  /// **'Privi {version} is available on GitHub.'**
  String appReleasePrompt(String version);

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @updateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateAction;

  /// No description provided for @viewRelease.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewRelease;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate;

  /// No description provided for @updateRestartFailed.
  ///
  /// In en, this message translates to:
  /// **'Restart failed. Reopen Privi.'**
  String get updateRestartFailed;

  /// No description provided for @updatesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Updates unavailable'**
  String get updatesUnavailable;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Check failed'**
  String get updateCheckFailed;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get updateDownloadFailed;

  /// No description provided for @authorLabel.
  ///
  /// In en, this message translates to:
  /// **'Author: {author}'**
  String authorLabel(String author);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {error}'**
  String scanFailed(String error);

  /// No description provided for @exportedMedia.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} media files + manifest'**
  String exportedMedia(int count);

  /// No description provided for @playing.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get playing;

  /// No description provided for @emptyPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Empty playlist'**
  String get emptyPlaylist;

  /// No description provided for @openExternal.
  ///
  /// In en, this message translates to:
  /// **'Open external'**
  String get openExternal;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @typeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get typeVideo;

  /// No description provided for @typeImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get typeImage;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @sizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sizeLabel;

  /// No description provided for @pathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get pathLabel;

  /// No description provided for @ratingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get ratingLabel;

  /// No description provided for @currentPattern.
  ///
  /// In en, this message translates to:
  /// **'Current pattern'**
  String get currentPattern;

  /// No description provided for @newPattern.
  ///
  /// In en, this message translates to:
  /// **'New pattern'**
  String get newPattern;

  /// No description provided for @confirmNewPattern.
  ///
  /// In en, this message translates to:
  /// **'Confirm new pattern'**
  String get confirmNewPattern;

  /// No description provided for @patternUpdated.
  ///
  /// In en, this message translates to:
  /// **'Pattern updated'**
  String get patternUpdated;

  /// No description provided for @newPatternsDidNotMatch.
  ///
  /// In en, this message translates to:
  /// **'New patterns did not match'**
  String get newPatternsDidNotMatch;

  /// No description provided for @drawCurrentPattern.
  ///
  /// In en, this message translates to:
  /// **'Draw your current pattern to continue'**
  String get drawCurrentPattern;

  /// No description provided for @drawSamePatternAgain.
  ///
  /// In en, this message translates to:
  /// **'Draw the same pattern again'**
  String get drawSamePatternAgain;

  /// No description provided for @currentPin.
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get currentPin;

  /// No description provided for @enterPinThenPattern.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN, then set a new pattern'**
  String get enterPinThenPattern;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pin;

  /// No description provided for @retention.
  ///
  /// In en, this message translates to:
  /// **'Retention'**
  String get retention;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageZhCn.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageZhCn;

  /// No description provided for @languageZhHk.
  ///
  /// In en, this message translates to:
  /// **'繁體中文（香港）'**
  String get languageZhHk;

  /// No description provided for @verifyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify identity'**
  String get verifyIdentity;

  /// No description provided for @unlockPrivi.
  ///
  /// In en, this message translates to:
  /// **'Unlock Privi'**
  String get unlockPrivi;

  /// No description provided for @biometricAvailable.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint / face when available'**
  String get biometricAvailable;

  /// No description provided for @biometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available on this device'**
  String get biometricUnavailable;

  /// No description provided for @biometricCancelled.
  ///
  /// In en, this message translates to:
  /// **'Biometric not enabled (cancelled or failed)'**
  String get biometricCancelled;

  /// No description provided for @biometricUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update biometric setting'**
  String get biometricUpdateFailed;

  /// No description provided for @externalPlayerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hand off videos to VLC / system player'**
  String get externalPlayerSubtitle;

  /// No description provided for @scanOrphansSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find vault files missing from the library'**
  String get scanOrphansSubtitle;

  /// No description provided for @retentionDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String retentionDays(int days);

  /// No description provided for @retention1Day.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get retention1Day;

  /// No description provided for @secondsCount.
  ///
  /// In en, this message translates to:
  /// **'{n} seconds'**
  String secondsCount(int n);

  /// No description provided for @secondCount.
  ///
  /// In en, this message translates to:
  /// **'{n} second'**
  String secondCount(int n);

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get empty;

  /// No description provided for @couldNotOpenExternally.
  ///
  /// In en, this message translates to:
  /// **'Could not open externally — preview in-app'**
  String get couldNotOpenExternally;

  /// No description provided for @openWith.
  ///
  /// In en, this message translates to:
  /// **'Open with'**
  String get openWith;

  /// No description provided for @playVideoWith.
  ///
  /// In en, this message translates to:
  /// **'Play video with'**
  String get playVideoWith;

  /// No description provided for @calculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get calculating;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @restoredToGallery.
  ///
  /// In en, this message translates to:
  /// **'Restored to Gallery'**
  String get restoredToGallery;

  /// No description provided for @couldNotUnhideFile.
  ///
  /// In en, this message translates to:
  /// **'Could not unhide file'**
  String get couldNotUnhideFile;

  /// No description provided for @favoriteToggle.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteToggle;

  /// No description provided for @ratedHearts.
  ///
  /// In en, this message translates to:
  /// **'Rated {rating} of 3 hearts'**
  String ratedHearts(int rating);

  /// No description provided for @confirmBiometricEnable.
  ///
  /// In en, this message translates to:
  /// **'Confirm to enable biometric unlock'**
  String get confirmBiometricEnable;

  /// No description provided for @confirmResetPattern.
  ///
  /// In en, this message translates to:
  /// **'Confirm it is you to reset Privi pattern'**
  String get confirmResetPattern;

  /// No description provided for @wrongPattern.
  ///
  /// In en, this message translates to:
  /// **'Wrong pattern'**
  String get wrongPattern;

  /// No description provided for @wrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN'**
  String get wrongPin;

  /// No description provided for @noSystemLock.
  ///
  /// In en, this message translates to:
  /// **'Set up a screen lock in Android Settings first'**
  String get noSystemLock;

  /// No description provided for @systemAuthCancelled.
  ///
  /// In en, this message translates to:
  /// **'System authentication cancelled'**
  String get systemAuthCancelled;

  /// No description provided for @scanFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Scan failed'**
  String get scanFailedShort;

  /// No description provided for @screenshotSettingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update screenshot protection'**
  String get screenshotSettingFailed;

  /// No description provided for @noOrphanVaultFiles.
  ///
  /// In en, this message translates to:
  /// **'No vault files found'**
  String get noOrphanVaultFiles;

  /// No description provided for @recoveryResult.
  ///
  /// In en, this message translates to:
  /// **'Recovered {recovered} · skipped {skipped} · failed {failed}'**
  String recoveryResult(int recovered, int skipped, int failed);

  /// No description provided for @galleryRecoveryResult.
  ///
  /// In en, this message translates to:
  /// **'Restored {restored} · skipped {skipped} · failed {failed}'**
  String galleryRecoveryResult(int restored, int skipped, int failed);

  /// No description provided for @noVaultMediaToRepair.
  ///
  /// In en, this message translates to:
  /// **'No vault media to repair'**
  String get noVaultMediaToRepair;

  /// No description provided for @captureDateRepairResult.
  ///
  /// In en, this message translates to:
  /// **'Fixed {fixed} · skipped {skipped} · failed {failed}'**
  String captureDateRepairResult(int fixed, int skipped, int failed);

  /// No description provided for @unlockLockout.
  ///
  /// In en, this message translates to:
  /// **'Try again in {seconds}s'**
  String unlockLockout(int seconds);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'HK':
            return AppLocalizationsZhHk();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
