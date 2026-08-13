import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const maxAvatarBytes = 2 * 1024 * 1024;
// MiMo accepts at most 10 MB for the Base64 data URL. Reserve space for the
// MIME prefix and account for Base64's 4/3 expansion.
const maxVoiceReferenceBytes = ((10_000_000 - 32) ~/ 4) * 3;

abstract interface class CharacterAssetStore {
  Future<String> importAvatar(String sourcePath, String characterId);
  Future<String> importVoiceReference(String sourcePath, String characterId);
  Future<void> deleteRelative(String? path);
  Future<void> purgeOrphans(Set<String> referencedPaths);
}

final class FileCharacterAssetStore implements CharacterAssetStore {
  FileCharacterAssetStore({required this.root});

  final Directory root;
  static int _sequence = 0;

  @override
  Future<String> importAvatar(String sourcePath, String characterId) async {
    _validateCharacterId(characterId);
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('Avatar image is empty');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('Avatar image is invalid');
    var image = img.bakeOrientation(decoded);
    final square = math.min(image.width, image.height);
    image = img.copyCrop(
      image,
      x: (image.width - square) ~/ 2,
      y: (image.height - square) ~/ 2,
      width: square,
      height: square,
    );
    if (image.width > 1024) {
      image = img.copyResize(
        image,
        width: 1024,
        height: 1024,
        interpolation: img.Interpolation.cubic,
      );
    }

    List<int>? encoded;
    for (final quality in const [88, 80, 72, 64, 56, 55]) {
      final candidate = img.encodeJpg(image, quality: quality);
      if (candidate.length <= maxAvatarBytes) {
        encoded = candidate;
        break;
      }
    }
    if (encoded == null) {
      throw RangeError('Processed avatar exceeds 2 MB');
    }
    final relative = 'avatars/${_fileStem(characterId)}.jpg';
    await _writeAtomically(relative, encoded);
    return relative;
  }

  @override
  Future<String> importVoiceReference(
    String sourcePath,
    String characterId,
  ) async {
    _validateCharacterId(characterId);
    final source = File(sourcePath);
    final length = await source.length();
    if (length == 0) throw const FormatException('Reference audio is empty');
    if (length > maxVoiceReferenceBytes) {
      throw RangeError('Reference audio exceeds 7.5 MB');
    }
    final extension = source.path.toLowerCase().endsWith('.wav')
        ? '.wav'
        : source.path.toLowerCase().endsWith('.mp3')
        ? '.mp3'
        : null;
    if (extension == null) {
      throw const FormatException('Reference audio must be WAV or MP3');
    }
    final bytes = await source.readAsBytes();
    final isWave =
        extension == '.wav' &&
        bytes.length >= 12 &&
        _ascii(bytes, 0, 4) == 'RIFF' &&
        _ascii(bytes, 8, 12) == 'WAVE';
    final isMp3 =
        extension == '.mp3' &&
        (_startsWith(bytes, const [0x49, 0x44, 0x33]) ||
            (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0));
    if (!isWave && !isMp3) {
      throw const FormatException('Reference audio content is invalid');
    }
    final relative = 'voices/${_fileStem(characterId)}$extension';
    await _writeAtomically(relative, bytes);
    return relative;
  }

  @override
  Future<void> deleteRelative(String? path) async {
    if (path == null) return;
    final file = _privateFile(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> purgeOrphans(Set<String> referencedPaths) async {
    final references = referencedPaths.map(_normalizeRelative).toSet();
    for (final directoryName in const ['avatars', 'voices']) {
      final directory = Directory('${root.path}/$directoryName');
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final relative = '$directoryName/${entity.uri.pathSegments.last}';
        if (!references.contains(relative)) await entity.delete();
      }
    }
  }

  Future<void> _writeAtomically(String relative, List<int> bytes) async {
    final destination = _privateFile(relative);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  File _privateFile(String relative) {
    final normalized = _normalizeRelative(relative);
    final first = normalized.split('/').first;
    if (first != 'avatars' && first != 'voices') {
      throw const FormatException(
        'Asset path is outside private asset folders',
      );
    }
    return File('${root.path}/$normalized');
  }

  static String _normalizeRelative(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.isEmpty ||
        normalized.split('/').contains('..')) {
      throw const FormatException('Asset path must be relative');
    }
    return normalized;
  }

  static String _fileStem(String characterId) {
    final sequence = _sequence++;
    return '${characterId}_${DateTime.now().microsecondsSinceEpoch}_$sequence';
  }

  static void _validateCharacterId(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      throw const FormatException('Character ID is invalid');
    }
  }

  static String _ascii(List<int> bytes, int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }
}
