enum EngineeringLogType {
  bug("BUG"),
  feature("FEATURE"),
  research("RESEARCH"),
  note("NOTE");

  const EngineeringLogType(this.value);

  final String value;

  static EngineeringLogType fromValue(String? value) {
    return EngineeringLogType.values.firstWhere(
      (type) => type.value == value?.toUpperCase(),
      orElse: () => EngineeringLogType.bug,
    );
  }
}

enum Severity {
  low("LOW"),
  medium("MEDIUM"),
  high("HIGH"),
  critical("CRITICAL");

  const Severity(this.value);

  final String value;

  static Severity fromValue(String? value) {
    return Severity.values.firstWhere(
      (severity) => severity.value == value?.toUpperCase(),
      orElse: () => Severity.medium,
    );
  }
}

enum SyncStatus {
  local("LOCAL"),
  synced("SYNCED"),
  closed("CLOSED");

  const SyncStatus(this.value);

  final String value;

  static SyncStatus fromValue(String? value) {
    return SyncStatus.values.firstWhere(
      (status) => status.value == value?.toUpperCase(),
      orElse: () => SyncStatus.local,
    );
  }
}

class EngineeringLog {
  final String? id;
  final String repoId;
  final String userId;
  final String title;
  final String description;
  final EngineeringLogType type;
  final Severity severity;
  final String environment;
  final List<String> labels;
  final SyncStatus syncStatus;
  final int? githubIssueNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EngineeringLog({
    this.id,
    required this.repoId,
    required this.userId,
    required this.title,
    required this.description,
    required this.type,
    required this.severity,
    required this.environment,
    required this.labels,
    this.syncStatus = SyncStatus.local,
    this.githubIssueNumber,
    this.createdAt,
    this.updatedAt,
  });

  bool get isSynced => syncStatus != SyncStatus.local;

  bool get isClosed => syncStatus == SyncStatus.closed;

  factory EngineeringLog.fromJson(Map<String, dynamic> json) {
    return EngineeringLog(
      id: json["id"] as String?,
      repoId: json["repo_id"] as String? ?? "",
      userId: json["user_id"] as String? ?? "",
      title: json["title"] as String? ?? "",
      description: json["description"] as String? ?? "",
      type: EngineeringLogType.fromValue(json["type"] as String?),
      severity: Severity.fromValue(json["severity"] as String?),
      environment: json["environment"] as String? ?? "",
      labels: _labels(json["labels"]),
      syncStatus: SyncStatus.fromValue(json["sync_status"] as String?),
      githubIssueNumber: _intValue(json["github_issue_number"]),
      createdAt: _dateValue(json["created_at"]),
      updatedAt: _dateValue(json["updated_at"]),
    );
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      if (id != null) "id": id,
      "repo_id": repoId,
      "user_id": userId,
      "title": title,
      "description": description,
      "type": type.value,
      "severity": severity.value,
      "environment": environment,
      "labels": labels,
      "sync_status": syncStatus.value,
      "github_issue_number": githubIssueNumber,
      if (createdAt != null) "created_at": createdAt!.toUtc().toIso8601String(),
      "updated_at": (updatedAt ?? DateTime.now().toUtc())
          .toUtc()
          .toIso8601String(),
    };
  }

  EngineeringLog copyWith({
    String? id,
    String? repoId,
    String? userId,
    String? title,
    String? description,
    EngineeringLogType? type,
    Severity? severity,
    String? environment,
    List<String>? labels,
    SyncStatus? syncStatus,
    int? githubIssueNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EngineeringLog(
      id: id ?? this.id,
      repoId: repoId ?? this.repoId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      environment: environment ?? this.environment,
      labels: labels ?? this.labels,
      syncStatus: syncStatus ?? this.syncStatus,
      githubIssueNumber: githubIssueNumber ?? this.githubIssueNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<String> _labels(dynamic value) {
    if (value is List) {
      return value.map((label) => label.toString()).toList();
    }
    return const [];
  }

  static int? _intValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
