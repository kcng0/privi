import 'package:photo_manager/photo_manager.dart';

import '../../../application/platform/visible_library.dart';
import '../../../domain/enums.dart';
import '../import/asset_gateway.dart';
import '../import/import_models.dart';

/// PhotoKit adapter for Visible browsing and opaque hide references.
///
/// Materialization stays inside the iOS vault workflow so limited access and
/// iCloud-only resources remain typed outcomes rather than missing paths.
final class IosPhotosVisibleLibraryAdapter implements VisibleLibrary {
  const IosPhotosVisibleLibraryAdapter({required AssetGateway assets})
      : _assets = assets;

  final AssetGateway _assets;

  @override
  VisibleLibraryCapabilities get capabilities =>
      const VisibleLibraryCapabilities(
        filtersAssetTypesInDart: true,
        includesAllCollection: true,
        showsLimitedAccessNotice: true,
      );

  @override
  Future<PermissionState> requestPermission() =>
      PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          iosAccessLevel: IosAccessLevel.readWrite,
        ),
      );

  @override
  Future<PermissionState> permissionState() => PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(
          iosAccessLevel: IosAccessLevel.readWrite,
        ),
      );

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<List<AssetPathEntity>> paths(MediaKindFilter filter) {
    // Query both media kinds on iOS, then filter AssetEntity.type in Dart.
    // Limited Photos access does not guarantee Android-style type filtering.
    return PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      onlyAll: false,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        videoOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
  }

  @override
  Future<int> assetCount(AssetPathEntity path) => path.assetCountAsync;

  @override
  Future<List<AssetEntity>> assetPage(
    AssetPathEntity path, {
    required int page,
    required int size,
  }) {
    // Keep a mixed PhotoKit query so limited authorization has one consistent
    // source of truth; GalleryService applies the image/video filter while it
    // builds logical pages.
    return path.getAssetListPaged(page: page, size: size);
  }

  @override
  Future<ImportSource?> resolveForHide(
    String id, {
    String? sourceFolderName,
  }) async {
    final info = await _assets.info(id);
    if (info == null) return null;
    final createSeconds = await _assets.createDateSecond(id);
    return ImportSource(
      path: '',
      name: info.title,
      mimeType:
          info.mimeType ?? (info.isVideo ? 'video/quicktime' : 'image/jpeg'),
      assetId: id,
      sourceFolderName: sourceFolderName?.trim().isNotEmpty == true
          ? sourceFolderName!.trim()
          : 'Photos',
      dateTaken: createSeconds == null || createSeconds <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              createSeconds * 1000,
              isUtc: true,
            ),
    );
  }
}
