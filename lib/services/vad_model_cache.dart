import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps a local copy of the Silero v5 VAD model so the session screen can
/// start listening without reaching the CDN.
///
/// The `vad` package loads its model from `baseAssetPath` (a jsDelivr URL by
/// default) every time `startListening()` runs, so with no network it fails
/// before recording can begin. This downloads the same file once (while
/// online) into the app's support directory; the session screen then passes
/// that directory as `baseAssetPath` and falls back to the CDN if the
/// package rejects it.
class VadModelCache {
  static const cdnBase = 'https://cdn.jsdelivr.net/npm/@keyurmaru/vad@0.0.1/';
  static const _fileName = 'silero_vad_v5.onnx';

  // The real model is ~2.3 MB; anything much smaller is a failed download.
  static const _minValidBytes = 1000000;

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'vad_model'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Directory path (with trailing slash) holding a valid cached model, or
  /// null if none has been downloaded yet.
  static Future<String?> localBasePath() async {
    final dir = await _dir();
    final file = File(p.join(dir.path, _fileName));
    if (await file.exists() && await file.length() >= _minValidBytes) {
      return '${dir.path}/';
    }
    return null;
  }

  /// Downloads the model once if it isn't cached. Safe to call repeatedly
  /// and never throws — offline or a failed download just leaves no cache.
  static Future<void> warmUp() async {
    try {
      if (await localBasePath() != null) return;
      final response = await http
          .get(Uri.parse('$cdnBase$_fileName'))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 ||
          response.bodyBytes.length < _minValidBytes) {
        return;
      }
      final dir = await _dir();
      final tmp = File(p.join(dir.path, '$_fileName.part'));
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(p.join(dir.path, _fileName));
    } catch (_) {
      // Best effort only.
    }
  }
}
