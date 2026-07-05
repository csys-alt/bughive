import '/app/controllers/auth_controller.dart';
import '/app/controllers/github_controller.dart';
import '/app/controllers/home_controller.dart';
import '/app/controllers/log_controller.dart';
import '/app/models/attachment.dart';
import '/app/models/engineering_log.dart';
import '/app/models/repository.dart';
import '/app/models/user.dart';
import '/app/networking/api_service.dart';

/* Model Decoders
|--------------------------------------------------------------------------
| Model decoders are used in 'app/networking/' for morphing json payloads
| into Models.
|
| Learn more https://nylo.dev/docs/7.x/decoders#model-decoders
|-------------------------------------------------------------------------- */

final Map<Type, dynamic> modelDecoders = {
  Map<String, dynamic>: (data) => Map<String, dynamic>.from(data),

  List<User>: (data) =>
      List.from(data).map((json) => User.fromJson(json)).toList(),
  //
  User: (data) => User.fromJson(data),
  List<Repository>: (data) => List.from(data)
      .map((json) => Repository.fromJson(Map<String, dynamic>.from(json)))
      .toList(),
  Repository: (data) => Repository.fromJson(Map<String, dynamic>.from(data)),
  List<EngineeringLog>: (data) => List.from(data)
      .map((json) => EngineeringLog.fromJson(Map<String, dynamic>.from(json)))
      .toList(),
  EngineeringLog: (data) =>
      EngineeringLog.fromJson(Map<String, dynamic>.from(data)),
  List<Attachment>: (data) => List.from(data)
      .map((json) => Attachment.fromJson(Map<String, dynamic>.from(json)))
      .toList(),
  Attachment: (data) => Attachment.fromJson(Map<String, dynamic>.from(data)),
};

/* API Decoders
| -------------------------------------------------------------------------
| API decoders are used when you need to access an API service using the
| 'api' helper. E.g. api<MyApiService>((request) => request.fetchData());
|
| Learn more https://nylo.dev/docs/7.x/decoders#api-decoders
|-------------------------------------------------------------------------- */

final Map<Type, dynamic> apiDecoders = {
  ApiService: () => ApiService(),

  // ...
};

/* Controller Decoders
| -------------------------------------------------------------------------
| Controller are used in pages.
|
| Learn more https://nylo.dev/docs/7.x/controllers
|-------------------------------------------------------------------------- */
final Map<Type, dynamic> controllers = {
  AuthController: () => AuthController(),
  HomeController: () => HomeController(),
  GithubController: () => GithubController(),
  LogController: () => LogController(),

  // ...
};
