/// Retains the most recent tap until the correct account's home is ready.
/// No notification contents are persisted to disk.
class NotificationTapInbox {
  Map<String, dynamic>? _pending;
  void Function(Map<String, dynamic>)? _handler;

  void receive(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.unmodifiable(data);
    final handler = _handler;
    if (handler == null) {
      _pending = copy;
    } else {
      handler(copy);
    }
  }

  void attach(void Function(Map<String, dynamic>) handler) {
    _handler = handler;
    final pending = _pending;
    _pending = null;
    if (pending != null) handler(pending);
  }

  void detach() => _handler = null;
  void clearPending() => _pending = null;
  void retainForAccount(String? uid) {
    if (uid == null ||
        (_pending?['recipientUid'] != null &&
            _pending!['recipientUid'] != uid)) {
      _pending = null;
    }
  }

  void clear() {
    _pending = null;
    _handler = null;
  }
}
