import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:vad/vad.dart';

import '../services/api_service.dart';
import '../services/chime_player.dart';
import '../services/live_pcm_player.dart';
import '../services/offline_queue_service.dart';
import '../services/response_cache_service.dart';
import '../utils/wav_encoder.dart';
import '../widgets/listening_mic_indicator.dart';
import '../widgets/study_background.dart';

enum AssistantState { initializing, idle, listening, processing, speaking, error }

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.sessionId,
    required this.syllabusTitle,
    required this.apiService,
  });

  final String sessionId;
  final String syllabusTitle;
  final ApiService apiService;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final VadHandler _vadHandler;
  final LivePcmPlayer _playback = LivePcmPlayer();
  final ChimePlayer _chime = ChimePlayer();
  final OfflineQueueService _offlineQueue = OfflineQueueService();
  final ResponseCacheService _responseCache = ResponseCacheService();

  StreamSubscription? _speechStartSub;
  StreamSubscription? _speechEndSub;
  StreamSubscription? _misfireSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _connectivitySub;

  AssistantState _state = AssistantState.initializing;
  String? _lastResponseText;
  String? _errorMessage;

  /// True once the VAD model has loaded successfully at least once — after
  /// that, per-turn restarts skip the "initializing" UI state, since the
  /// model should already be resident and startListening() should resolve
  /// quickly rather than re-fetching from the CDN.
  bool _vadInitialized = false;

  /// Audio for the most recent response only — enough for the replay
  /// button. Not kept per history entry; only ever the latest one. Backed
  /// by [ResponseCacheService] on disk, so it survives app restarts and
  /// works with no network at all.
  Uint8List? _lastResponsePcm;

  /// Text-only history of the last 3 responses, newest last. No audio
  /// stored here, and no user-query text — the backend doesn't return a
  /// separate transcription of what the user said.
  static const _maxQueueSize = 3;
  final List<String> _responseTextQueue = [];

  /// How many recorded questions are currently sitting in the offline
  /// queue, waiting for connectivity to come back. Drives the small
  /// "waiting to send" banner.
  int _pendingCount = 0;
  bool _isDraining = false;

  @override
  void initState() {
    super.initState();
    _vadHandler = VadHandler.create();

    // NOTE: confirm your `vad` package version actually exposes
    // onSpeechStart — some versions may name it differently
    // (onRealSpeechStart, onSpeechDetected, etc). If it's missing entirely,
    // the start chime can't fire on true speech onset and would need a
    // different signal.
    //
    // Using onRealSpeechStart rather than onSpeechStart deliberately:
    // onSpeechStart fires tentatively and can be walked back via
    // onVADMisfire (segment too short to count as real speech).
    // onRealSpeechStart only fires once minSpeechFrames is actually
    // satisfied, so the start chime + "listening" UI state won't fire on
    // noise blips that get discarded.
    _speechStartSub = _vadHandler.onRealSpeechStart.listen((_) => _onSpeechStart());
    _speechEndSub = _vadHandler.onSpeechEnd.listen(_onSpeechEnd);

    // Without this, a misfired segment leaves the UI stuck in "listening"
    // forever (or until some later, unrelated utterance's onSpeechEnd
    // accidentally resets it) — this was the actual cause of recording
    // appearing to "not end on silence."
    _misfireSub = _vadHandler.onVADMisfire.listen((_) => _onMisfire());
    _errorSub = _vadHandler.onError.listen(_onVadError);

    // Fires whenever the device's connectivity state changes. Used only as
    // a trigger to try sending whatever's queued — the actual network call
    // inside drainQueue() is still the source of truth (a device can report
    // "wifi" while the wifi has no real internet access).
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) _drainOfflineQueue();
    });

    _loadPersistedResponseCache();
    _refreshPendingCount();
    _initSession();
  }

  /// Loads whatever answer was last durably cached (possibly from a
  /// previous app run, or from a question that was queued offline and sent
  /// in the background) so Replay works immediately, even with no network.
  Future<void> _loadPersistedResponseCache() async {
    final cached = await _responseCache.load();
    if (cached != null && mounted) {
      setState(() {
        _lastResponsePcm = cached.pcmBytes;
        _lastResponseText = cached.transcript;
      });
    }
  }

  Future<void> _refreshPendingCount() async {
    final count = await _offlineQueue.pendingCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  /// Plays the "session ready" chime once, then starts continuous
  /// listening. This chime no longer fires per-utterance — it's a single
  /// cue marking the assistant is now live for this session.
  Future<void> _initSession() async {
    await _chime.playStart();
    await _startListening();
    // In case questions queued up while the app was closed and the device
    // is already back online by the time this session opens.
    _drainOfflineQueue();
  }

  Future<void> _startListening() async {
    final isFirstInit = !_vadInitialized;
    if (mounted) {
      setState(() {
        // Only show the loading state for the genuine first-time model
        // load. Per-turn restarts set idle as a neutral placeholder while
        // this resolves — should be fast once the model's already loaded,
        // so there's nothing worth showing a spinner for.
        _state = isFirstInit ? AssistantState.initializing : AssistantState.idle;
        _errorMessage = null;
      });
    }
    try {
      await _vadHandler
          .startListening(
        positiveSpeechThreshold: 0.5,
        negativeSpeechThreshold: 0.35,
        redemptionFrames: 8,
        minSpeechFrames: 3,
        model: 'v5', // newer model than the package default 'legacy'
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'VAD model failed to load within 15s — likely a network '
              'issue reaching the model CDN (jsdelivr).',
        ),
      );
      _vadInitialized = true;
      if (mounted) {
        setState(() {
          _state = AssistantState.idle;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = AssistantState.error;
          _errorMessage = 'Could not start listening: $e';
        });
      }
    }
  }

  void _onSpeechStart() {
    debugPrint('[VAD] real speech start confirmed');
    if (mounted) setState(() => _state = AssistantState.listening);
  }

  void _onMisfire() {
    debugPrint('[VAD] misfire — discarded, resetting to idle');
    // Only reset if we were actually mid-"listening" for this — avoids
    // clobbering state if a misfire arrives while processing/speaking.
    if (mounted && _state == AssistantState.listening) {
      setState(() => _state = AssistantState.idle);
    }
  }

  void _onVadError(String message) {
    debugPrint('[VAD] error: $message');
    if (mounted) {
      setState(() {
        _state = AssistantState.error;
        _errorMessage = message;
      });
    }
  }

  Future<void> _onSpeechEnd(List<double> samples) async {
    debugPrint('[VAD] speech end detected — ${samples.length} samples');
    await _vadHandler.stopListening();

    if (!mounted) return;
    setState(() => _state = AssistantState.processing);

    // Silero VAD (what the `vad` package wraps) operates at 16kHz —
    // confirm this matches your package version's actual output rate.
    final int16Samples = floatToInt16(samples);
    final wavBytes = encodeWav(int16Samples, sampleRate: 16000);

    AskStreamResult? result;
    try {
      result = await widget.apiService.askQuestionStream(widget.sessionId, wavBytes);
    } catch (e) {
      // Distinguish "couldn't reach the server at all" (network down —
      // queue it, nothing is lost) from a real backend error (e.g. a 4xx/5xx
      // response) — retrying a genuine error forever would be pointless, so
      // only connectivity-shaped failures get queued. See ApiService: that
      // message prefix is only used for the exception thrown around the
      // HTTP send() call itself (SocketException/TimeoutException/etc),
      // never for a non-200 response.
      final isOffline = e is ApiException && e.message.startsWith('Could not reach server');
      if (isOffline) {
        await _offlineQueue.enqueue(widget.sessionId, wavBytes);
        await _refreshPendingCount();
        if (mounted) {
          setState(() {
            _state = AssistantState.idle;
            _errorMessage = null;
            _lastResponseText =
            "You're offline — this question has been saved and will be "
                "answered automatically once you're back online.";
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _state = AssistantState.error;
            _errorMessage = 'Request failed: $e';
          });
        }
      }
    }

    if (result != null) {
      if (!mounted) return;
      setState(() {
        _lastResponseText = result!.transcript;
        _state = AssistantState.speaking;
      });

      // Chime marks "the assistant is about to respond" — plays right
      // before playback starts, not on speech end itself.
      await _chime.playEnd();

      // Tee the stream: one copy feeds live playback as before, the other
      // accumulates bytes so this response can be replayed later without
      // re-hitting the API (playStream() consumes its input stream once).
      final teeController = StreamController<List<int>>();
      final bytesBuilder = BytesBuilder();
      final teeSub = result.pcmStream.listen(
            (chunk) {
          bytesBuilder.add(chunk);
          teeController.add(chunk);
        },
        onDone: teeController.close,
        onError: teeController.addError,
      );

      try {
        await _playback.playStream(teeController.stream);
      } finally {
        await teeSub.cancel();
        result.close();
      }

      final pcmBytes = bytesBuilder.toBytes();
      if (mounted) setState(() => _lastResponsePcm = pcmBytes);
      _pushResponseTextQueue(result.transcript);

      // Persist durably so Replay survives an app restart / works with no
      // network — fire-and-forget, playback has already finished either way.
      unawaited(_responseCache.save(widget.sessionId, result.transcript, pcmBytes));
    }

    // Resume continuous listening for the next utterance. VAD (not a wake
    // word) stays stopped during playback so the assistant's own audio
    // can't be picked up as new speech.
    //
    // The short delay guards against a race inside the `vad` package
    // itself: stopListening()'s Future can resolve before its internal
    // frame-processing closure has fully drained, so calling
    // startListening() again immediately can crash with "Cannot add new
    // events after calling close" if a trailing frame from the old
    // session fires after the new one has begun.
    if (mounted) setState(() => _state = AssistantState.idle);
    await Future.delayed(const Duration(milliseconds: 200));
    await _startListening();
  }

  /// Sends every queued (previously offline) question, oldest first. Safe
  /// to call opportunistically — connectivity-change events, session start,
  /// and a manual retry can all call this, and it no-ops while already
  /// running or when the queue is empty.
  Future<void> _drainOfflineQueue() async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      final sent = await _offlineQueue.drainQueue(
        widget.apiService,
        onItemSent: (answer) async {
          if (mounted) {
            setState(() {
              _lastResponsePcm = answer.pcmBytes;
              _lastResponseText = answer.transcript;
            });
          }
        },
      );
      if (sent > 0) {
        debugPrint('[Offline] sent $sent queued question(s).');
      }
    } catch (e) {
      debugPrint('[Offline] drain attempt stopped: $e');
    } finally {
      _isDraining = false;
      await _refreshPendingCount();
    }
  }

  void _pushResponseTextQueue(String text) {
    _responseTextQueue.add(text);
    if (_responseTextQueue.length > _maxQueueSize) {
      _responseTextQueue.removeAt(0);
    }
  }

  Future<void> _replayLast() async {
    final pcm = _lastResponsePcm;
    if (pcm == null) return;

    // Same pause-VAD-during-playback rule as a normal turn, so the
    // assistant's own audio can't be picked up as new speech. This works
    // fully offline — the bytes came from ResponseCacheService on disk.
    await _vadHandler.stopListening();
    if (mounted) setState(() => _state = AssistantState.speaking);

    await _playback.playStream(Stream.value(pcm));

    if (mounted) setState(() => _state = AssistantState.idle);
    await Future.delayed(const Duration(milliseconds: 200));
    await _startListening();
  }

  @override
  void dispose() {
    _speechStartSub?.cancel();
    _speechEndSub?.cancel();
    _misfireSub?.cancel();
    _errorSub?.cancel();
    _connectivitySub?.cancel();
    // dispose() must be synchronous, but stopListening() is async — if we
    // fire both without sequencing, _vadHandler.dispose() (which closes
    // internal StreamControllers) can run while a frame is still mid-flight
    // from just before stopListening() took effect, crashing with "Cannot
    // add new events after calling close". Chaining onto stopListening()'s
    // completion guarantees the engine has actually halted first.
    _vadHandler.stopListening().whenComplete(() {
      _vadHandler.dispose();
    });
    _playback.dispose();
    _chime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.syllabusTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: StudyBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_state == AssistantState.listening)
                          const ListeningMicIndicator(isListening: true)
                        else if (_state == AssistantState.initializing) ...[
                          const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          const SizedBox(height: 16),
                          Text(_labelForState(), style: const TextStyle(fontSize: 18)),
                        ] else ...[
                          Icon(_iconForState(), size: 64, color: _colorForState()),
                          const SizedBox(height: 16),
                          Text(_labelForState(), style: const TextStyle(fontSize: 18)),
                        ],
                        if (_pendingCount > 0) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off, size: 18, color: Colors.orange),
                                const SizedBox(width: 8),
                                Text(
                                  _pendingCount == 1
                                      ? '1 question waiting to send'
                                      : '$_pendingCount questions waiting to send',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_state == AssistantState.error) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _startListening,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                        if (_lastResponseText != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Response:',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(_lastResponseText!, textAlign: TextAlign.center),
                        ],
                        if (_lastResponsePcm != null &&
                            (_state == AssistantState.idle ||
                                _state == AssistantState.listening)) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _replayLast,
                            icon: const Icon(Icons.replay),
                            label: const Text('Replay last response'),
                          ),
                        ],
                        if (_responseTextQueue.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Recent responses:',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 4),
                          for (final text in _responseTextQueue.reversed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13, color: Colors.black54),
                              ),
                            ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  IconData _iconForState() {
    switch (_state) {
      case AssistantState.initializing:
        return Icons.hourglass_empty;
      case AssistantState.idle:
        return Icons.mic_none;
      case AssistantState.listening:
        return Icons.mic;
      case AssistantState.processing:
        return Icons.hourglass_top;
      case AssistantState.speaking:
        return Icons.volume_up;
      case AssistantState.error:
        return Icons.error_outline;
    }
  }

  Color _colorForState() {
    switch (_state) {
      case AssistantState.initializing:
        return Colors.blueGrey;
      case AssistantState.idle:
        return Colors.grey;
      case AssistantState.listening:
        return Colors.red;
      case AssistantState.processing:
        return Colors.orange;
      case AssistantState.speaking:
        return Colors.indigo;
      case AssistantState.error:
        return Colors.red.shade900;
    }
  }

  String _labelForState() {
    switch (_state) {
      case AssistantState.initializing:
        return 'Setting up voice assistant...';
      case AssistantState.idle:
        return 'Listening for your question...';
      case AssistantState.listening:
        return 'Recording...';
      case AssistantState.processing:
        return 'Thinking...';
      case AssistantState.speaking:
        return 'Playing back your recording...';
      case AssistantState.error:
        return 'Something went wrong';
    }
  }
}
