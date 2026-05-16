import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LocalPreferences {
  LocalPreferences(this._prefs);

  final SharedPreferences _prefs;

  // ---- Identity ----

  String get userId => _prefs.getString('userId') ?? '';
  Future<void> setUserId(String value) => _prefs.setString('userId', value);

  String get deviceId => _prefs.getString('deviceId') ?? '';

  String get organizationId => _prefs.getString('organizationId') ?? '';
  Future<void> setOrganizationId(String value) =>
      _prefs.setString('organizationId', value);

  // ---- Bootstrap ----

  String _bootstrapKey(String organizationId) =>
      'bootstrapComplete_$organizationId';

  bool bootstrapCompleteFor(String organizationId) {
    if (organizationId.isEmpty) return false;
    return _prefs.getBool(_bootstrapKey(organizationId)) ?? false;
  }

  Future<void> setBootstrapCompleteFor(
    String organizationId,
    bool value,
  ) async {
    if (organizationId.isEmpty) return;
    await _prefs.setBool(_bootstrapKey(organizationId), value);
  }

  Future<void> clearBootstrapCompleteFor(String organizationId) async {
    if (organizationId.isEmpty) return;
    await _prefs.remove(_bootstrapKey(organizationId));
  }

  // ---- Pull sync (future use) ----

  DateTime? lastPulledAt(String entityType) {
    final raw = _prefs.getString('lastPulledAt_$entityType');
    return raw != null ? DateTime.parse(raw) : null;
  }

  Future<void> setLastPulledAt(String entityType, DateTime time) =>
      _prefs.setString('lastPulledAt_$entityType', time.toIso8601String());

  // ---- Device ID (generated once) ----

  Future<void> ensureDeviceId(Uuid uuid) async {
    if (_prefs.getString('deviceId') == null) {
      await _prefs.setString('deviceId', uuid.v4());
    }
  }

  // ---- Clear (for sign out) ----

  Future<void> clearSession() async {
    final currentOrganizationId = organizationId;
    await _prefs.remove('userId');
    await _prefs.remove('organizationId');
    await clearBootstrapCompleteFor(currentOrganizationId);
  }
}
