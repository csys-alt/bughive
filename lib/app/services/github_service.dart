import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import 'package:nylo_framework/nylo_framework.dart';

class GithubServiceException implements Exception {
  final String message;

  const GithubServiceException(this.message);

  @override
  String toString() => message;
}

/// Thrown when GitHub rejects a request because the token is missing,
/// expired, or lacks a required scope. Callers should prompt the user to
/// reconnect their GitHub account rather than showing a raw error.
class GithubReauthRequiredException implements Exception {
  const GithubReauthRequiredException();

  @override
  String toString() =>
      "Your GitHub connection needs to be refreshed. Reconnect to continue.";
}

class GithubRepositoryMetadata {
  final int githubRepoId;
  final String owner;
  final String name;
  final String url;
  final DateTime? createdAt;

  const GithubRepositoryMetadata({
    required this.githubRepoId,
    required this.owner,
    required this.name,
    required this.url,
    this.createdAt,
  });
}

class GithubIssueMetadata {
  final int number;
  final String title;
  final String body;
  final List<String> labels;
  final bool closed;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const GithubIssueMetadata({
    required this.number,
    required this.title,
    required this.body,
    required this.labels,
    required this.closed,
    this.createdAt,
    this.updatedAt,
  });

  factory GithubIssueMetadata.fromJson(Map<String, dynamic> data) {
    final labels = data["labels"] is List
        ? (data["labels"] as List)
              .whereType<Map>()
              .map((label) => label["name"]?.toString())
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return GithubIssueMetadata(
      number: _intValue(data["number"]),
      title: data["title"]?.toString() ?? "GitHub issue",
      body: data["body"]?.toString() ?? "",
      labels: labels,
      closed: data["state"] == "closed",
      createdAt: _dateValue(data["created_at"]),
      updatedAt: _dateValue(data["updated_at"]),
    );
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }
}

class GithubService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: "https://api.github.com",
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    ),
  );

  Future<GithubRepositoryMetadata> getRepository(
    String repositoryUrl, {
    String? accessToken,
  }) async {
    final parsed = parseRepositoryUrl(repositoryUrl);

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        "/repos/${parsed.$1}/${parsed.$2}",
        options: _options(accessToken),
      );
      final data = response.data;
      if (data == null) {
        throw const GithubServiceException("GitHub returned no repository.");
      }

      return GithubRepositoryMetadata(
        githubRepoId: _intValue(data["id"]),
        owner: (data["owner"] as Map?)?["login"]?.toString() ?? parsed.$1,
        name: data["name"]?.toString() ?? parsed.$2,
        url: data["html_url"]?.toString() ?? repositoryUrl.trim(),
        createdAt: DateTime.tryParse(
          data["created_at"]?.toString() ?? "",
        )?.toUtc(),
      );
    } on DioException catch (error) {
      _throwGithubError(error);
    }
  }

  Future<int> createIssue({
    required Repository repository,
    required EngineeringLog log,
    required String accessToken,
    List<String> attachmentUrls = const [],
  }) async {
    if (accessToken.isEmpty) {
      throw const GithubReauthRequiredException();
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        "/repos/${repository.owner}/${repository.name}/issues",
        data: {
          "title": log.title,
          "body": buildIssueBody(log, attachmentUrls: attachmentUrls),
          if (log.labels.isNotEmpty) "labels": log.labels,
        },
        options: _options(accessToken),
      );

      final issueNumber = response.data?["number"];
      if (issueNumber is int) return issueNumber;
      throw const GithubServiceException("GitHub issue number is missing.");
    } on DioException catch (error) {
      _throwGithubError(error);
    }
  }

  Future<void> updateIssue({
    required Repository repository,
    required EngineeringLog log,
    required int issueNumber,
    required String accessToken,
    List<String> attachmentUrls = const [],
  }) async {
    if (accessToken.isEmpty) {
      throw const GithubReauthRequiredException();
    }

    try {
      await _dio.patch<Map<String, dynamic>>(
        "/repos/${repository.owner}/${repository.name}/issues/$issueNumber",
        data: {
          "title": log.title,
          "body": buildIssueBody(log, attachmentUrls: attachmentUrls),
          if (log.labels.isNotEmpty) "labels": log.labels,
        },
        options: _options(accessToken),
      );
    } on DioException catch (error) {
      _throwGithubError(error);
    }
  }

  Future<void> closeIssue({
    required Repository repository,
    required int issueNumber,
    required String accessToken,
    String stateReason = "completed",
  }) async {
    if (accessToken.isEmpty) {
      throw const GithubReauthRequiredException();
    }

    try {
      await _dio.patch<Map<String, dynamic>>(
        "/repos/${repository.owner}/${repository.name}/issues/$issueNumber",
        data: {"state": "closed", "state_reason": stateReason},
        options: _options(accessToken),
      );
    } on DioException catch (error) {
      _throwGithubError(error);
    }
  }

  Future<List<GithubIssueMetadata>> listIssues({
    required Repository repository,
    required String accessToken,
  }) async {
    if (accessToken.isEmpty) {
      throw const GithubReauthRequiredException();
    }

    try {
      final response = await _dio.get<List<dynamic>>(
        "/repos/${repository.owner}/${repository.name}/issues",
        queryParameters: {"state": "all", "per_page": 100},
        options: _options(accessToken),
      );

      return (response.data ?? const [])
          .whereType<Map>()
          .where((issue) => issue["pull_request"] == null)
          .map((issue) => GithubIssueMetadata.fromJson(Map.from(issue)))
          .where((issue) => issue.number > 0)
          .toList(growable: false);
    } on DioException catch (error) {
      _throwGithubError(error);
    }
  }

  String buildIssueBody(
    EngineeringLog log, {
    List<String> attachmentUrls = const [],
  }) {
    final evidence = attachmentUrls.where((url) => url.trim().isNotEmpty);
    final evidenceLines = evidence.isEmpty
        ? ["Not attached"]
        : [
            for (final entry in evidence.indexed)
              "![Attachment ${entry.$1 + 1}](${entry.$2.trim()})",
          ];

    return [
      "# Bug Report",
      "",
      "## Description",
      "",
      log.description.trim(),
      "",
      "## Environment",
      "",
      log.environment.trim(),
      "",
      "## Severity",
      "",
      log.severity.value,
      "",
      "## Evidence",
      "",
      ...evidenceLines,
    ].join("\n");
  }

  (String, String) parseRepositoryUrl(String repositoryUrl) {
    final value = repositoryUrl.trim();
    final uri = Uri.tryParse(
      value.startsWith("http") ? value : "https://$value",
    );
    if (uri == null || uri.host.toLowerCase() != "github.com") {
      throw const GithubServiceException(
        "Enter a valid GitHub repository URL.",
      );
    }

    final parts = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (parts.length < 2) {
      throw const GithubServiceException(
        "Repository URL must include owner and name.",
      );
    }

    final owner = parts[0];
    final name = parts[1].replaceFirst(RegExp(r"\.git$"), "");
    if (owner.isEmpty || name.isEmpty) {
      throw const GithubServiceException(
        "Repository URL must include owner and name.",
      );
    }
    return (owner, name);
  }

  Options _options(String? accessToken) {
    return Options(
      headers: {
        if (accessToken != null && accessToken.isNotEmpty)
          "Authorization": "Bearer $accessToken",
      },
    );
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }

  String _githubError(DioException error) {
    final data = error.response?.data;
    if (data is Map && data["message"] != null) {
      return data["message"].toString();
    }
    return "GitHub request failed.";
  }

  Never _throwGithubError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      throw const GithubReauthRequiredException();
    }
    throw GithubServiceException(_githubError(error));
  }
}
