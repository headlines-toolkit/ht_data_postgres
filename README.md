# ht_data_postgres

![coverage: percentage](https://img.shields.io/badge/coverage-97-green)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License: PolyForm Free Trial](https://img.shields.io/badge/License-PolyForm%20Free%20Trial-blue)](https://polyformproject.org/licenses/free-trial/1.0.0)

> **Note:** This package is being archived. Please use the successor package [`data-mongodb`](https://github.com/flutter-news-app-full-source-code/data-mongodb) instead.

A generic PostgreSQL implementation of the `DataClient` interface.

This package provides a concrete implementation of the `DataClient`
for interacting with PostgreSQL databases. It translates generic CRUD and
query operations into SQL commands, supporting various data models via
JSON serialization and deserialization functions.

## Getting Started

Add the `ht_data_postgres` package to your `pubspec.yaml`:

```yaml
dependencies:
  ht_data_postgres:
    git:
      url: https://github.com/flutter-news-app-full-source-code/ht-data-postgres.git
```

## Features

*   **Generic Data Client:** Implements `DataClient<T>` for any data model.
*   **CRUD Operations:** Supports `create`, `read`, `update`, and `delete`.
*   **Querying:** `readAll` and `readAllByQuery` with pagination and sorting.
*   **User Scoping:** Operations can be scoped to a specific user via `userId`.
*   **Error Handling:** Maps PostgreSQL exceptions to `HtHttpException` subtypes.

## Usage

Initialize `HtDataPostgresClient` with a PostgreSQL `Connection`, table name,
and JSON serialization functions:

```dart
import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_data_postgres/ht_data_postgres.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

// Example data model (replace with your actual model)
class MyItem {
  MyItem({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  static MyItem fromJson(Map<String, dynamic> json) =>
      MyItem(id: json['id'] as String, name: json['name'] as String);
}

Future<void> main() async {
  final log = Logger('PostgresClient');
  final connection = await Connection.open(
    Endpoint(
      host: 'localhost',
      port: 5432,
      database: 'mydatabase',
      username: 'myuser',
      password: 'mypassword',
    ),
  );

  final client = HtDataPostgresClient<MyItem>(
    connection: connection,
    tableName: 'my_items',
    fromJson: MyItem.fromJson,
    toJson: (item) => item.toJson(),
    log: log,
  );

  try {
    // Create an item
    final newItem = MyItem(id: '123', name: 'Test Item');
    final createdResponse = await client.create(item: newItem);
    print('Created: ${createdResponse.data.name}');

    // Read an item
    final readResponse = await client.read(id: '123');
    print('Read: ${readResponse.data.name}');

    // Update an item
    final updatedItem = MyItem(id: '123', name: 'Updated Item');
    final updatedResponse = await client.update(id: '123', item: updatedItem);
    print('Updated: ${updatedResponse.data.name}');

    // Read all items
    final allItemsResponse = await client.readAll();
    print('All items: ${allItemsResponse.data.items.length}');

    // Delete an item
    await client.delete(id: '123');
    print('Deleted item 123');
  } catch (e) {
    print('Error: $e');
  } finally {
    await connection.close();
  }
}
```

## License

This package is licensed under the [PolyForm Free Trial](LICENSE). Please
review the terms before use.
