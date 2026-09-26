import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domain and protocol import neither Flutter nor other layers', () {
    final violations = <String>[];
    for (final layer in ['domain', 'protocol']) {
      final dir = Directory('lib/$layer');
      expect(dir.existsSync(), isTrue, reason: 'missing lib/$layer');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final uri in _importUris(entity.readAsStringSync())) {
          if (_forbidden(uri)) {
            violations.add('${entity.path} imports $uri');
          }
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('capture imports only domain and protocol', () {
    expect(
      _layerViolations('capture', const ['capture', 'domain', 'protocol']),
      isEmpty,
    );
  });

  test('ble imports only protocol', () {
    expect(_layerViolations('ble', const ['ble', 'protocol']), isEmpty);
  });

  test('storage imports only domain', () {
    expect(_storageViolations(), isEmpty);
  });

  test('sync imports only domain and storage', () {
    expect(
      _layerViolations('sync', const ['sync', 'domain', 'storage']),
      isEmpty,
    );
  });
}

List<String> _storageViolations() {
  final violations = <String>[];
  final dir = Directory('lib/storage');
  expect(dir.existsSync(), isTrue, reason: 'missing lib/storage');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final uri in _importUris(entity.readAsStringSync())) {
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:hive_ce/')) continue;
      if (!_staysInside(entity.path, uri, const ['storage', 'domain'])) {
        violations.add('${entity.path} imports $uri');
      }
    }
  }
  return violations;
}

List<String> _layerViolations(String layer, List<String> allowed) {
  final violations = <String>[];
  final dir = Directory('lib/$layer');
  expect(dir.existsSync(), isTrue, reason: 'missing lib/$layer');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final uri in _importUris(entity.readAsStringSync())) {
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:') ||
          !_staysInside(entity.path, uri, allowed)) {
        violations.add('${entity.path} imports $uri');
      }
    }
  }
  return violations;
}

bool _staysInside(String from, String uri, List<String> allowed) {
  final resolved = File(from).absolute.uri.resolve(uri).toFilePath();
  final path = _normalize(resolved);
  for (final folder in allowed) {
    final root = _normalize(Directory('lib/$folder').absolute.path);
    if (path == root || path.startsWith('$root/')) return true;
  }
  return false;
}

String _normalize(String path) {
  final parts = <String>[];
  for (final part in path.split(Platform.pathSeparator)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}

final _importUri = RegExp('(?:import|export)\\s+[\'"]([^\'"]+)[\'"]');

Iterable<String> _importUris(String source) sync* {
  for (final line in source.split('\n')) {
    final code = line.split('//').first;
    final match = _importUri.firstMatch(code);
    if (match != null) yield match.group(1)!;
  }
}

bool _forbidden(String uri) {
  if (uri.startsWith('dart:')) return false;
  if (uri.startsWith('package:uuid/')) return false;
  if (uri.contains('..')) return true;
  if (uri.startsWith('package:')) return true;
  return false;
}
