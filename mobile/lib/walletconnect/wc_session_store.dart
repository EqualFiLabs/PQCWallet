class WcSessionStore {
  const WcSessionStore();

  Future<void> persistSession(String topic, Map<String, Object?> data) async {
    await Future<void>.value();
  }

  Future<void> clearSession(String topic) async {
    await Future<void>.value();
  }
}
