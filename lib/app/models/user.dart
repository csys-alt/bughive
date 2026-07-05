import 'package:nylo_framework/nylo_framework.dart';

class User extends Model {
  String? id;
  String? githubId;
  String? username;
  String? avatarUrl;
  DateTime? createdAt;

  static final StorageKey key = 'user';

  User() : super(key: key);

  User.fromJson(dynamic data) {
    id = data["id"] as String?;
    githubId = data["github_id"]?.toString();
    username = data["username"] as String?;
    avatarUrl = data["avatar_url"] as String?;
    createdAt = data["created_at"] == null
        ? null
        : DateTime.tryParse(data["created_at"].toString());
  }

  @override
  toJson() => {
    "id": id,
    "github_id": githubId,
    "username": username,
    "avatar_url": avatarUrl,
    "created_at": createdAt?.toIso8601String(),
  };

  Map<String, dynamic> toProfileJson() => {
    "id": id,
    "github_id": githubId,
    "username": username,
    "avatar_url": avatarUrl,
  };
}
