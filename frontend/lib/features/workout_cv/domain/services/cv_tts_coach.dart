import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Priority levels for live Workout CV voice coaching ("Bank Face-ID" style).
enum CvTtsPriority {
  urgent,
  calibration,
  formCue,
  repCount,
}

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
/// Implements a 4-tier priority system inspired by bank Face-ID voice guidance:
/// 1. [CvTtsPriority.urgent]: Immediately interrupts current speech and bypasses
///    form-cue cooldown for critical safety/tracking interruptions.
/// 2. [CvTtsPriority.calibration]: Pre-workout framing cues with anti-spam
///    debounce and faster transitions when moving to a new setup step.
/// 3. [CvTtsPriority.formCue]: Technical form/tempo cues throttled by
///    [formCueCooldown] (`>= 2.5s`) and [sameCueCooldown] (`>= 5.0s`).
/// 4. [CvTtsPriority.repCount]: Plays a crisp chime ("Ting!") then announces
///    completed reps or 5-second hold milestones.
///
/// Also coordinates Android transient ducking AudioFocus when callbacks are
/// provided, and supports Vietnamese (`vi-VN`) and English (`en-US`) locales.
class CvTtsCoach {
  static const Duration _calibrationStepSwitchMinDelay =
      Duration(milliseconds: 1200);

  final CvTtsEngine _engine;
  final DateTime Function() _clock;
  final Future<bool> Function()? _onRequestAudioFocus;
  final Future<bool> Function()? _onAbandonAudioFocus;
  final Future<void> Function() _onRepChime;

  /// Minimum interval between any two form cues (`>= 2.5s`).
  final Duration formCueCooldown;

  /// Minimum interval before repeating the same form `cueKey`.
  final Duration sameCueCooldown;

  /// Minimum interval before repeating the exact same urgent `cueKey`.
  final Duration urgentCueCooldown;

  /// Minimum interval before repeating the same calibration step `cueKey`.
  final Duration calibrationCueCooldown;

  /// Delay after speech trigger before releasing Android transient AudioFocus.
  final Duration audioFocusReleaseDelay;

  /// Default speech rate applied to the TTS engine.
  final double speechRate;

  bool _isMuted;
  bool _isDisposed = false;
  bool _hasAudioFocus = false;
  Timer? _audioFocusTimer;
  String _localeTag;
  String? _appliedLocaleTag;

  int? _lastSpokenRep;
  int? _lastSpokenHoldSecond;
  DateTime? _lastFormCueAt;
  final Map<String, DateTime> _lastCueByKey = <String, DateTime>{};
  DateTime? _lastUrgentCueAt;
  String? _lastUrgentCueKey;
  DateTime? _lastCalibrationCueAt;
  String? _lastCalibrationCueKey;
  CvTtsPriority? _lastSpokenPriority;

  CvTtsCoach({
    CvTtsEngine? engine,
    DateTime Function()? clock,
    this.formCueCooldown = const Duration(milliseconds: 2500),
    this.sameCueCooldown = const Duration(milliseconds: 5000),
    this.speechRate = 0.5,
    bool initiallyMuted = false,
    String initialLanguageCode = 'vi',
    Future<bool> Function()? onRequestAudioFocus,
    Future<bool> Function()? onAbandonAudioFocus,
    Future<void> Function()? onRepChime,
    this.urgentCueCooldown = const Duration(milliseconds: 3000),
    this.calibrationCueCooldown = const Duration(milliseconds: 2500),
    this.audioFocusReleaseDelay = const Duration(milliseconds: 1800),
  })  : _engine = engine ?? FlutterTtsEngine(),
        _clock = clock ?? DateTime.now,
        _isMuted = initiallyMuted,
        _localeTag = _resolveLocaleTag(initialLanguageCode),
        _onRequestAudioFocus = onRequestAudioFocus,
        _onAbandonAudioFocus = onAbandonAudioFocus,
        _onRepChime = onRepChime ?? _defaultRepChime;

  bool get isMuted => _isMuted;
  String get currentLocale => _localeTag;
  bool get isVietnamese => _localeTag == 'vi-VN';
  bool get isDisposed => _isDisposed;
  bool get hasAudioFocus => _hasAudioFocus;
  CvTtsPriority? get lastSpokenPriority => _lastSpokenPriority;

  static Future<void> _defaultRepChime() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Safe no-op in headless/test environments without a platform sound channel.
    }
  }

  static String _resolveLocaleTag(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();
    if (normalized == 'vi' ||
        normalized.startsWith('vi-') ||
        normalized.startsWith('vi_')) {
      return 'vi-VN';
    }
    return 'en-US';
  }

  /// Toggles mute state. Muting stops any active speech and releases AudioFocus immediately.
  void setMuted(bool muted) {
    _isMuted = muted;
    if (muted && !_isDisposed) {
      _audioFocusTimer?.cancel();
      _audioFocusTimer = null;
      unawaited(_engine.stop());
      unawaited(_releaseAudioFocus());
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

  Future<void> _acquireAudioFocus() async {
    if (_onRequestAudioFocus == null && _onAbandonAudioFocus == null) return;
    _audioFocusTimer?.cancel();
    _audioFocusTimer = null;

    if (!_hasAudioFocus) {
      if (_onRequestAudioFocus != null) {
        try {
          _hasAudioFocus = await _onRequestAudioFocus();
        } catch (_) {
          _hasAudioFocus = false;
        }
      } else {
        _hasAudioFocus = true;
      }
    }

    if (_hasAudioFocus && !_isDisposed && !_isMuted) {
      _audioFocusTimer = Timer(audioFocusReleaseDelay, () {
        _audioFocusTimer = null;
        unawaited(_releaseAudioFocus());
      });
    }
  }

  Future<void> _releaseAudioFocus() async {
    _audioFocusTimer?.cancel();
    _audioFocusTimer = null;
    if (!_hasAudioFocus) return;
    _hasAudioFocus = false;
    if (_onAbandonAudioFocus != null) {
      try {
        await _onAbandonAudioFocus();
      } catch (_) {
        // Safe no-op if platform audio focus release fails.
      }
    }
  }

  Future<void> _playRepChime() async {
    try {
      await _onRepChime();
    } catch (_) {
      // Never block rep announcement if chime playback fails.
    }
  }

  Future<void> _speakWithFocus(String text) async {
    if (_isDisposed || _isMuted) return;
    await _ensureConfigured();
    if (_isDisposed || _isMuted) return;
    await _acquireAudioFocus();
    if (_isDisposed || _isMuted) return;
    await _engine.speak(text);
  }

  /// Priority 1 (Urgent): Immediately interrupts current speech and bypasses
  /// [formCueCooldown].
  ///
  /// Repeated calls with the exact same [cueKey] within [urgentCueCooldown] are
  /// suppressed, while switching to a different urgent [cueKey] interrupts and
  /// speaks immediately.
  Future<void> speakUrgent(String cueKey, String text) async {
    final trimmed = text.trim();
    if (_isDisposed || _isMuted || trimmed.isEmpty) return;

    final now = _clock();
    if (_lastUrgentCueKey == cueKey &&
        _lastUrgentCueAt != null &&
        now.difference(_lastUrgentCueAt!) < urgentCueCooldown) {
      return;
    }

    _lastUrgentCueKey = cueKey;
    _lastUrgentCueAt = now;
    _lastSpokenPriority = CvTtsPriority.urgent;

    await _engine.stop();
    await _speakWithFocus(trimmed);
  }

  /// Priority 2 (Face-ID Calibration): Announces step-by-step pre-workout
  /// framing guidance with anti-spam debounce (`>= calibrationCueCooldown`),
  /// allowing earlier transition after `1.2s` when the guidance step changes.
  Future<void> speakCalibrationCue(String cueKey, String text) async {
    final trimmed = text.trim();
    if (_isDisposed || _isMuted || trimmed.isEmpty) return;

    final now = _clock();
    if (_lastCalibrationCueAt != null) {
      final elapsed = now.difference(_lastCalibrationCueAt!);
      if (_lastCalibrationCueKey == cueKey) {
        if (elapsed < calibrationCueCooldown) return;
      } else {
        final minSwitchDelay =
            calibrationCueCooldown < _calibrationStepSwitchMinDelay
                ? calibrationCueCooldown
                : _calibrationStepSwitchMinDelay;
        if (elapsed < minSwitchDelay) return;
      }
    }

    _lastCalibrationCueKey = cueKey;
    _lastCalibrationCueAt = now;
    _lastSpokenPriority = CvTtsPriority.calibration;

    await _speakWithFocus(trimmed);
  }

  /// Priority 4 (Rep Count): Plays a crisp "Ting!" chime then announces the
  /// completed rep number or 5-second hold milestone.
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
      _lastSpokenPriority = CvTtsPriority.repCount;
      await _playRepChime();
      final phrase = isVietnamese ? '$repNumber giây' : '$repNumber seconds';
      await _speakWithFocus(phrase);
      return;
    }

    if (_lastSpokenRep == repNumber) return;
    _lastSpokenRep = repNumber;
    _lastSpokenPriority = CvTtsPriority.repCount;
    await _playRepChime();
    await _speakWithFocus('$repNumber');
  }

  /// Priority 3 (Form Cue): Announces a coaching form cue if unmuted and both
  /// cooldown windows allow it (`formCueCooldown >= 2.5s`, `sameCueCooldown >= 5.0s`).
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
    _lastSpokenPriority = CvTtsPriority.formCue;

    await _speakWithFocus(trimmed);
  }

  /// Speaks calibration countdown digits or start cue without form-cue throttling.
  Future<void> speakCountdown(String text) async {
    final trimmed = text.trim();
    if (_isDisposed || _isMuted || trimmed.isEmpty) return;
    _lastSpokenPriority = CvTtsPriority.calibration;
    await _speakWithFocus(trimmed);
  }

  /// Clears per-session deduplication state (e.g., when a session restarts).
  void resetSessionTracking() {
    _lastSpokenRep = null;
    _lastSpokenHoldSecond = null;
    _lastFormCueAt = null;
    _lastCueByKey.clear();
    _lastUrgentCueAt = null;
    _lastUrgentCueKey = null;
    _lastCalibrationCueAt = null;
    _lastCalibrationCueKey = null;
    _lastSpokenPriority = null;
  }

  /// Immediately halts current TTS playback and releases AudioFocus.
  Future<void> stop() async {
    if (_isDisposed) return;
    _audioFocusTimer?.cancel();
    _audioFocusTimer = null;
    await _engine.stop();
    await _releaseAudioFocus();
  }

  /// Releases TTS resources, AudioFocus, and blocks further speech requests.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _audioFocusTimer?.cancel();
    _audioFocusTimer = null;
    await _engine.stop();
    await _releaseAudioFocus();
  }
}
