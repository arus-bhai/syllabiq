import 'dart:typed_data';

/// Encodes mono 16-bit PCM [samples] into a valid WAV file's bytes.
Uint8List encodeWav(Int16List samples, {required int sampleRate}) {
  final byteCount = samples.length * 2;
  final header = ByteData(44);

  void writeString(int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  header.setUint32(4, 36 + byteCount, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // PCM format
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate (16-bit mono)
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  writeString(36, 'data');
  header.setUint32(40, byteCount, Endian.little);

  final wavBytes = Uint8List(44 + byteCount);
  wavBytes.setRange(0, 44, header.buffer.asUint8List());
  wavBytes.setRange(
    44,
    wavBytes.length,
    samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes),
  );

  return wavBytes;
}

/// Converts float samples in [-1.0, 1.0] (what the `vad` package emits) into
/// 16-bit PCM. Assumes 16kHz mono, which is Silero VAD's standard rate —
/// confirm against the actual samples your VAD package hands back.
Int16List floatToInt16(List<double> floatSamples) {
  final out = Int16List(floatSamples.length);
  for (int i = 0; i < floatSamples.length; i++) {
    final clamped = floatSamples[i].clamp(-1.0, 1.0);
    out[i] = (clamped * 32767).round();
  }
  return out;
}
