import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Injectable text-to-speech engine contract for Workout CV live coaching.
abstract class CvTtsEngine {
  Future<void> setLanguage(String lang);
  Future<void> setSpeechRate(double rate);
  Future<void> speak(String text);
  Future<void> stop();
}

/// Production [CvTtsEngine] backed by [FlutterTts] with safe error guards so
/// environments without a native TTS plugin (e.g., widget/unit tests) never crash.
class FlutterTtsEngine implements CvTtsEngine {
  FlutterTts? _tts;

  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts;

  FlutterTts? _ensurePlugin() {
    if (_tts != null) return _tts;
    try {
      _tts = FlutterTts();
      return _tts;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setLanguage(String lang) async {
    try {
      await _ensurePlugin()?.setLanguage(lang);
    } catch (_) {
      // Safe no-op when TTS plugin channel is unavailable.
    }
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    try {
      await _ensurePlugin()?.setSpeechRate(rate);
    } catch (_) {
      // Safe no-op when TTS plugin channel is unavailable.
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _ensurePlugin()?.speak(text);
    } catch (_) {
      // Safe no-op when TTS plugin channel is unavailable.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _ensurePlugin()?.stop();
    } catch (_) {
      // Safe no-op when TTS plugin channel is unavailable.
    }
  }
}

/// Live audio coaching coordinator for `WorkoutCvScreen`.
///
/// - Enforces rate-limiting / debounce (`>= 2.5s` global cooldown, `>= 5.0s`
///   per cue key) on form cues so rapid frame jitter never spams audio.
/// - Prioritizes rep counts and plank hold milestones by bypassing the form-cue
///   cooldown while preventing duplicate announcements of the same number.
/// - Supports Vietnamese (`vi-VN`) and English (`en-US`) locales.
class CvTtsCoach {
  final CvTtsEngine _engine;
  final DateTime Function() _clock;

  /// Minimum interval between any two form cues (`>= 2.5s`).
  final Duration formCueCooldown;

  /// Minimum interval before repeating the same `cueKey`.
  final Duration sameCueCooldown;

  /// Default speech rate applied to the TTS engine.
  final double speechRate;

  bool _isMuted;
  bool _isDisposed = false;
  String _localeTag;
  String? _appliedLocaleTag;

  int? _lastSpokenRep;
  int? _lastSpokenHoldSecond;
  DateTime? _lastFormCueAt;
  final Map<String, DateTime> _lastCueByKey = <String, DateTime>{};

  CvTtsCoach({
    CvTtsEngine? engine,
    DateTime Function()? clock,
    this.formCueCooldown = const Duration(milliseconds: 2500),
    this.sameCueCooldown = const Duration(milliseconds: 5000),
    this.speechRate = 0.5,
    bool initiallyMuted = false,
    String initialLanguageCode = 'vi',
  })  : _engine = engine ?? FlutterTtsEngine(),
        _clock = clock ?? DateTime.now,
        _isMuted = initiallyMuted,
        _localeTag = _resolveLocaleTag(initialLanguageCode);

  bool get isMuted => _isMuted;
  String get currentLocale => _localeTag;
  bool get isVietnamese => _localeTag == 'vi-VN';
  bool get isDisposed => _isDisposed;

  static String _resolveLocaleTag(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();
    if (normalized == 'vi' || normalized.startsWith('vi-') || normalized.startsWith('vi_')) {
      return 'vi-VN';
    }
    return 'en-US';
  }

  /// Toggles mute state. Muting stops any active speech immediately.
  void setMuted(bool muted) {
    _isMuted = muted;
    if (muted && !_isDisposed) {
      unawaited(_engine.stop());
    }
  }

  /// Updates the active TTS locale (`vi-VN` for `'vi'`, otherwise `en-US`).
  Future<void> updateLocale(String languageCode) async {
    if (_isDisposed) return;
    final nextTag = _resolveLocaleTag(languageCode);
    _localeTag = nextTag;
    if (_appliedLocaleTag == nextTag) return;
    _appliedLocaleTag = nextTag;
    await _engine.setLanguage(nextTag);
    await _engine.setSpeechRate(speechRate);
  }

  Future<void> _ensureConfigured() async {
    if (_appliedLocaleTag == _localeTag) return;
    _appliedLocaleTag = _localeTag;
    await _engine.setLanguage(_localeTag);
    await _engine.setSpeechRate(speechRate);
  }

  /// High-priority announcement for completed reps or hold-second milestones.
  ///
  /// Bypasses [formCueCooldown] so rep counting is never delayed by a recent
  /// form cue, while avoiding duplicate announcements of the same value.
  Future<void> speakRepCount(
    int repNumber, {
    bool isHoldSecond = false,
  }) async {
    if (_isDisposed || _isMuted || repNumber <= 0) return;

    if (isHoldSecond) {
      if (repNumber % 5 != 0) return;
      if (_lastSpokenHoldSecond == repNumber) return;
      _lastSpokenHoldSecond = repNumber;
      await _ensureConfigured();
      final phrase = isVietnamese ? '$repNumber giây' : '$repNumber seconds';
      await _engine.speak(phrase);
      return;
    }

    if (_lastSpokenRep == repNumber) return;
    _lastSpokenRep = repNumber;
    await _ensureConfigured();
    await _engine.speak('$repNumber');
  }

  /// Announces a coaching form cue if unmuted and both cooldown windows allow it.
  Future<void> speakFormCue(String cueKey, String text) async {
    final trimmed = text.trim();
    if (_isDisposed || _isMuted || trimmed.isEmpty) return;

    final now = _clock();
    if (_lastFormCueAt != null &&
        now.difference(_lastFormCueAt!) < formCueCooldown) {
      return;
    }

    final previousForKey = _lastCueByKey[cueKey];
    if (previousForKey != null &&
        now.difference(previousForKey) < sameCueCooldown) {
      return;
    }

    _lastFormCueAt = now;
    _lastCueByKey[cueKey] = now;

    await _ensureConfigured();
    await _engine.speak(trimmed);
  }

  /// Speaks calibration countdown digits or start cue without form-cue throttling.
  Future<void> speakCountdown(String text) async {
    final trimmed = text.trim();
    if (_isDisposed || _isMuted || trimmed.isEmpty) return;
    await _ensureConfigured();
    await _engine.speak(trimmed);
  }

  /// Clears per-session deduplication state (e.g., when a session restarts).
  void resetSessionTracking() {
    _lastSpokenRep = null;
    _lastSpokenHoldSecond = null;
    _lastFormCueAt = null;
    _lastCueByKey.clear();
  }

  /// Immediately halts current TTS playback.
  Future<void> stop() async {
    if (_isDisposed) return;
    await _engine.stop();
  }

  /// Releases TTS resources and blocks further speech requests.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _engine.stop();
  }
}
