import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_tracker/data/api.dart';

void main() {
  test('mobile requests send bearer auth and real JSON numbers', () async {
    final api =
        MedicineApi(
            client: MockClient((request) async {
              expect(request.url.toString(), 'https://example.test/api/stock');
              expect(request.headers['authorization'], 'Bearer session');
              expect(jsonDecode(request.body)['quantity'], 0.5);
              return http.Response('{"medicines":[]}', 200);
            }),
          )
          ..baseUrl = 'https://example.test'
          ..token = 'session';
    expect(await api.post('stock', {'quantity': 0.5}), {'medicines': []});
  });
  test('backend conflicts preserve their message and status', () async {
    final api = MedicineApi(
      client: MockClient(
        (_) async => http.Response('{"message":"Not enough stock"}', 409),
      ),
    )..baseUrl = 'https://example.test';
    await expectLater(
      api.get('state'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.message, 'message', 'Not enough stock'),
      ),
    );
  });
  test('server URL validation prevents embedded credentials and API paths', () {
    expect(
      MedicineApi.normalizeUrl(' http://192.168.1.2:3001/ '),
      'http://192.168.1.2:3001',
    );
    for (final url in [
      'example.test',
      'https://user:secret@example.test',
      'https://example.test/api',
      'file:///data',
    ]) {
      expect(() => MedicineApi.normalizeUrl(url), throwsA(isA<ApiException>()));
    }
  });
}
