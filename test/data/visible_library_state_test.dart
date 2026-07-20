import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:privi/application/platform/visible_library.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/domain/enums.dart';

final class _FakeVisibleLibrary implements VisibleLibrary {
  const _FakeVisibleLibrary({
    required this.capabilities,
    required List<AssetPathEntity> paths,
    required Map<String, List<AssetEntity>> assetsByPath,
  })  : _paths = paths,
        _assetsByPath = assetsByPath;

  @override
  final VisibleLibraryCapabilities capabilities;

  final List<AssetPathEntity> _paths;
  final Map<String, List<AssetEntity>> _assetsByPath;

  @override
  Future<int> assetCount(AssetPathEntity path) async =>
      _assetsByPath[path.id]?.length ?? 0;

  @override
  Future<List<AssetEntity>> assetPage(
    AssetPathEntity path, {
    required int page,
    required int size,
  }) async {
    final assets = _assetsByPath[path.id] ?? const <AssetEntity>[];
    final start = page * size;
    if (start >= assets.length) return const [];
    final end = start + size < assets.length ? start + size : assets.length;
    return assets.sublist(start, end);
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<AssetPathEntity>> paths(MediaKindFilter filter) async => _paths;

  @override
  Future<PermissionState> permissionState() async => PermissionState.authorized;

  @override
  Future<PermissionState> requestPermission() async =>
      PermissionState.authorized;

  @override
  Future<ImportSource?> resolveForHide(
    String assetId, {
    String? sourceFolderName,
  }) async =>
      null;
}

AssetEntity _asset(String id, AssetType type) => AssetEntity(
      id: id,
      typeInt: type.index,
      width: 1,
      height: 1,
      title: '$id.jpg',
    );

void main() {
  late VisibleLibraryState state;

  setUp(() {
    state = VisibleLibraryState();
  });

  tearDown(() async {
    state.dispose();
  });

  test('exclusion matches original relative path, not basename alone', () {
    state.hydrateOriginalPaths([
      '/storage/emulated/0/DCIM/Camera/same.jpg',
    ]);

    expect(
      state.isExcludedKey(
        assetId: 'camera-id',
        relativePath: 'DCIM/Camera/',
        title: 'same.jpg',
      ),
      isTrue,
    );
    expect(
      state.isExcludedKey(
        assetId: 'download-id',
        relativePath: 'Download/',
        title: 'same.jpg',
      ),
      isFalse,
    );
  });

  test('session asset id has priority over path matching', () {
    state.apply(
      const VisibleHidden(
        pathId: 'camera',
        hiddenCount: 1,
        assetIds: ['hidden-id'],
      ),
    );

    expect(
      state.isExcludedKey(
        assetId: 'hidden-id',
        relativePath: 'Elsewhere/',
        title: 'other.jpg',
      ),
      isTrue,
    );
  });

  test('optimistic count is replaced by reconciled count', () {
    state.setFolders(
      MediaKindFilter.image,
      const [GalleryFolder(id: 'camera', name: 'Camera', count: 5)],
    );
    state.apply(
      const VisibleHidden(pathId: 'camera', hiddenCount: 2),
    );

    expect(state.snapshot(MediaKindFilter.image).folders.single.count, 3);

    state.reconcileCount('camera', 4);
    expect(state.snapshot(MediaKindFilter.image).folders.single.count, 4);
  });

  test('reveal clears session exclusions and cached snapshot', () {
    state.setFolders(
      MediaKindFilter.image,
      const [GalleryFolder(id: 'camera', name: 'Camera', count: 2)],
    );
    state.apply(
      const VisibleHidden(
        pathId: 'camera',
        hiddenCount: 1,
        assetIds: ['hidden-id'],
      ),
    );

    state.apply(const VisibleRevealed());

    expect(state.snapshot(MediaKindFilter.image).folders, isEmpty);
    expect(
      state.isExcludedKey(
        assetId: 'hidden-id',
        relativePath: 'DCIM/Camera/',
        title: 'same.jpg',
      ),
      isFalse,
    );
  });

  test('snapshot remains immutable after later mutations', () {
    state.setFolders(
      MediaKindFilter.image,
      const [GalleryFolder(id: 'camera', name: 'Camera', count: 1)],
    );
    state.apply(
      const VisibleHidden(
        pathId: 'camera',
        hiddenCount: 1,
        assetIds: ['hidden-id'],
      ),
    );
    final snapshot = state.snapshot(MediaKindFilter.image);
    final asset = AssetEntity(
      id: 'hidden-id',
      typeInt: AssetType.image.index,
      width: 1,
      height: 1,
      title: 'hidden.jpg',
      relativePath: 'DCIM/Camera/',
    );

    state.apply(const VisibleRevealed());

    expect(snapshot.isExcluded(asset), isTrue);
    expect(
      () => snapshot.folders.add(
        const GalleryFolder(id: 'other', name: 'Other', count: 1),
      ),
      throwsUnsupportedError,
    );
  });

  test('iOS retains All while Android keeps virtual collections excluded',
      () async {
    final all = AssetPathEntity(id: 'all', name: 'Recent', isAll: true);
    final assets = {
      'all': [_asset('image-1', AssetType.image)],
    };
    final ios = GalleryService(
      library: _FakeVisibleLibrary(
        capabilities: const VisibleLibraryCapabilities(
          filtersAssetTypesInDart: true,
          includesAllCollection: true,
          showsLimitedAccessNotice: true,
        ),
        paths: [all],
        assetsByPath: assets,
      ),
    );
    final android = GalleryService(
      library: _FakeVisibleLibrary(
        capabilities: const VisibleLibraryCapabilities(
          filtersAssetTypesInDart: false,
          includesAllCollection: false,
          showsLimitedAccessNotice: false,
        ),
        paths: [all],
        assetsByPath: assets,
      ),
    );
    addTearDown(ios.dispose);
    addTearDown(android.dispose);

    final iosFolders = await ios.listFolders(MediaKindFilter.image);
    final androidFolders = await android.listFolders(MediaKindFilter.image);

    expect(iosFolders, hasLength(1));
    expect(iosFolders.single.isAll, isTrue);
    expect(androidFolders, isEmpty);
  });

  test('mixed iOS results paginate after media-kind filtering', () async {
    final path = AssetPathEntity(id: 'photos', name: 'Photos');
    final library = _FakeVisibleLibrary(
      capabilities: const VisibleLibraryCapabilities(
        filtersAssetTypesInDart: true,
        includesAllCollection: true,
        showsLimitedAccessNotice: true,
      ),
      paths: [path],
      assetsByPath: {
        'photos': [
          _asset('image-0', AssetType.image),
          _asset('video-0', AssetType.video),
          _asset('image-1', AssetType.image),
          _asset('video-1', AssetType.video),
          _asset('image-2', AssetType.image),
          _asset('video-2', AssetType.video),
          _asset('image-3', AssetType.image),
        ],
      },
    );
    final gallery = GalleryService(library: library);
    addTearDown(gallery.dispose);

    final first = await gallery.listAssets(
      pathId: path.id,
      filter: MediaKindFilter.image,
      page: 0,
      size: 2,
    );
    final second = await gallery.listAssets(
      pathId: path.id,
      filter: MediaKindFilter.image,
      page: 1,
      size: 2,
    );

    expect(first.map((asset) => asset.id), ['image-0', 'image-1']);
    expect(second.map((asset) => asset.id), ['image-2', 'image-3']);
  });
}
