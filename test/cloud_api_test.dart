import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_tracker/data/api.dart';
import 'package:medicine_tracker/data/controller.dart';

void main() {
  test('S3 uploads carry bytes without forwarding the API session', () async {
    final bytes = utf8.encode('%PDF-1.4\nPrivate prescription');
    final paths = <String>[];
    final api =
        MedicineApi(
            client: MockClient((request) async {
              paths.add(request.url.path);
              if (request.url.host == 'private.s3.test') {
                expect(request.method, 'PUT');
                expect(request.headers['authorization'], isNull);
                expect(request.headers['if-none-match'], '*');
                expect(request.bodyBytes, bytes);
                return http.Response('', 200);
              }
              expect(
                request.headers['authorization'],
                'Bearer private-session',
              );
              if (request.url.path.endsWith('/capabilities')) {
                return http.Response('{"directFileUpload":true}', 200);
              }
              if (request.url.path.endsWith('/upload')) {
                final body = jsonDecode(request.body) as Map;
                expect(body['base64'], isNull);
                expect(body['size'], bytes.length);
                return http.Response(
                  jsonEncode({
                    'id': 'upload-id',
                    'url': 'https://private.s3.test/object',
                    'headers': {
                      'Content-Type': 'application/pdf',
                      'If-None-Match': '*',
                    },
                  }),
                  200,
                );
              }
              expect(jsonDecode(request.body), {'id': 'upload-id'});
              return http.Response(
                '{"prescriptions":[{"id":"upload-id"}]}',
                200,
              );
            }),
          )
          ..baseUrl = 'https://medicine.test'
          ..token = 'private-session';
    final result = await api.post('prescriptions', {
      'name': 'file.pdf',
      'mime': 'application/pdf',
      'base64': base64Encode(bytes),
    });
    expect((result['prescriptions'] as List).length, 1);
    expect(paths, [
      '/api/capabilities',
      '/api/prescriptions/upload',
      '/object',
      '/api/prescriptions/complete',
    ]);
  });

  test('S3 downloads do not disclose the API Authorization header', () async {
    final api =
        MedicineApi(
            client: MockClient((request) async {
              if (request.url.host == 'private.s3.test') {
                expect(request.headers['authorization'], isNull);
                return http.Response('private bytes', 200);
              }
              expect(
                request.headers['authorization'],
                'Bearer private-session',
              );
              return http.Response(
                request.url.path.endsWith('/capabilities')
                    ? '{"directFileUpload":true}'
                    : '{"url":"https://private.s3.test/object"}',
                200,
              );
            }),
          )
          ..baseUrl = 'https://medicine.test'
          ..token = 'private-session';
    expect(utf8.decode(await api.file('file-id')), 'private bytes');
  });

  test(
    'Cognito pending verification does not create an authenticated mobile session',
    () async {
      final api = MedicineApi(
        client: MockClient((request) async {
          expect(request.url.origin, MedicineApi.productionBaseUrl);
          return http.Response('{"confirmationRequired":true}', 202);
        }),
      );
      final app = AppController(api: api);
      final result = await app.authenticate(
        email: 'user@example.test',
        password: 'TestPassword123',
        name: 'User',
      );
      expect(result?['confirmationRequired'], true);
      expect(app.signedIn, false);
      expect(api.token, isNull);
      app.dispose();
    },
  );
}
