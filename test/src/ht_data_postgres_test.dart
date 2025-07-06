// Not required for test files
// ignore_for_file: prefer_const_constructors

import 'package:equatable/equatable.dart';
import 'package:ht_data_postgres/ht_data_postgres.dart';
import 'package:ht_shared/ht_shared.dart' hide ServerException;
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

class MockConnection extends Mock implements Connection {}

class MockLogger extends Mock implements Logger {}

class MockResult extends Mock implements Result {}

class MockResultRow extends Mock implements ResultRow {}

class FakeSql extends Fake implements Sql {}

class FakeServerException extends Fake implements ServerException {
  FakeServerException({
    required this.message,
    this.code,
    this.severity = Severity.error,
  });

  @override
  final String? code;

  @override
  final String message;

  @override
  final Severity severity;
}

class TestModel extends Equatable {
  const TestModel({required this.id, required this.name});

  factory TestModel.fromJson(Map<String, dynamic> json) {
    return TestModel(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  List<Object?> get props => [id, name];
}

void main() {
  group('HtDataPostgresClient', () {
    late HtDataPostgresClient<TestModel> sut;
    late MockConnection mockConnection;
    late MockLogger mockLogger;

    const tableName = 'test_models';
    final testModel = TestModel(id: '1', name: 'Test');
    final testModelJson = {'id': '1', 'name': 'Test'};

    setUpAll(() {
      registerFallbackValue(FakeSql());
    });

    setUp(() {
      mockConnection = MockConnection();
      mockLogger = MockLogger();
      sut = HtDataPostgresClient<TestModel>(
        connection: mockConnection,
        tableName: tableName,
        fromJson: TestModel.fromJson,
        toJson: (m) => m.toJson(),
        log: mockLogger,
      );
    });

    group('create', () {
      test('should return created item on success', () async {
        final mockResult = MockResult();
        final mockResultRow = MockResultRow();
        when(mockResultRow.toColumnMap).thenReturn(testModelJson);
        when(() => mockResult.first).thenReturn(mockResultRow);
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenAnswer((_) async => mockResult);

        final result = await sut.create(item: testModel);

        expect(result.data, testModel);
        verify(
          () => mockConnection.execute(
            any(
              that: isA<Sql>().having(
                (s) => (s as dynamic).sql as String,
                'sql',
                'INSERT INTO test_models (id, name) VALUES (@id, @name) RETURNING *;',
              ),
            ),
            parameters: testModelJson,
          ),
        ).called(1);
        verify(() => mockLogger.fine(any())).called(1);
        verify(() => mockLogger.finer(any())).called(1);
      });

      test('should throw ConflictException on unique violation', () {
        final exception = FakeServerException(
          message: 'unique violation',
          code: '23505',
        );
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenThrow(exception);

        expect(
          () => sut.create(item: testModel),
          throwsA(isA<ConflictException>()),
        );
        verify(() => mockLogger.severe(any(), any(), any())).called(1);
      });
    });

    group('read', () {
      test('should return item when found', () async {
        final mockResult = MockResult();
        final mockResultRow = MockResultRow();
        when(mockResultRow.toColumnMap).thenReturn(testModelJson);
        when(() => mockResult.isEmpty).thenReturn(false);
        when(() => mockResult.first).thenReturn(mockResultRow);
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenAnswer((_) async => mockResult);

        final result = await sut.read(id: '1');

        expect(result.data, testModel);
        verify(
          () => mockConnection.execute(
            any(
              that: isA<Sql>().having(
                (s) => (s as dynamic).sql as String,
                'sql',
                'SELECT * FROM test_models WHERE id = @id;',
              ),
            ),
            parameters: {'id': '1'},
          ),
        ).called(1);
      });

      test('should throw NotFoundException when item is not found', () {
        final mockResult = MockResult();
        when(() => mockResult.isEmpty).thenReturn(true);
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenAnswer((_) async => mockResult);

        expect(
          () => sut.read(id: '1'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('update', () {
      test('should return updated item on success', () async {
        final mockResult = MockResult();
        final mockResultRow = MockResultRow();
        when(mockResultRow.toColumnMap).thenReturn(testModelJson);
        when(() => mockResult.isEmpty).thenReturn(false);
        when(() => mockResult.first).thenReturn(mockResultRow);
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenAnswer((_) async => mockResult);

        final result = await sut.update(id: '1', item: testModel);

        expect(result.data, testModel);
        verify(
          () => mockConnection.execute(
            any(
              that: isA<Sql>().having(
                (s) => (s as dynamic).sql as String,
                'sql',
                'UPDATE test_models SET name = @name WHERE id = @id RETURNING *;',
              ),
            ),
            parameters: {'name': 'Test', 'id': '1'},
          ),
        ).called(1);
      });
    });

    group('delete', () {
      test('should complete normally on success', () async {
        final mockResult = MockResult();
        when(() => mockResult.affectedRows).thenReturn(1);
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenAnswer((_) async => mockResult);

        await expectLater(sut.delete(id: '1'), completes);
        verify(() => mockLogger.finer(any())).called(1);
      });

      test('should throw NotFoundException when item to delete is not found',
          () {
        final mockResult = MockResult();
        when(() => mockResult.affectedRows).thenReturn(0);
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenAnswer((_) async => mockResult);

        expect(
          () => sut.delete(id: '1'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('readAllByQuery', () {
      test('should build correct query for `_in` operator', () async {
        final mockResult = MockResult();
        when(() => mockResult.map(any())).thenReturn([]);
        when(
          () => mockConnection.execute(
            any(),
            parameters: any(named: 'parameters'),
          ),
        ).thenAnswer((_) async => mockResult);

        await sut.readAllByQuery({'id_in': '1,2,3'});

        final captured = verify(
          () => mockConnection.execute(
            captureAny(),
            parameters: captureAny(named: 'parameters'),
          ),
        ).captured;

        final sql = captured[0] as Sql;
        final params = captured[1] as Map<String, dynamic>;

        expect(
          (sql as dynamic).sql,
          'SELECT * FROM test_models WHERE id IN (@p0, @p1, @p2) LIMIT 11;',
        );
        expect(params, {'p0': '1', 'p1': '2', 'p2': '3'});
      });

      test('should throw ArgumentError for invalid column name', () {
        expect(
          () => sut.readAllByQuery({'id; DROP TABLE test_models;': '1'}),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
