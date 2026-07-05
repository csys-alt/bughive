class Attachment {
  final String? id;
  final String logId;
  final String fileUrl;
  final DateTime? createdAt;

  const Attachment({
    this.id,
    required this.logId,
    required this.fileUrl,
    this.createdAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json["id"] as String?,
      logId: json["log_id"] as String? ?? "",
      fileUrl: json["file_url"] as String? ?? "",
      createdAt: _dateValue(json["created_at"]),
    );
  }

  Map<String, dynamic> toSupabaseJson() {
    return {if (id != null) "id": id, "log_id": logId, "file_url": fileUrl};
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
