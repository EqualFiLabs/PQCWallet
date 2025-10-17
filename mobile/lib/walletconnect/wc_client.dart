import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:reown_walletkit/reown_walletkit.dart';

import 'ui/wc_sessions_screen.dart';
import 'wc_session_store.dart';

class WcClient extends ChangeNotifier {
  WcClient({
    required WcSessionStore sessionStore,
    required GlobalKey<NavigatorState> navigatorKey,
    ReownWalletKit? walletKit,
  })  : _sessionStore = sessionStore,
        _navigatorKey = navigatorKey,
        _walletKit = walletKit;

  final WcSessionStore _sessionStore;
  final GlobalKey<NavigatorState> _navigatorKey;

  ReownWalletKit? _walletKit;
  bool _initializing = false;
  bool _initialized = false;
  bool _listenersAttached = false;

  final Map<String, SessionData> _sessions = <String, SessionData>{};
  final Map<String, WcSessionSummary> _summaries =
      <String, WcSessionSummary>{};
  final Map<int, ProposalData> _pendingProposals = <int, ProposalData>{};
  final Map<int, SessionRequestEvent> _pendingRequests =
      <int, SessionRequestEvent>{};

  void Function(SessionProposalEvent)? _proposalHandler;
  void Function(SessionProposalErrorEvent)? _proposalErrorHandler;
  void Function(SessionProposalEvent)? _proposalExpireHandler;
  void Function(SessionRequestEvent)? _requestHandler;
  void Function(SessionDelete)? _sessionDeleteHandler;
  void Function(SessionExpire)? _sessionExpireHandler;
  void Function(SessionConnect)? _sessionConnectHandler;
  void Function(StoreUpdateEvent<SessionData>)? _sessionUpdateHandler;
  void Function(StoreDeleteEvent<SessionData>)? _sessionStoreDeleteHandler;
  void Function(StoreDeleteEvent<SessionRequest>)? _pendingRequestDeleteHandler;

  bool get isInitializing => _initializing;
  bool get isInitialized => _initialized;
  bool get isAvailable => _walletKit != null;

  ReownWalletKit? get walletKit => _walletKit;

  NavigatorState? get navigator => _navigatorKey.currentState;
  BuildContext? get navigationContext => _navigatorKey.currentContext;

  UnmodifiableMapView<String, SessionData> get sessions =>
      UnmodifiableMapView<String, SessionData>(_sessions);

  List<WcSessionSummary> get sessionSummaries =>
      _summaries.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  UnmodifiableMapView<int, ProposalData> get pendingProposals =>
      UnmodifiableMapView<int, ProposalData>(_pendingProposals);

  UnmodifiableMapView<int, SessionRequestEvent> get pendingRequests =>
      UnmodifiableMapView<int, SessionRequestEvent>(_pendingRequests);

  Future<void> init({
    required String? projectId,
    required PairingMetadata metadata,
    String? relayUrl,
    String? pushUrl,
    LogLevel logLevel = LogLevel.nothing,
  }) async {
    if (_initialized || _initializing) {
      return;
    }
    if (projectId == null || projectId.isEmpty) {
      _log('WalletConnect disabled: missing project ID.');
      return;
    }

    _initializing = true;
    notifyListeners();
    try {
      _walletKit ??= await ReownWalletKit.createInstance(
        projectId: projectId,
        metadata: metadata,
        relayUrl: relayUrl ?? ReownConstants.DEFAULT_RELAY_URL,
        pushUrl: pushUrl ?? ReownConstants.DEFAULT_PUSH_URL,
        logLevel: logLevel,
      );

      await _restorePersistedSessions();
      _restoreWalletKitState();
      _attachListeners();
      _initialized = true;
      notifyListeners();
    } catch (e, st) {
      _log('Failed to initialize WalletConnect: $e\n$st');
      rethrow;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<PairingInfo> pair(Uri uri) async {
    final kit = _requireKit();
    _log('Pairing with ${uri.toString()}');
    return kit.pair(uri: uri);
  }

  Future<ApproveResponse> approve({
    required int id,
    required Map<String, Namespace> namespaces,
    Map<String, String>? sessionProperties,
    String? relayProtocol,
  }) async {
    final kit = _requireKit();
    final result = await kit.approveSession(
      id: id,
      namespaces: namespaces,
      sessionProperties: sessionProperties,
      relayProtocol: relayProtocol,
    );
    if (_pendingProposals.remove(id) != null) {
      notifyListeners();
    }
    return result;
  }

  Future<void> reject({
    required int id,
    ReownSignError reason = const ReownSignError(
      code: 5000,
      message: 'User rejected the proposal',
    ),
  }) async {
    final kit = _requireKit();
    await kit.rejectSession(id: id, reason: reason);
    if (_pendingProposals.remove(id) != null) {
      notifyListeners();
    }
  }

  Future<void> disconnect({
    required String topic,
    ReownSignError reason = const ReownSignError(
      code: 6000,
      message: 'User disconnected session',
    ),
  }) async {
    final kit = _requireKit();
    await kit.disconnectSession(topic: topic, reason: reason);
    await _sessionStore
        .clearSession(topic)
        .catchError((Object err, StackTrace st) {
      _log('Failed clearing persisted WalletConnect session: $err\n$st');
    });
  }

  Future<void> respond({
    required String topic,
    required JsonRpcResponse response,
  }) async {
    final kit = _requireKit();
    await kit.respondSessionRequest(topic: topic, response: response);
    final responseId = response.id;
    if (responseId is int && _pendingRequests.remove(responseId) != null) {
      notifyListeners();
    }
  }

  Future<void> openSessionsScreen() async {
    final nav = navigator;
    if (nav == null) {
      _log('Navigator not ready for WalletConnect sessions route.');
      return;
    }
    await nav.pushNamed(WcSessionsScreen.routeName);
  }

  @override
  void dispose() {
    _detachListeners();
    super.dispose();
  }

  ReownWalletKit _requireKit() {
    final kit = _walletKit;
    if (kit == null) {
      throw StateError('WalletConnect client not initialized');
    }
    return kit;
  }

  Future<void> _restorePersistedSessions() async {
    final stored = await _sessionStore.loadSessions();
    _summaries
      ..clear()
      ..addEntries(stored.entries.map((entry) {
        final value = entry.value;
        if (value case final Map<String, Object?> data) {
          final summary = WcSessionSummary.fromJson(
            Map<String, Object?>.from(data),
          );
          if (summary != null) {
            return MapEntry(entry.key, summary);
          }
        }
        return null;
      }).whereType<MapEntry<String, WcSessionSummary>>());
  }

  void _restoreWalletKitState() {
    final kit = _walletKit;
    if (kit == null) {
      return;
    }

    _sessions
      ..clear()
      ..addEntries(kit.sessions
          .getAll()
          .map((session) => MapEntry(session.topic, session)));

    for (final session in _sessions.values) {
      final summary = WcSessionSummary.fromSession(session);
      _summaries[session.topic] = summary;
      _sessionStore
          .persistSession(session.topic, summary.toJson())
          .catchError((Object err, StackTrace st) {
        _log('Failed persisting WalletConnect session: $err\n$st');
      });
    }

    _pendingProposals
      ..clear()
      ..addEntries(kit.proposals
          .getAll()
          .map((proposal) => MapEntry(proposal.id, proposal)));

    _pendingRequests
      ..clear()
      ..addEntries(kit.pendingRequests.getAll().map((request) => MapEntry(
            request.id,
            SessionRequestEvent.fromSessionRequest(request),
          )));
  }

  void _attachListeners() {
    if (_listenersAttached) {
      return;
    }
    final kit = _walletKit;
    if (kit == null) {
      return;
    }

    _proposalHandler = (event) {
      _pendingProposals[event.id] = event.params;
      notifyListeners();
    };
    kit.onSessionProposal.subscribe(_proposalHandler!);

    _proposalErrorHandler = (event) {
      if (_pendingProposals.remove(event.id) != null) {
        notifyListeners();
      }
    };
    kit.onSessionProposalError.subscribe(_proposalErrorHandler!);

    _proposalExpireHandler = (event) {
      if (_pendingProposals.remove(event.id) != null) {
        notifyListeners();
      }
    };
    kit.onProposalExpire.subscribe(_proposalExpireHandler!);

    _requestHandler = (event) {
      _pendingRequests[event.id] = event;
      notifyListeners();
    };
    kit.onSessionRequest.subscribe(_requestHandler!);

    _sessionConnectHandler = (event) {
      final session = event.session;
      _sessions[session.topic] = session;
      final summary = WcSessionSummary.fromSession(session);
      _summaries[session.topic] = summary;
      _sessionStore
          .persistSession(session.topic, summary.toJson())
          .catchError((Object err, StackTrace st) {
        _log('Failed persisting WalletConnect session: $err\n$st');
      });
      notifyListeners();
    };
    kit.onSessionConnect.subscribe(_sessionConnectHandler!);

    _sessionDeleteHandler = (event) {
      final removed = _sessions.remove(event.topic);
      if (removed != null) {
        _summaries.remove(event.topic);
        _sessionStore
            .clearSession(event.topic)
            .catchError((Object err, StackTrace st) {
          _log('Failed clearing WalletConnect session: $err\n$st');
        });
        notifyListeners();
      }
    };
    kit.onSessionDelete.subscribe(_sessionDeleteHandler!);

    _sessionExpireHandler = (event) {
      if (_sessions.remove(event.topic) != null) {
        _summaries.remove(event.topic);
        _sessionStore
            .clearSession(event.topic)
            .catchError((Object err, StackTrace st) {
          _log('Failed clearing expired WalletConnect session: $err\n$st');
        });
        notifyListeners();
      }
    };
    kit.onSessionExpire.subscribe(_sessionExpireHandler!);

    _sessionUpdateHandler = (event) {
      final session = event.value;
      _sessions[session.topic] = session;
      final summary = WcSessionSummary.fromSession(session);
      _summaries[session.topic] = summary;
      _sessionStore
          .persistSession(session.topic, summary.toJson())
          .catchError((Object err, StackTrace st) {
        _log('Failed updating WalletConnect session: $err\n$st');
      });
      notifyListeners();
    };
    kit.sessions.onUpdate.subscribe(_sessionUpdateHandler!);

    _sessionStoreDeleteHandler = (event) {
      if (_sessions.remove(event.key) != null) {
        _summaries.remove(event.key);
        notifyListeners();
      }
    };
    kit.sessions.onDelete.subscribe(_sessionStoreDeleteHandler!);

    _pendingRequestDeleteHandler = (event) {
      if (_pendingRequests.remove(event.value.id) != null) {
        notifyListeners();
      }
    };
    kit.pendingRequests.onDelete.subscribe(_pendingRequestDeleteHandler!);

    _listenersAttached = true;
  }

  void _detachListeners() {
    if (!_listenersAttached) {
      return;
    }
    final kit = _walletKit;
    if (kit == null) {
      return;
    }

    if (_proposalHandler != null) {
      kit.onSessionProposal.unsubscribe(_proposalHandler!);
      _proposalHandler = null;
    }
    if (_proposalErrorHandler != null) {
      kit.onSessionProposalError.unsubscribe(_proposalErrorHandler!);
      _proposalErrorHandler = null;
    }
    if (_proposalExpireHandler != null) {
      kit.onProposalExpire.unsubscribe(_proposalExpireHandler!);
      _proposalExpireHandler = null;
    }
    if (_requestHandler != null) {
      kit.onSessionRequest.unsubscribe(_requestHandler!);
      _requestHandler = null;
    }
    if (_sessionConnectHandler != null) {
      kit.onSessionConnect.unsubscribe(_sessionConnectHandler!);
      _sessionConnectHandler = null;
    }
    if (_sessionDeleteHandler != null) {
      kit.onSessionDelete.unsubscribe(_sessionDeleteHandler!);
      _sessionDeleteHandler = null;
    }
    if (_sessionExpireHandler != null) {
      kit.onSessionExpire.unsubscribe(_sessionExpireHandler!);
      _sessionExpireHandler = null;
    }
    if (_sessionUpdateHandler != null) {
      kit.sessions.onUpdate.unsubscribe(_sessionUpdateHandler!);
      _sessionUpdateHandler = null;
    }
    if (_sessionStoreDeleteHandler != null) {
      kit.sessions.onDelete.unsubscribe(_sessionStoreDeleteHandler!);
      _sessionStoreDeleteHandler = null;
    }
    if (_pendingRequestDeleteHandler != null) {
      kit.pendingRequests.onDelete.unsubscribe(_pendingRequestDeleteHandler!);
      _pendingRequestDeleteHandler = null;
    }

    _listenersAttached = false;
  }

  void _log(String message) {
    debugPrint('[WalletConnect] $message');
  }
}

@immutable
class WcSessionSummary {
  const WcSessionSummary({
    required this.topic,
    required this.name,
    required this.description,
    required this.url,
    required this.icons,
    required this.accounts,
    required this.expiry,
  });

  final String topic;
  final String name;
  final String description;
  final String url;
  final List<String> icons;
  final List<String> accounts;
  final int expiry;

  bool get isExpired =>
      expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Map<String, Object?> toJson() => <String, Object?>{
        'topic': topic,
        'name': name,
        'description': description,
        'url': url,
        'icons': icons,
        'accounts': accounts,
        'expiry': expiry,
      };

  static WcSessionSummary? fromJson(Map<String, Object?> json) {
    final topic = json['topic'] as String?;
    final name = json['name'] as String?;
    final description = json['description'] as String? ?? '';
    final url = json['url'] as String? ?? '';
    final icons = _stringList(json['icons']);
    final accounts = _stringList(json['accounts']);
    final expiry = json['expiry'] as int?;

    if (topic == null || name == null || expiry == null) {
      return null;
    }

    return WcSessionSummary(
      topic: topic,
      name: name,
      description: description,
      url: url,
      icons: icons,
      accounts: accounts,
      expiry: expiry,
    );
  }

  factory WcSessionSummary.fromSession(SessionData session) {
    final peer = session.peer.metadata;
    final accounts = session.namespaces.values
        .expand((namespace) => namespace.accounts)
        .toSet()
        .toList()
      ..sort();
    return WcSessionSummary(
      topic: session.topic,
      name: peer.name,
      description: peer.description,
      url: peer.url,
      icons: List<String>.from(peer.icons),
      accounts: accounts,
      expiry: session.expiry,
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((dynamic v) => v.toString()).toList();
    }
    return <String>[];
  }
}
