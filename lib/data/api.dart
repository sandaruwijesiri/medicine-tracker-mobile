import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class MedicineApi {
  MedicineApi({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  static const productionBaseUrl =
      'https://14ht6ah4ql.execute-api.ap-south-1.amazonaws.com';
  String baseUrl = productionBaseUrl;
  String? token;
  static String normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const ApiException(
        'Enter the server address, e.g. http://192.168.1.10:3001 (without /api).',
      );
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<http.Response> _request(String path, [Json? body]) async {
    try {
      final uri = Uri.parse('$baseUrl/api/$path');
      final headers = {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      final response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'Server returned ${response.statusCode}.';
        try {
          message = str(jsonDecode(response.body)['message']);
        } catch (_) {
          /* Non-JSON proxy response. */
        }
        throw ApiException(message, response.statusCode);
      }
      return response;
    } on TimeoutException {
      throw ApiException(
        body == null
            ? 'The server took too long to respond. Check your connection.'
            : 'The request timed out and may have been saved. Sync and check before trying again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the server. Check your internet connection and try again.',
      );
    }
  }

  Future<Json> get(String path) async =>
      Map<String, dynamic>.from(jsonDecode((await _request(path)).body) as Map);
  Future<Json> post(String path, Json body) async {
    if (path == 'prescriptions' && body['base64'] is String) {
      final capabilities = await get('capabilities');
      if (capabilities['directFileUpload'] == true) {
        final bytes = base64Decode(body['base64'] as String);
        final metadata = Map<String, dynamic>.from(body)..remove('base64');
        final ticket = await post('prescriptions/upload', {
          ...metadata,
          'size': bytes.length,
        });
        final uri = Uri.parse(str(ticket['url']));
        if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
          throw const ApiException('Invalid secure upload address.');
        }
        final upload = await client
            .put(
              uri,
              headers: Map<String, String>.from(ticket['headers'] as Map),
              body: bytes,
            )
            .timeout(const Duration(seconds: 60));
        if (upload.statusCode < 200 || upload.statusCode >= 300) {
          throw const ApiException(
            'The file upload failed. Select the file again.',
          );
        }
        return post('prescriptions/complete', {'id': ticket['id']});
      }
    }
    return Map<String, dynamic>.from(
      jsonDecode((await _request(path, body)).body) as Map,
    );
  }

  Future<List<int>> file(String id) async {
    final capabilities = await get('capabilities');
    if (capabilities['directFileUpload'] == true) {
      final link = await get('files/${Uri.encodeComponent(id)}/link');
      final uri = Uri.parse(str(link['url']));
      if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        throw const ApiException('Invalid secure download address.');
      }
      // No API Authorization header is forwarded to the S3 host.
      final result = await client.get(uri).timeout(const Duration(seconds: 60));
      if (result.statusCode != 200) {
        throw const ApiException('File download failed. Try again.');
      }
      return result.bodyBytes;
    }
    return (await _request('files/${Uri.encodeComponent(id)}')).bodyBytes;
  }

  void close() => client.close();
}
