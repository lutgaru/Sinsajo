import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ws_service.dart';
import 'transcription_provider.dart';

/// One entry from the server's model registry.
class ServerModelEntry {
  final String name;
  final String display;
  final String dir;
  final bool installed;
  final bool active;
  final int files;

  const ServerModelEntry({
    required this.name,
    required this.display,
    required this.dir,
    required this.installed,
    required this.active,
    required this.files,
  });

  factory ServerModelEntry.fromJson(Map<String, dynamic> json) =>
      ServerModelEntry(
        name: (json['name'] ?? '') as String,
        display: (json['display'] ?? json['name'] ?? '') as String,
        dir: (json['dir'] ?? '') as String,
        installed: json['installed'] == true,
        active: json['active'] == true,
        files: (json['files'] as num?)?.toInt() ?? 0,
      );
}

class ServerModelsState {
  final List<ServerModelEntry> models;
  final String? activeModel;
  final bool loading;
  final String? error;

  /// Current long-running action reported by the server.
  final String? action;
  final String? actionModel;
  final String? actionState;
  final String? actionMessage;

  /// Aggregate download progress for the whole model. The server reports
  /// bytes across every remaining file so the UI can show one bar.
  final String? downloadFile;
  final int downloadPercent;
  final int downloadedBytes;
  final int totalBytes;

  /// Exact overall completion (0..1) with every file weighted equally.
  final double downloadFraction;

  /// Files completed / total files in the current model download.
  final int downloadFilesDone;
  final int downloadFilesTotal;

  const ServerModelsState({
    this.models = const [],
    this.activeModel,
    this.loading = false,
    this.error,
    this.action,
    this.actionModel,
    this.actionState,
    this.actionMessage,
    this.downloadFile,
    this.downloadPercent = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadFraction = 0,
    this.downloadFilesDone = 0,
    this.downloadFilesTotal = 0,
  });

  bool get isBusy => actionState == 'started';

  bool get isDownloading => isBusy && action == 'download';

  ServerModelsState copyWith({
    List<ServerModelEntry>? models,
    String? activeModel,
    bool? loading,
    String? error,
    String? action,
    String? actionModel,
    String? actionState,
    String? actionMessage,
    String? downloadFile,
    int? downloadPercent,
    int? downloadedBytes,
    int? totalBytes,
    double? downloadFraction,
    int? downloadFilesDone,
    int? downloadFilesTotal,
    bool clearError = false,
    bool clearAction = false,
    bool clearActionMessage = false,
    bool clearDownload = false,
  }) {
    return ServerModelsState(
      models: models ?? this.models,
      activeModel: activeModel ?? this.activeModel,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      action: clearAction ? null : (action ?? this.action),
      actionModel: clearAction ? null : (actionModel ?? this.actionModel),
      actionState: clearAction ? null : (actionState ?? this.actionState),
      actionMessage: (clearAction || clearActionMessage)
          ? null
          : (actionMessage ?? this.actionMessage),
      downloadFile: (clearAction || clearDownload)
          ? null
          : (downloadFile ?? this.downloadFile),
      downloadPercent: (clearAction || clearDownload)
          ? 0
          : (downloadPercent ?? this.downloadPercent),
      downloadedBytes: (clearAction || clearDownload)
          ? 0
          : (downloadedBytes ?? this.downloadedBytes),
      totalBytes: (clearAction || clearDownload)
          ? 0
          : (totalBytes ?? this.totalBytes),
      downloadFraction: (clearAction || clearDownload)
          ? 0
          : (downloadFraction ?? this.downloadFraction),
      downloadFilesDone: (clearAction || clearDownload)
          ? 0
          : (downloadFilesDone ?? this.downloadFilesDone),
      downloadFilesTotal: (clearAction || clearDownload)
          ? 0
          : (downloadFilesTotal ?? this.downloadFilesTotal),
    );
  }
}

/// Talks to the server's model-manager commands over the shared WebSocket.
class ServerModelsNotifier extends Notifier<ServerModelsState> {
  WsService? _ws;
  StreamSubscription<WsMessage>? _messageSub;
  StreamSubscription<WsStatus>? _statusSub;
  Timer? _refreshTimeout;

  @override
  ServerModelsState build() {
    final ws = ref.read(transcriptionProvider.notifier).ws;
    _ws = ws;
    _messageSub = ws.messageStream.listen(_onMessage);
    _statusSub = ws.statusStream.listen(_onStatus);

    // If the socket was already connected before this provider was created,
    // the connection event is in the past: ask for the list once.
    scheduleMicrotask(_refreshIfConnected);

    ref.onDispose(() {
      _refreshTimeout?.cancel();
      _refreshTimeout = null;
      _messageSub?.cancel();
      _statusSub?.cancel();
    });

    return const ServerModelsState();
  }

  bool _ensureConnected() {
    final ws = _ws;
    if (ws == null || ws.status != WsStatus.connected) {
      state = state.copyWith(
        error: 'Not connected to the server. Check the IP address and retry.',
        loading: false,
      );
      return false;
    }
    return true;
  }

  void _refreshIfConnected() {
    if (_ws?.status == WsStatus.connected) {
      _requestList();
    }
  }

  void _requestList() {
    if (!_ensureConnected()) return;
    _refreshTimeout?.cancel();
    state = state.copyWith(loading: true, clearError: true);
    _ws!.requestModelList();
    _refreshTimeout = Timer(const Duration(seconds: 10), () {
      if (!ref.mounted || !state.loading) return;
      state = state.copyWith(
        loading: false,
        error: 'The server did not answer the model list request.',
      );
    });
  }

  /// User-initiated refresh (button). Shows an error if offline.
  void refresh() => _requestList();

  /// Dismisses the last action result banner.
  void clearStatus() {
    state = state.copyWith(clearAction: true, clearError: true);
  }

  void downloadModel(String name) {
    if (!_ensureConnected()) return;
    state = state.copyWith(
      action: 'download',
      actionModel: name,
      actionState: 'started',
      clearActionMessage: true,
      clearDownload: true,
      clearError: true,
    );
    _ws!.downloadModel(name);
  }

  void loadModel(String name) {
    if (!_ensureConnected()) return;
    state = state.copyWith(
      action: 'load',
      actionModel: name,
      actionState: 'started',
      clearActionMessage: true,
      clearDownload: true,
      clearError: true,
    );
    _ws!.loadModel(name);
  }

  void deleteModel(String name) {
    if (!_ensureConnected()) return;
    state = state.copyWith(
      action: 'delete',
      actionModel: name,
      actionState: 'started',
      clearActionMessage: true,
      clearDownload: true,
      clearError: true,
    );
    _ws!.deleteModel(name);
  }

  void _onStatus(WsStatus status) {
    if (status == WsStatus.connected) {
      _refreshIfConnected();
    } else if (state.loading) {
      _refreshTimeout?.cancel();
      state = state.copyWith(
        loading: false,
        error: 'Connection to the server was lost.',
      );
    }
  }

  void _onMessage(WsMessage msg) {
    switch (msg.type) {
      case 'model_list':
        _applyModelList(msg.data);
        break;
      case 'model_info':
        if (msg.model != null) {
          state = state.copyWith(activeModel: msg.model);
        }
        break;
      case 'model_action':
        _applyAction(msg.data);
        break;
      case 'model_download_progress':
        _applyDownloadProgress(msg.data);
        break;
    }
  }

  void _applyModelList(Map<String, dynamic> data) {
    _refreshTimeout?.cancel();
    _refreshTimeout = null;

    final rawModels = (data['models'] as List?) ?? const [];
    final models = rawModels
        .whereType<Map>()
        .map((e) => ServerModelEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    state = state.copyWith(
      models: models,
      activeModel: (data['active'] as String?) ?? state.activeModel,
      loading: false,
      clearError: true,
    );
  }

  void _applyAction(Map<String, dynamic> data) {
    final action = (data['action'] as String?) ?? '';
    final model = (data['model'] as String?) ?? '';
    final phase = (data['state'] as String?) ?? '';
    final message = data['message'] as String?;

    state = state.copyWith(
      action: action,
      actionModel: model,
      actionState: phase,
      actionMessage: message,
      clearActionMessage: message == null && phase == 'started',
      clearDownload: phase == 'started',
      error: phase == 'failed' && message != null ? message : state.error,
    );
  }

  void _applyDownloadProgress(Map<String, dynamic> data) {
    final fraction = downloadFractionFromProgress(data);
    state = state.copyWith(
      downloadFile: (data['file'] as String?) ?? state.downloadFile,
      downloadPercent: (fraction * 100).round(),
      downloadedBytes: (data['downloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (data['total'] as num?)?.toInt() ?? 0,
      downloadFraction: fraction,
      downloadFilesDone: (data['files_done'] as num?)?.toInt() ?? 0,
      downloadFilesTotal: (data['files_total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Overall completion (0..1) from a `model_download_progress` payload.
///
/// Every file owns an equal slice of the bar, so the value is
/// `(files_done + current_file_fraction) / files_total`. `file_complete` marks
/// the last snapshot of a file before the next one starts: without it the
/// completed file would be counted twice and the bar would jump backwards.
///
/// Older servers only sent a per-file `percent`, which is used as a fallback.
double downloadFractionFromProgress(Map<String, dynamic> data) {
  final filesTotal = (data['files_total'] as num?)?.toInt() ?? 0;
  if (filesTotal <= 0) {
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final downloaded = (data['downloaded'] as num?)?.toInt() ?? 0;
    final percent =
        (data['percent'] as num?)?.toInt() ??
        (total > 0 ? (downloaded * 100 ~/ total) : 0);
    return (percent / 100).clamp(0.0, 1.0).toDouble();
  }

  final filesDone = (data['files_done'] as num?)?.toInt() ?? 0;
  final fileDownloaded = (data['file_downloaded'] as num?)?.toInt() ?? 0;
  final fileTotal = (data['file_total'] as num?)?.toInt() ?? 0;
  final fileComplete = data['file_complete'] == true;
  final fileFraction = fileComplete
      ? 1.0
      : (fileTotal > 0
            ? (fileDownloaded / fileTotal).clamp(0.0, 1.0).toDouble()
            : 0.0);
  return ((filesDone + fileFraction) / filesTotal)
      .clamp(0.0, 1.0)
      .toDouble();
}

final serverModelsProvider =
    NotifierProvider<ServerModelsNotifier, ServerModelsState>(
      ServerModelsNotifier.new,
    );
