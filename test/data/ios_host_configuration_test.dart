import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privi/data/services/ios_external_url_launcher.dart';
import 'package:privi/data/services/platform/ios_privacy_shield_adapter.dart';
import 'package:xml/xml.dart';

const _receiveSharingVersion = '1.9.0';
const _appGroup = 'group.com.privi.app';
const _runnerBundleId = 'com.privi.app';
const _extensionBundleId = 'com.privi.app.ShareExtension';

void main() {
  test('iOS host configuration keeps targets, package, and channels aligned',
      () {
    final runnerInfo = _plist('ios/Runner/Info.plist');
    final extensionInfo = _plist('ios/ShareExtension/Info.plist');
    final runnerEntitlements = _plist('ios/Runner/Runner.entitlements');
    final extensionEntitlements =
        _plist('ios/ShareExtension/ShareExtension.entitlements');
    final project = _read('ios/Runner.xcodeproj/project.pbxproj');
    final appDelegate = _read('ios/Runner/AppDelegate.swift');
    final pubspec = _read('pubspec.yaml');

    expect(_string(runnerInfo, 'AppGroupId'), r'$(CUSTOM_GROUP_ID)');
    expect(_string(extensionInfo, 'AppGroupId'), r'$(CUSTOM_GROUP_ID)');
    expect(
      _string(runnerInfo, 'NSPhotoLibraryUsageDescription'),
      isNotEmpty,
    );
    expect(
      _string(runnerInfo, 'NSPhotoLibraryAddUsageDescription'),
      isNotEmpty,
    );
    expect(_string(runnerInfo, 'NSFaceIDUsageDescription'), isNotEmpty);
    expect(
      _stringsDeep(runnerInfo, 'CFBundleURLSchemes'),
      contains('ShareMedia-\$(PRODUCT_BUNDLE_IDENTIFIER)'),
    );
    expect(
      _stringDeep(runnerInfo, 'UISceneDelegateClassName'),
      r'$(PRODUCT_MODULE_NAME).SceneDelegate',
    );

    expect(
      _stringDeep(extensionInfo, 'NSExtensionPointIdentifier'),
      'com.apple.share-services',
    );
    expect(
      _stringDeep(extensionInfo, 'NSExtensionPrincipalClass'),
      r'$(PRODUCT_MODULE_NAME).ShareViewController',
    );
    expect(
      _stringsDeep(extensionInfo, 'PHSupportedMediaTypes'),
      containsAll(<String>['Image', 'Video']),
    );

    expect(
      _strings(runnerEntitlements, 'com.apple.security.application-groups'),
      [_appGroup],
    );
    expect(
      _strings(
        extensionEntitlements,
        'com.apple.security.application-groups',
      ),
      [_appGroup],
    );

    expect(project, contains('SceneDelegate.swift in Sources'));
    expect(project, contains('PrivacyShieldCoordinator.swift in Sources'));
    expect(project, contains('ShareViewController.swift in Sources'));
    expect(
      project,
      contains('productType = "com.apple.product-type.app-extension"'),
    );
    expect(
      project,
      contains('target = C00700000000000000000001 /* ShareExtension */'),
    );
    expect(
      project,
      contains(
        'relativePath = '
        'Flutter/ephemeral/Packages/.packages/receive_sharing_intent-'
        '$_receiveSharingVersion;',
      ),
    );
    expect(project, contains('productName = "receive-sharing-intent";'));
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = $_runnerBundleId;'));
    expect(
      project,
      contains('PRODUCT_BUNDLE_IDENTIFIER = $_extensionBundleId;'),
    );
    expect(project, contains('CUSTOM_GROUP_ID = $_appGroup;'));
    expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;'));
    expect(
      pubspec,
      contains('receive_sharing_intent: $_receiveSharingVersion'),
    );
    final nativeTargets = _section(project, 'PBXNativeTarget');
    expect(
      nativeTargets
          .indexOf('C00300000000000000000001 /* Embed App Extensions */'),
      lessThan(
        nativeTargets.indexOf('3B06AD1E1E4923F5004D2608 /* Thin Binary */'),
      ),
    );

    expect(appDelegate, contains(IosPrivacyShieldAdapter.channelName));
    expect(appDelegate, contains(IosExternalUrlLauncher.channelName));
    expect(appDelegate, contains('setAppSwitcherShield'));
    expect(appDelegate, contains('openUrl'));
  });
}

XmlElement _plist(String relativePath) =>
    XmlDocument.parse(_read(relativePath)).rootElement.getElement('dict')!;

String _read(String relativePath) =>
    File(p.join(Directory.current.path, relativePath)).readAsStringSync();

String _string(XmlElement parent, String key) {
  final value = _value(parent, key);
  if (value?.name.local != 'string') {
    throw StateError('Expected plist string for $key');
  }
  return value!.innerText;
}

String _stringDeep(XmlElement parent, String key) {
  final value = _valueDeep(parent, key);
  if (value.name.local != 'string') {
    throw StateError('Expected plist string for $key');
  }
  return value.innerText;
}

List<String> _strings(XmlElement parent, String key) {
  final value = _value(parent, key);
  if (value?.name.local != 'array') {
    throw StateError('Expected plist array for $key');
  }
  return [
    for (final child in value!.childElements)
      if (child.name.local == 'string') child.innerText,
  ];
}

List<String> _stringsDeep(XmlElement parent, String key) {
  final value = _valueDeep(parent, key);
  if (value.name.local != 'array') {
    throw StateError('Expected plist array for $key');
  }
  return [
    for (final child in value.childElements)
      if (child.name.local == 'string') child.innerText,
  ];
}

XmlElement _valueDeep(XmlElement parent, String key) {
  for (final dictionary in <XmlElement>[
    parent,
    ...parent.findAllElements('dict'),
  ]) {
    final value = _tryValue(dictionary, key);
    if (value != null) return value;
  }
  throw StateError('Missing plist key $key');
}

XmlElement? _value(XmlElement parent, String key) {
  final value = _tryValue(parent, key);
  if (value != null) return value;
  throw StateError('Missing plist key $key');
}

XmlElement? _tryValue(XmlElement parent, String key) {
  final children = parent.childElements.toList(growable: false);
  for (var index = 0; index + 1 < children.length; index++) {
    final current = children[index];
    if (current.name.local == 'key' && current.innerText == key) {
      return children[index + 1];
    }
  }
  return null;
}

String _section(String project, String name) {
  final start = project.indexOf('/* Begin $name section */');
  final end = project.indexOf('/* End $name section */');
  if (start < 0 || end <= start) {
    throw StateError('Missing Xcode project section $name');
  }
  return project.substring(start, end);
}
