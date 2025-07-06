import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_shared/ht_shared.dart' hide ServerException;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

/// {@template ht_data_postgres}
/// A generic PostgreSQL implementation of the [HtDataClient] interface.
///
/// This client translates the generic CRUD and query operations into SQL
/// commands to interact with a PostgreSQL database. It requires a table name
/// and functions for JSON serialization/deserialization to work with any
/// data model [T].
/// {@endtemplate}
class HtDataPostgresClient<T> implements HtDataClient<T> {
  /// {@macro ht_data_postgres_client}
  HtDataPostgresClient({
    required this.connection,
    required this.tableName,
    required this.fromJson,
    required this.toJson,
    required Logger log,
  })  : _queryBuilder = _QueryBuilder(tableName: tableName),
        _log = log;

  final Logger _log;

  /// The active PostgreSQL database connection.
  final Connection connection;

  /// The name of the database table corresponding to type [T].
  final String tableName;

  /// A function that converts a JSON map into an object of type [T].
  final FromJson<T> fromJson;

  /// A function that converts an object of type [T] into a JSON map.
  /// This map's keys should correspond to the database column names.
  final ToJson<T> toJson;

  /// A helper class to construct SQL queries dynamically.
  final _QueryBuilder _queryBuilder;

  @override
  Future<SuccessApiResponse<T>> create({
    required T item,
    String? userId,
  }) async {
    _log.fine('Creating item in "$tableName"...');
    try {
      final data = toJson(item);
      if (userId != null) {
        // Assume a 'user_id' column for user-owned models.
        data['user_id'] = userId;
      }

      final columns = data.keys.join(', ');
      final placeholders = List.generate(
        data.length,
        (i) => '@${data.keys.elementAt(i)}',
      ).join(', ');

      final sql = Sql.named(
        'INSERT INTO $tableName ($columns) VALUES ($placeholders) RETURNING *;',
      );

      final result = await connection.execute(sql, parameters: data);

      final createdItem = fromJson(
        result.first.toColumnMap(),
      );
      _log.finer(
        'Successfully created item with id "${(createdItem as dynamic).id}" in "$tableName".',
      );
      return SuccessApiResponse(data: createdItem);
    } on Object catch (e, st) {
      _log.severe('Failed to create item in "$tableName".', e, st);
      throw _handlePgException(e);
    }
  }

  @override
  Future<void> delete({required String id, String? userId}) async {
    try {
      _log.fine('Deleting item with id "$id" from "$tableName"...');
      var sql = 'DELETE FROM $tableName WHERE id = @id';
      final parameters = <String, dynamic>{'id': id};

      if (userId != null) {
        sql += ' AND user_id = @userId';
        parameters['userId'] = userId;
      }

      final result = await connection.execute(
        Sql.named(sql),
        parameters: parameters,
      );

      if (result.affectedRows == 0) {
        throw NotFoundException(
          'Item with ID "$id" not found${userId != null ? ' for this user' : ''}.',
        );
      }
      _log.finer('Successfully deleted item with id "$id" from "$tableName".');
    } on Object catch (e, st) {
      _log.severe('Failed to delete item with id "$id" from "$tableName".', e, st);
      throw _handlePgException(e);
    }
  }

  @override
  Future<SuccessApiResponse<T>> read({
    required String id,
    String? userId,
  }) async {
    _log.fine('Reading item with id "$id" from "$tableName"...');
    try {
      var sql = 'SELECT * FROM $tableName WHERE id = @id';
      final parameters = <String, dynamic>{'id': id};

      if (userId != null) {
        sql += ' AND user_id = @userId';
        parameters['userId'] = userId;
      }
      sql += ';';

      final result = await connection.execute(
        Sql.named(sql),
        parameters: parameters,
      );

      if (result.isEmpty) {
        throw NotFoundException(
          'Item with ID "$id" not found${userId != null ? ' for this user' : ''}.',
        );
      }
      final readItem = fromJson(result.first.toColumnMap());
      _log.finer('Successfully read item with id "$id" from "$tableName".');
      return SuccessApiResponse(data: readItem);
    } on Object catch (e, st) {
      _log.severe('Failed to read item with id "$id" from "$tableName".', e, st);
      throw _handlePgException(e);
    }
  }

  @override
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAll({
    String? userId,
    String? startAfterId,
    int? limit,
    String? sortBy,
    SortOrder? sortOrder,
  }) {
    // readAll is just a special case of readAllByQuery with an empty query.
    return readAllByQuery(
      {},
      userId: userId,
      startAfterId: startAfterId,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
  }

  @override
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAllByQuery(
    Map<String, dynamic> query, {
    String? userId,
    String? startAfterId,
    int? limit,
    String? sortBy,
    SortOrder? sortOrder,
  }) async {
    _log.fine(
      'Querying "$tableName" with query: $query, limit: $limit, sortBy: $sortBy',
    );
    try {
      // Note: startAfterId is not yet implemented for PostgreSQL client.
      // Keyset pagination would be required for a robust implementation.
      final (sql, params) = _queryBuilder.buildSelect(
        query: query,
        userId: userId,
        limit: limit,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );

      final result = await connection.execute(
        Sql.named(sql),
        parameters: params,
      );

      final items = result.map((row) => fromJson(row.toColumnMap())).toList();

      var hasMore = false;
      if (limit != null && items.length > limit) {
        hasMore = true;
        items.removeLast();
      }

      // The cursor should be the ID of the last item in the returned list.
      final cursor = items.isNotEmpty
          ? (items.last as dynamic).id as String?
          : null;

      _log.finer(
        'Successfully queried "$tableName". Found ${items.length} items.',
      );
      return SuccessApiResponse(
        data: PaginatedResponse(
          items: items,
          hasMore: hasMore,
          cursor: cursor,
        ),
      );
    } on Object catch (e, st) {
      _log.severe('Failed to query "$tableName".', e, st);
      throw _handlePgException(e);
    }
  }

  @override
  Future<SuccessApiResponse<T>> update({
    required String id,
    required T item,
    String? userId,
  }) async {
    _log.fine('Updating item with id "$id" in "$tableName"...');
    try {
      final data = toJson(item)
        // Remove 'id' from the data to be updated in SET clause, as it's used
        // in the WHERE clause. Also remove created_at if it exists.
        ..remove('id')
        ..remove('created_at');

      if (data.isEmpty) {
        // Nothing to update, just read and return the item.
        return read(id: id, userId: userId);
      }

      final setClauses = data.keys.map((key) => '$key = @$key').join(', ');

      var sql = 'UPDATE $tableName SET $setClauses WHERE id = @id';
      final parameters = <String, dynamic>{...data, 'id': id};

      if (userId != null) {
        sql += ' AND user_id = @userId';
        parameters['userId'] = userId;
      }
      sql += ' RETURNING *;';

      final result = await connection.execute(
        Sql.named(sql),
        parameters: parameters,
      );

      if (result.isEmpty) {
        throw NotFoundException(
          'Item with ID "$id" not found${userId != null ? ' for this user' : ''}.',
        );
      }
      final updatedItem = fromJson(result.first.toColumnMap());
      _log.finer('Successfully updated item with id "$id" in "$tableName".');
      return SuccessApiResponse(data: updatedItem);
    } on Object catch (e, st) {
      _log.severe('Failed to update item with id "$id" in "$tableName".', e, st);
      throw _handlePgException(e);
    }
  }

  /// Maps a [PgException] to a corresponding [HtHttpException].
  Exception _handlePgException(Object e) {
    if (e is ServerException) {
      _log.warning(
        'Mapping ServerException with code: ${e.code} to HtHttpException.',
        e,
      );
      // See PostgreSQL error codes: https://www.postgresql.org/docs/current/errcodes-appendix.html
      final code = e.code;
      if (code != null) {
        switch (code) {
          case '23505': // unique_violation
            return ConflictException(
              e.message,
            );
          case '23503': // foreign_key_violation
            return BadRequestException(
              e.message,
            );
        }
      }
      return OperationFailedException(
        'A database error occurred: ${e.message}',
      );
    } else if (e is PgException) {
      _log.warning('Mapping generic PgException to HtHttpException.', e);
      return OperationFailedException(
        'A database connection error occurred: ${e.message}',
      );
    }
    _log.severe('Encountered an unknown exception type.', e);
    return Exception('An unknown error occurred: $e');
  }
}

/// A helper class to dynamically build SQL SELECT queries.
class _QueryBuilder {
  _QueryBuilder({required this.tableName});

  final String tableName;

  /// Builds a SQL SELECT statement and its substitution parameters.
  (String, Map<String, dynamic>) buildSelect({
    required Map<String, dynamic> query,
    String? userId,
    int? limit,
    String? sortBy,
    SortOrder? sortOrder,
  }) {
    final whereClauses = <String>[];
    final params = <String, dynamic>{};
    var paramCounter = 0;

    // Handle user-scoping
    if (userId != null) {
      whereClauses.add('user_id = @userId');
      params['userId'] = userId;
    }

    // Handle generic query map
    for (final entry in query.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key.endsWith('_in')) {
        final column = _sanitizeColumnName(key.replaceAll('_in', ''));
        final values = (value as String).split(',');
        if (values.isNotEmpty) {
          final paramNames = <String>[];
          for (final val in values) {
            final paramName = 'p${paramCounter++}';
            paramNames.add('@$paramName');
            params[paramName] = val;
          }
          whereClauses.add('$column IN (${paramNames.join(', ')})');
        }
      } else if (key.endsWith('_contains')) {
        final column = _sanitizeColumnName(key.replaceAll('_contains', ''));
        final paramName = 'p${paramCounter++}';
        whereClauses.add('$column ILIKE @$paramName');
        params[paramName] = '%$value%';
      } else {
        // Exact match
        final column = _sanitizeColumnName(key);
        final paramName = 'p${paramCounter++}';
        whereClauses.add('$column = @$paramName');
        params[paramName] = value;
      }
    }

    var sql = 'SELECT * FROM $tableName';
    if (whereClauses.isNotEmpty) {
      sql += ' WHERE ${whereClauses.join(' AND ')}';
    }

    // Handle sorting
    if (sortBy != null) {
      final order = sortOrder == SortOrder.desc ? 'DESC' : 'ASC';
      sql += ' ORDER BY ${_sanitizeColumnName(sortBy)} $order';
    }

    // Handle limit (fetch one extra to check for `hasMore`)
    if (limit != null) {
      sql += ' LIMIT ${limit + 1}';
    }

    sql += ';';

    return (sql, params);
  }

  /// Sanitizes a column name to prevent SQL injection.
  /// Converts dot notation (e.g., 'category.id') to snake_case ('category_id').
  String _sanitizeColumnName(String name) {
    // A simple sanitizer. For production, a more robust one might be needed.
    // This prevents basic injection by only allowing alphanumeric, underscore,
    // and dot characters, then replacing dots.
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(name)) {
      throw ArgumentError('Invalid column name format: $name');
    }
    return name.replaceAll('.', '_');
  }
}
