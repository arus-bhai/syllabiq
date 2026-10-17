import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/syllabus.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SessionInitResult {
  final String sessionId;
  final String syllabusTitle;
  final String cacheName;

  SessionInitResult({
    required this.sessionId,
    required this.syllabusTitle,
    required this.cacheName,
  });

  factory SessionInitResult.fromJson(Map<String, dynamic> json) {
    return SessionInitResult(
      sessionId: json['session_id'] as String,
      syllabusTitle: json['syllabus_title'] as String,
      cacheName: json['cache_name'] as String,
    );
  }
}

/// Result of a single ask/stream turn: transcript arrives as a header
/// (already decoded here), audio arrives as a raw PCM byte stream.
/// Call [close] once the pcmStream has been fully consumed to release
/// the underlying HTTP client.
class AskStreamResult {
  AskStreamResult({
    required this.transcript,
    required this.pcmStream,
    required this.close,
  });

  final String transcript;
  final Stream<List<int>> pcmStream;
  final void Function() close;
}

class ApiService {
  ApiService({required this.baseUrl});

  /// e.g. "http://10.0.2.2:8000" on Android emulator, or your deployed URL.
  final String baseUrl;

  Future<List<Syllabus>> fetchSyllabi() async {
    final uri = Uri.parse('$baseUrl/api/admin/syllabi');

    final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ApiException('Could not reach server: $e');
    }

    if (response.statusCode != 200) {
      throw ApiException(
        'Failed to load syllabi (${response.statusCode}): ${response.body}',
      );
    }

    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => Syllabus.fromApiJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SessionInitResult> initSession(String syllabusId) async {
    final uri = Uri.parse('$baseUrl/api/session/init');
    final request = http.MultipartRequest('POST', uri)
      ..fields['syllabus_id'] = syllabusId;

    final http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw ApiException('Could not reach server: $e');
    }

    if (response.statusCode != 200) {
      throw ApiException(
        'Failed to initialize session (${response.statusCode}): ${response.body}',
      );
    }

    final Map<String, dynamic> data =
    jsonDecode(response.body) as Map<String, dynamic>;
    return SessionInitResult.fromJson(data);
  }

  /// Sends one recorded utterance (WAV bytes) for [sessionId] and returns
  /// the transcript (from a response header) plus the raw PCM audio stream
  /// (24kHz mono 16-bit) of the spoken reply.
  Future<AskStreamResult> askQuestionStream(
      String sessionId,
      Uint8List wavBytes,
      ) async {
    final uri = Uri.parse('$baseUrl/api/session/ask/stream');
    final request = http.MultipartRequest('POST', uri)
      ..fields['session_id'] = sessionId
      ..files.add(
        http.MultipartFile.fromBytes(
          'audio_file',
          wavBytes,
          filename: 'utterance.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

    final client = http.Client();
    final http.StreamedResponse streamed;
    try {
      streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      client.close();
      throw ApiException('Could not reach server: $e');
    }

    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      client.close();
      throw ApiException(
        'ask/stream failed (${streamed.statusCode}): $body',
      );
    }

    var transcript = '';
    final transcriptB64 = streamed.headers['x-transcript-b64'];
    if (transcriptB64 != null) {
      try {
        transcript = utf8.decode(base64.decode(transcriptB64));
      } catch (_) {
        // Leave transcript empty rather than fail the whole turn over a
        // malformed header.
      }
    }

    return AskStreamResult(
      transcript: transcript,
      pcmStream: streamed.stream,
      close: client.close,
    );
  }
}