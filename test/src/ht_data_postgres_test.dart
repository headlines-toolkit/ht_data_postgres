// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:ht_data_postgres/ht_data_postgres.dart';
import 'package:test/test.dart';

void main() {
  group('HtDataPostgres', () {
    test('can be instantiated', () {
      expect(HtDataPostgres(), isNotNull);
    });
  });
}
