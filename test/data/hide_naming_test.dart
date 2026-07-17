import 'package:flutter_test/flutter_test.dart';
import 'package:privi/core/constants.dart';
import 'package:privi/data/services/hide_naming.dart';

void main() {
  group('HideNaming', () {
    test('legacy video marker pattern', () {
      expect(
        HideNaming.toLegacyHiddenPath('/sdcard/DCIM/clip.mp4', isVideo: true),
        '/sdcard/DCIM/clip.vid.pg.mp4',
      );
    });

    test('legacy image marker pattern', () {
      expect(
        HideNaming.toLegacyHiddenPath('/sdcard/Pictures/a.jpg', isVideo: false),
        '/sdcard/Pictures/a.img.pg.jpg',
      );
    });

    test('legacy reveal reverses rename', () {
      expect(
        HideNaming.fromLegacyHiddenPath('/sdcard/DCIM/clip.vid.pg.mp4'),
        '/sdcard/DCIM/clip.mp4',
      );
    });

    test('hidden vault path detection', () {
      const p =
          '/storage/emulated/0/${VaultPaths.hiddenRootName}/Downloads/ab_photo.jpg';
      expect(HideNaming.isHiddenVaultPath(p), isTrue);
      expect(HideNaming.isHiddenPath(p), isTrue);
    });

    test('displayName strips legacy marker', () {
      expect(HideNaming.displayName('clip.vid.pg.mp4'), 'clip.mp4');
    });

    test('sanitize folder', () {
      expect(HideNaming.sanitizeFolder('download'), 'Downloads');
      expect(HideNaming.sanitizeFolder('Camera'), 'Camera');
    });

    test('vaultMirrorFolder extracts segment', () {
      const p =
          '/storage/emulated/0/${VaultPaths.hiddenRootName}/Downloads/ab_photo.jpg';
      expect(HideNaming.vaultMirrorFolder(p), 'Downloads');
    });
  });

  group('HideNaming.resolveUnhidePath', () {
    const vaultDownloads =
        '/storage/emulated/0/${VaultPaths.hiddenRootName}/Downloads/ab_photo.jpg';
    const vaultCamera =
        '/storage/emulated/0/${VaultPaths.hiddenRootName}/Camera/img.jpg';
    const vaultImported =
        '/storage/emulated/0/${VaultPaths.hiddenRootName}/Imported/x.png';
    const legacy = '/storage/emulated/0/DCIM/Camera/clip.vid.pg.mp4';

    test('originalPath wins when present', () {
      expect(
        HideNaming.resolveUnhidePath(
          privatePath: vaultDownloads,
          originalPath: '/storage/emulated/0/Pictures/mine.jpg',
          originalName: 'ab_photo.jpg',
        ),
        '/storage/emulated/0/Pictures/mine.jpg',
      );
    });

    test('empty originalPath ignored in favor of vault/legacy', () {
      expect(
        HideNaming.resolveUnhidePath(
          privatePath: vaultDownloads,
          originalPath: '   ',
          originalName: 'ab_photo.jpg',
        ),
        '/storage/emulated/0/Download/ab_photo.jpg',
      );
    });

    test('legacy reverse when no originalPath', () {
      expect(
        HideNaming.resolveUnhidePath(
          privatePath: legacy,
          originalPath: null,
          originalName: 'clip.mp4',
        ),
        '/storage/emulated/0/DCIM/Camera/clip.mp4',
      );
    });

    test('vault + Downloads maps to public Download', () {
      expect(
        HideNaming.resolveUnhidePath(
          privatePath: vaultDownloads,
          originalPath: null,
          originalName: 'ab_photo.jpg',
        ),
        '/storage/emulated/0/Download/ab_photo.jpg',
      );
    });

    test('vault + Camera maps to DCIM/Camera', () {
      expect(
        HideNaming.resolveUnhidePath(
          privatePath: vaultCamera,
          originalPath: null,
          originalName: 'img.jpg',
        ),
        '/storage/emulated/0/DCIM/Camera/img.jpg',
      );
    });

    test('vault + Imported falls back to Download', () {
      expect(
        HideNaming.resolveUnhidePath(
          privatePath: vaultImported,
          originalPath: null,
          originalName: 'x.png',
        ),
        '/storage/emulated/0/Download/x.png',
      );
    });

    test('missing original and non-vault non-legacy → Download fallback', () {
      expect(
        HideNaming.resolveUnhidePath(
          privatePath: '/data/user/0/app/cache/tmp.bin',
          originalPath: null,
          originalName: 'tmp.bin',
        ),
        '/storage/emulated/0/Download/tmp.bin',
      );
    });
  });
}
