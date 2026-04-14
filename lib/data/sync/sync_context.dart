class SyncContext {
  const SyncContext({
    required this.userId,
    required this.deviceId,
    required this.organizationId,
  });

  final String userId;
  final String deviceId;
  final String organizationId;

  bool get isValid =>
      userId.isNotEmpty &&
      deviceId.isNotEmpty &&
      organizationId.isNotEmpty;

  static const empty = SyncContext(
    userId: '',
    deviceId: '',
    organizationId: '',
  );
}
