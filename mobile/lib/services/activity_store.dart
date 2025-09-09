import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity.dart';
import 'dart:async';

class ActivityStore {
  static const _key = 'pqcwallet/activityFeed/v1';
  final _controller = StreamController<List<ActivityItem>>.broadcast();
  List<ActivityItem> _items = [];

  Stream<List<ActivityItem>> get stream => _controller.stream;
  List<ActivityItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_key);
    _items = s == null ? [] : ActivityItem.decodeList(s);
    _controller.add(items);
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, ActivityItem.encodeList(_items));
    _controller.add(items);
  }

  Future<void> add(ActivityItem item) async {
    _items.insert(0, item);
    if (_items.length > 200) _items.removeRange(200, _items.length);
    await _save();
  }

  Future<void> upsertByUserOpHash(String userOpHash,
      ActivityItem Function(ActivityItem?) mutate) async {
    final idx = _items.indexWhere(
        (e) => e.userOpHash.toLowerCase() == userOpHash.toLowerCase());
    final existing = idx >= 0 ? _items[idx] : null;
    final next = mutate(existing);
    if (idx >= 0) {
      _items[idx] = next;
    } else {
      _items.insert(0, next);
    }
    await _save();
  }

  Future<void> setStatus(String userOpHash, ActivityStatus status,
      {String? txHash}) async {
    final idx = _items.indexWhere(
        (e) => e.userOpHash.toLowerCase() == userOpHash.toLowerCase());
    if (idx < 0) return;
    _items[idx] =
        _items[idx].copyWith(status: status, txHash: txHash ?? _items[idx].txHash);
    await _save();
  }
}
