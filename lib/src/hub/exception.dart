import 'package:json_annotation/json_annotation.dart';

part 'exception.g.dart';

@JsonSerializable(createFactory: false)
class LoginFailedException implements Exception {
  final String code;
  final String message;

  LoginFailedException({required this.code, required this.message});

  Map<String, dynamic> toJson() => _$LoginFailedExceptionToJson(this);
}
