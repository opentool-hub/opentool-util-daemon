import 'package:dio/dio.dart';

typedef DioResponder = Object? Function(RequestOptions options);

Dio createStubDio(Map<String, DioResponder> responders) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final key = '${options.method} ${options.path}';
        final responder = responders[key];
        if (responder == null) {
          handler.reject(
            DioException(
              requestOptions: options,
              error: 'Unhandled request: $key',
            ),
          );
          return;
        }
        handler.resolve(
          Response(
            requestOptions: options,
            data: responder(options),
            statusCode: 200,
          ),
        );
      },
    ),
  );
  return dio;
}
