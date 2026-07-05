class Repository {
  final String? id;
  final String? userId;
  final int githubRepoId;
  final String owner;
  final String name;
  final String url;
  final DateTime? lastSync;
  final DateTime? createdAt;

  const Repository({
    this.id,
    this.userId,
    required this.githubRepoId,
    required this.owner,
    required this.name,
    required this.url,
    this.lastSync,
    this.createdAt,
  });

  String get fullName => "$owner/$name";

  factory Repository.fromJson(Map<String, dynamic> json) {
    return Repository(
      id: json["id"] as String?,
      userId: json["user_id"] as String?,
      githubRepoId: _intValue(json["github_repo_id"]),
      owner: json["owner"] as String? ?? "",
      name: json["name"] as String? ?? "",
      url: json["url"] as String? ?? "",
      lastSync: _dateValue(json["last_sync"]),
      createdAt: _dateValue(json["created_at"]),
    );
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      if (id != null) "id": id,
      "user_id": userId,
      "github_repo_id": githubRepoId,
      "owner": owner,
      "name": name,
      "url": url,
      "last_sync": lastSync?.toIso8601String(),
      if (createdAt != null) "created_at": createdAt!.toUtc().toIso8601String(),
    };
  }

  Repository copyWith({
    String? id,
    String? userId,
    int? githubRepoId,
    String? owner,
    String? name,
    String? url,
    DateTime? lastSync,
    DateTime? createdAt,
  }) {
    return Repository(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      githubRepoId: githubRepoId ?? this.githubRepoId,
      owner: owner ?? this.owner,
      name: name ?? this.name,
      url: url ?? this.url,
      lastSync: lastSync ?? this.lastSync,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
