import 'package:dio/dio.dart';

class FetchResult {
  const FetchResult({required this.statusCode, required this.bytes});
  final int statusCode;
  final List<int> bytes;
  bool get isOk => statusCode >= 200 && statusCode < 300;
}

/// Thrown when nothing answered at all, as distinct from answering badly.
class FetchUnreachable implements Exception {
  const FetchUnreachable(this.detail);
  final String detail;
  @override
  String toString() => 'FetchUnreachable: $detail';
}

/// Fetching raw bytes for a repository index. An interface so the parser and
/// repository can be tested without network access (INSTRUCTIONS.md 16).
abstract interface class RepoIndexFetcher {
  Future<FetchResult> get(String url);
}

class DioRepoIndexFetcher implements RepoIndexFetcher {
  DioRepoIndexFetcher({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              // Repository indexes are a few hundred KB at most; anything
              // larger is not an index we should be parsing.
              maxRedirects: 5,
              followRedirects: true,
              headers: const {'Accept': '*/*'},
            ),
          );

  final Dio _dio;

  @override
  Future<FetchResult> get(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          // We want to report a 404 as a 404, not as a thrown exception.
          validateStatus: (_) => true,
          // Ask for the raw bytes: gzip is part of the payload format here
          // (section 6), not a transport detail to be unwrapped for us.
          receiveDataWhenStatusError: true,
        ),
      );
      return FetchResult(
        statusCode: response.statusCode ?? 0,
        bytes: response.data ?? const [],
      );
    } on DioException catch (e) {
      throw FetchUnreachable(e.message ?? e.type.name);
    }
  }
}
