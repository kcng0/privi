import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/domain/enums.dart';

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
}
