enum SyncOpType { createLog, updateLog, deleteLog, createAttachment }

class SyncOperation {
  final String opId;
  final SyncOpType type;
  final Map<String, dynamic> payload;
  final String? localFilePath;
  final DateTime createdAt;
  final String? error;

  const SyncOperation({
    required this.opId,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.localFilePath,
    this.error,
  });

  String get logId {
    if (type == SyncOpType.createAttachment) {
      return payload["log_id"]?.toString() ?? "";
    }
    return payload["id"]?.toString() ?? "";
  }

  SyncOperation copyWith({String? error}) => SyncOperation(
        opId: opId,
        type: type,
        payload: payload,
        createdAt: createdAt,
        localFilePath: localFilePath,
        error: error ?? this.error,
      );

  Map<String, dynamic> toJson() => {
        "opId": opId,
        "type": type.name,
        "payload": payload,
        "localFilePath": localFilePath,
        "createdAt": createdAt.toUtc().toIso8601String(),
        "error": error,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        opId: json["opId"] as String,
        type: SyncOpType.values.firstWhere((t) => t.name == json["type"]),
        payload: Map<String, dynamic>.from(json["payload"] as Map),
        localFilePath: json["localFilePath"] as String?,
        createdAt:
            DateTime.tryParse(json["createdAt"]?.toString() ?? "")?.toUtc() ??
                DateTime.now().toUtc(),
        error: json["error"] as String?,
      );
}
