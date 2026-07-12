import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PttKey { none, control, shift, alt, command, capsLock }

class SettingsService extends ChangeNotifier {
  static const String _kPttKey = 'ptt_key';
  static const String _kPttSuppress = 'ptt_suppress';
  static const String _kThemeMode = 'theme_mode';
  static const String _kCustomHotkey = 'custom_hotkey';
  static const String _kHotkeyBindings = 'hotkey_bindings';
  static const String _kWindowWidth = 'window_width';
  static const String _kWindowHeight = 'window_height';
  static const String _kWindowX = 'window_x';
  static const String _kWindowY = 'window_y';
  static const String _kReconnectToLastServer = 'reconnect_last_server';
  static const String _kLastServerJson = 'last_server_json';
  static const String _kCaptureDeviceId = 'capture_device_id';
  static const String _kPlaybackDeviceId = 'playback_device_id';
  static const String _kInputGain = 'input_gain';
  static const String _kOutputVolume = 'output_volume';
  static const String _kIgnoreAccessibility = 'ignore_accessibility';
  static const String _kUserVolumes = 'user_volumes';
  static const String _kLocalMutedUsers = 'local_muted_users';
  static const String _kShowVolumeIndicator = 'show_volume_indicator';
  static const String _kOutgoingAudioBitrate = 'outgoing_audio_bitrate';
  static const String _kOutgoingAudioMsPerPacket = 'outgoing_audio_ms_per_packet';
  static const String _kIncomingJitterBufferMs = 'incoming_jitter_buffer_ms';
  static const String _kPlaybackHwBufferMs = 'playback_hw_buffer_ms';
  static const String _kRememberLastChannel = 'remember_last_channel';
  static const String _kHideEmptyChannels = 'hide_empty_channels';
  static const String _kPttHoldMs = 'ptt_hold_ms';
  static const String _kPtStartDelayMs = 'ptt_start_delay_ms';
  static const String _kTransmissionMode = 'transmission_mode';
  static const String _kVadMethod = 'vad_method';
  static const String _kVadThreshold = 'vad_threshold';
  static const String _kShowChat = 'show_chat';
  static const String _kEchoCancellation = 'echo_cancellation';
  static const String _kNoiseSuppression = 'noise_suppression';
  static const String _kAutomaticGainControl = 'automatic_gain_control';
  static const String _kShowFloatingOverlay = 'show_floating_overlay';

  final SharedPreferences _prefs;

  PttKey _pttKey;
  bool _pttSuppress;
  ThemeMode _themeMode;
  Map<String, dynamic>? _customHotkey;
  List<Map<String, dynamic>> _hotkeyBindings;
  bool _reconnectToLastServer;
  String? _lastServerJson;
  String? _captureDeviceId;
  String? _playbackDeviceId;
  double _inputGain;
  double _outputVolume;
  bool _ignoreAccessibility;
  bool _showVolumeIndicator;
  final Map<String, double> _userVolumes;
  final Set<String> _localMutedUsers;
  int _outgoingAudioBitrate;
  int _outgoingAudioMsPerPacket;
  int _incomingJitterBufferMs;
  int _playbackHwBufferMs;
  bool _rememberLastChannel;
  bool _hideEmptyChannels;
  int _pttHoldMs;
  int _pttStartDelayMs;
  int _transmissionMode; // 0: PTT, 1: Always Send, 2: Auto-Activate
  int _vadMethod; // 0: Threshold, 1: AI
  double _vadThreshold;
  bool _showChat;
  bool _echoCancellation;
  bool _noiseSuppression;
  bool _automaticGainControl;
  bool _showFloatingOverlay;

  SettingsService(this._prefs)
    : _pttKey = PttKey.values[_prefs.getInt(_kPttKey) ?? 0],
      _pttSuppress = _prefs.getBool(_kPttSuppress) ?? true,
      _themeMode = ThemeMode.values[_prefs.getInt(_kThemeMode) ?? 2],
      _reconnectToLastServer = _prefs.getBool(_kReconnectToLastServer) ?? false,
      _lastServerJson = _prefs.getString(_kLastServerJson),
      _captureDeviceId = _prefs.getString(_kCaptureDeviceId),
      _playbackDeviceId = _prefs.getString(_kPlaybackDeviceId),
      _inputGain = _prefs.getDouble(_kInputGain) ?? 1.0,
      _outputVolume = _prefs.getDouble(_kOutputVolume) ?? 1.0,
      _ignoreAccessibility = _prefs.getBool(_kIgnoreAccessibility) ?? false,
      _showVolumeIndicator = _prefs.getBool(_kShowVolumeIndicator) ?? true,
      _outgoingAudioBitrate = _prefs.getInt(_kOutgoingAudioBitrate) ?? 72000,
      _outgoingAudioMsPerPacket = _prefs.getInt(_kOutgoingAudioMsPerPacket) ?? 10,
      _incomingJitterBufferMs = _prefs.getInt(_kIncomingJitterBufferMs) ?? 40,
      _playbackHwBufferMs = _prefs.getInt(_kPlaybackHwBufferMs) ?? 0,
      _rememberLastChannel = _prefs.getBool(_kRememberLastChannel) ?? true,
      _hideEmptyChannels = _prefs.getBool(_kHideEmptyChannels) ?? false,
      _pttHoldMs = _prefs.getInt(_kPttHoldMs) ?? 200,
      _pttStartDelayMs = _prefs.getInt(_kPtStartDelayMs) ?? 0,
      _transmissionMode = _prefs.getInt(_kTransmissionMode) ?? 0,
      _vadMethod = _prefs.getInt(_kVadMethod) ?? 0,
      _vadThreshold = _prefs.getDouble(_kVadThreshold) ?? 0.1,
      _showChat = _prefs.getBool(_kShowChat) ?? true,
      _echoCancellation = _prefs.getBool(_kEchoCancellation) ?? true,
      _noiseSuppression = _prefs.getBool(_kNoiseSuppression) ?? true,
      _automaticGainControl = _prefs.getBool(_kAutomaticGainControl) ?? true,
      _showFloatingOverlay = _prefs.getBool(_kShowFloatingOverlay) ?? true,
      _hotkeyBindings = [],
      _userVolumes = {},
      _localMutedUsers = {} {
    // Load user volumes
    final List<String>? userVols = _prefs.getStringList(_kUserVolumes);
    if (userVols != null) {
      for (final s in userVols) {
        final parts = s.split(':');
        if (parts.length == 2) {
          final name = Uri.decodeComponent(parts[0]);
          final vol = double.tryParse(parts[1]);
          if (vol != null) {
            _userVolumes[name] = vol;
          }
        }
      }
    }

    // Load local muted users
    final List<String>? localMuted = _prefs.getStringList(_kLocalMutedUsers);
    if (localMuted != null) {
      _localMutedUsers.addAll(localMuted);
    }

    final String? customJson = _prefs.getString(_kCustomHotkey);
    if (customJson != null) {
      try {
        _customHotkey = Map<String, dynamic>.from(
          Uri.parse('http://foo?$customJson').queryParameters,
        );
        // Migrating old custom hotkey to new list if not already there
        if (_customHotkey != null) {
           _hotkeyBindings.add({
             'action': 'pushToTalk',
             ..._customHotkey!,
           });
        }
      } catch (_) {}
    }

    final List<String>? bindingsJson = _prefs.getStringList(_kHotkeyBindings);
    if (bindingsJson != null) {
      _hotkeyBindings = bindingsJson
          .map((s) => jsonDecode(s))
          .cast<Map<String, dynamic>>()
          .toList();
    }
  }

  PttKey get pttKey => _pttKey;
  bool get pttSuppress => _pttSuppress;
  ThemeMode get themeMode => _themeMode;
  Map<String, dynamic>? get customHotkey => _customHotkey;
  bool get reconnectToLastServer => _reconnectToLastServer;
  String? get lastServerJson => _lastServerJson;
  String? get captureDeviceId => _captureDeviceId;
  String? get playbackDeviceId => _playbackDeviceId;
  double get inputGain => _inputGain;
  double get outputVolume => _outputVolume;
  bool get ignoreAccessibility => _ignoreAccessibility;
  bool get showVolumeIndicator => _showVolumeIndicator;
  int get outgoingAudioBitrate => _outgoingAudioBitrate;
  int get outgoingAudioMsPerPacket => _outgoingAudioMsPerPacket;
  int get incomingJitterBufferMs => _incomingJitterBufferMs;
  int get playbackHwBufferMs => _playbackHwBufferMs;
  bool get rememberLastChannel => _rememberLastChannel;
  bool get hideEmptyChannels => _hideEmptyChannels;
  int get pttHoldMs => _pttHoldMs;
  int get pttStartDelayMs => _pttStartDelayMs;
  int get transmissionMode => _transmissionMode;
  int get vadMethod => _vadMethod;
  double get vadThreshold => _vadThreshold;
  bool get showChat => _showChat;
  bool get echoCancellation => _echoCancellation;
  bool get noiseSuppression => _noiseSuppression;
  bool get automaticGainControl => _automaticGainControl;
  bool get showFloatingOverlay => _showFloatingOverlay;
  List<Map<String, dynamic>> get hotkeyBindings => List.unmodifiable(_hotkeyBindings);
  Map<String, double> get userVolumes => Map.unmodifiable(_userVolumes);
  Set<String> get localMutedUsers => Set.unmodifiable(_localMutedUsers);

  double? get windowWidth => _prefs.getDouble(_kWindowWidth);
  double? get windowHeight => _prefs.getDouble(_kWindowHeight);
  double? get windowX => _prefs.getDouble(_kWindowX);
  double? get windowY => _prefs.getDouble(_kWindowY);

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setPttKey(PttKey key) async {
    _pttKey = key;
    await _prefs.setInt(_kPttKey, key.index);
    if (key != PttKey.none) {
      _customHotkey = null; // Clear custom when preset is chosen
      await _prefs.remove(_kCustomHotkey);
    }
    notifyListeners();
  }

  Future<void> setPttSuppress(bool suppress) async {
    _pttSuppress = suppress;
    await _prefs.setBool(_kPttSuppress, suppress);
    notifyListeners();
  }

  Future<void> setCustomHotkey(Map<String, dynamic>? hotkey) async {
    _customHotkey = hotkey;
    if (hotkey != null) {
      _pttKey = PttKey.none; // Clear preset when custom is chosen
      await _prefs.setInt(_kPttKey, PttKey.none.index);
      await _prefs.setString(
        _kCustomHotkey,
        Uri(
          queryParameters: hotkey.map((k, v) => MapEntry(k, v.toString())),
        ).query,
      );
    } else {
      await _prefs.remove(_kCustomHotkey);
    }
    notifyListeners();
  }

  Future<void> addHotkeyBinding(Map<String, dynamic> hotkey) async {
    // Default to suppressing if not specified
    if (!hotkey.containsKey('suppress')) {
      hotkey['suppress'] = true;
    }
    _hotkeyBindings.add(hotkey);
    await _saveHotkeyBindings();
    notifyListeners();
  }

  Future<void> updateHotkeyBinding(int index, Map<String, dynamic> binding) async {
    if (index >= 0 && index < _hotkeyBindings.length) {
      _hotkeyBindings[index] = binding;
      await _saveHotkeyBindings();
      notifyListeners();
    }
  }

  Future<void> removeHotkeyBinding(int index) async {
    if (index >= 0 && index < _hotkeyBindings.length) {
      _hotkeyBindings.removeAt(index);
      await _saveHotkeyBindings();
      notifyListeners();
    }
  }

  Future<void> _saveHotkeyBindings() async {
    final List<String> bindingsJson = _hotkeyBindings
        .map((b) => jsonEncode(b))
        .toList();
    await _prefs.setStringList(_kHotkeyBindings, bindingsJson);
  }

  Future<void> setWindowSize(Size size) async {
    await _prefs.setDouble(_kWindowWidth, size.width);
    await _prefs.setDouble(_kWindowHeight, size.height);
  }

  Future<void> setWindowPosition(Offset position) async {
    await _prefs.setDouble(_kWindowX, position.dx);
    await _prefs.setDouble(_kWindowY, position.dy);
  }

  Future<void> setReconnectToLastServer(bool value) async {
    _reconnectToLastServer = value;
    await _prefs.setBool(_kReconnectToLastServer, value);
    notifyListeners();
  }

  Future<void> setLastServerJson(String? json) async {
    _lastServerJson = json;
    if (json != null) {
      await _prefs.setString(_kLastServerJson, json);
    } else {
      await _prefs.remove(_kLastServerJson);
    }
    notifyListeners();
  }

  Future<void> setCaptureDeviceId(String? id) async {
    _captureDeviceId = id;
    if (id != null) {
      await _prefs.setString(_kCaptureDeviceId, id);
    } else {
      await _prefs.remove(_kCaptureDeviceId);
    }
    notifyListeners();
  }

  Future<void> setPlaybackDeviceId(String? id) async {
    _playbackDeviceId = id;
    if (id != null) {
      await _prefs.setString(_kPlaybackDeviceId, id);
    } else {
      await _prefs.remove(_kPlaybackDeviceId);
    }
    notifyListeners();
  }

  Future<void> setInputGain(double gain) async {
    _inputGain = gain;
    await _prefs.setDouble(_kInputGain, gain);
    notifyListeners();
  }

  Future<void> setOutputVolume(double volume) async {
    _outputVolume = volume;
    await _prefs.setDouble(_kOutputVolume, volume);
    notifyListeners();
  }

  Future<void> setIgnoreAccessibility(bool value) async {
    _ignoreAccessibility = value;
    await _prefs.setBool(_kIgnoreAccessibility, value);
    notifyListeners();
  }

  Future<void> setShowVolumeIndicator(bool value) async {
    _showVolumeIndicator = value;
    await _prefs.setBool(_kShowVolumeIndicator, value);
    notifyListeners();
  }

  Future<void> setUserVolume(String name, double volume) async {
    _userVolumes[name] = volume;
    final List<String> userVols = _userVolumes.entries
        .map((e) => '${Uri.encodeComponent(e.key)}:${e.value}')
        .toList();
    await _prefs.setStringList(_kUserVolumes, userVols);
    notifyListeners();
  }

  Future<void> setLocalMute(String name, bool muted) async {
    if (muted) {
      _localMutedUsers.add(name);
    } else {
      _localMutedUsers.remove(name);
    }
    await _prefs.setStringList(_kLocalMutedUsers, _localMutedUsers.toList());
    notifyListeners();
  }

  bool isLocalMuted(String name) {
    return _localMutedUsers.contains(name);
  }

  double getUserVolume(String name) {
    return _userVolumes[name] ?? 1.0;
  }

  Future<void> setOutgoingAudioBitrate(int bitrate) async {
    _outgoingAudioBitrate = bitrate;
    await _prefs.setInt(_kOutgoingAudioBitrate, bitrate);
    notifyListeners();
  }

  Future<void> setOutgoingAudioMsPerPacket(int frameMs) async {
    _outgoingAudioMsPerPacket = frameMs;
    await _prefs.setInt(_kOutgoingAudioMsPerPacket, frameMs);
    notifyListeners();
  }

  Future<void> setIncomingJitterBufferMs(int ms) async {
    _incomingJitterBufferMs = ms;
    await _prefs.setInt(_kIncomingJitterBufferMs, ms);
    notifyListeners();
  }

  Future<void> setPlaybackHwBufferMs(int ms) async {
    _playbackHwBufferMs = ms;
    await _prefs.setInt(_kPlaybackHwBufferMs, ms);
    notifyListeners();
  }
  
  Future<void> setRememberLastChannel(bool value) async {
    _rememberLastChannel = value;
    await _prefs.setBool(_kRememberLastChannel, value);
    notifyListeners();
  }

  Future<void> setHideEmptyChannels(bool value) async {
    _hideEmptyChannels = value;
    await _prefs.setBool(_kHideEmptyChannels, value);
    notifyListeners();
  }

  Future<void> setPttHoldMs(int ms) async {
    _pttHoldMs = ms;
    await _prefs.setInt(_kPttHoldMs, ms);
    notifyListeners();
  }

  Future<void> setPtStartDelayMs(int ms) async {
    _pttStartDelayMs = ms;
    await _prefs.setInt(_kPtStartDelayMs, ms);
    notifyListeners();
  }

  Future<void> setTransmissionMode(int mode) async {
    _transmissionMode = mode;
    await _prefs.setInt(_kTransmissionMode, mode);
    notifyListeners();
  }

  Future<void> setVadMethod(int method) async {
    _vadMethod = method;
    await _prefs.setInt(_kVadMethod, method);
    notifyListeners();
  }

  Future<void> setVadThreshold(double threshold) async {
    _vadThreshold = threshold;
    await _prefs.setDouble(_kVadThreshold, threshold);
    notifyListeners();
  }

  Future<void> setShowChat(bool value) async {
    _showChat = value;
    await _prefs.setBool(_kShowChat, value);
  Future<void> setEchoCancellation(bool enabled) async {
    _echoCancellation = enabled;
    await _prefs.setBool(_kEchoCancellation, enabled);
    notifyListeners();
  }

  Future<void> setNoiseSuppression(bool enabled) async {
    _noiseSuppression = enabled;
    await _prefs.setBool(_kNoiseSuppression, enabled);
    notifyListeners();
  }

  Future<void> setAutomaticGainControl(bool enabled) async {
    _automaticGainControl = enabled;
    await _prefs.setBool(_kAutomaticGainControl, enabled);
    notifyListeners();
  }

  Future<void> setShowFloatingOverlay(bool enabled) async {
    _showFloatingOverlay = enabled;
    await _prefs.setBool(_kShowFloatingOverlay, enabled);
    notifyListeners();
  }
}
