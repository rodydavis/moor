## 0.8.0

This package is now deprecated, but will continue to work for Flutter users.

Moor users should use the new `package:moor/ffi.dart` library.
To migrate,
- replace imports
  - of `package:moor_ffi/moor_ffi.dart` with `package:moor/ffi.dart`
  - of `package:moor_ffi/open_helper.dart` with `package:sqlite3/open.dart`
- when using Flutter, add a dependency on `sqlite3_flutter_libs`

Users of this package that don't use moor should use the new [sqlite3](https://pub.dev/packages/sqlite3)
package instead.

## 0.7.0

- Throw an error when using an unsupported datatype as argument
- Return null from `REGEXP` when either argument is null (used to report an error)

## 0.6.0

- Added `moor_contains` sql function to support case-sensitive contains
- Workaround for `dlopen` issues on some Android devices.

## 0.5.0

- Provide mathematical functions in sql (`pow`, `power`, `sin`, `cos`, `tan`, `asin`, `atan`, `acos`, `sqrt`)
- On Android, use sqlite 3.31.1
- added an `extendedResultCode` to `SqliteException`

## 0.4.0

- Use precompiled libraries for faster build times

## 0.3.2

- Fix a bug where empty blobs would read as `null` instead of an empty list

## 0.3.1

- Implement `overrideForAll` and `overrideFor` - thanks, [@negator](https://github.com/negator)

## 0.3.0

- Better setup for compiling sqlite3 on Android
  - Compilation options to increase runtime performance, enable `fts5` and `json1`
  - We no longer download sqlite sources on the first run, they now ship with the plugin

## 0.2.0

- Remove the `background` flag from the moor apis provided by this package. Use the moor isolate api
  instead.
- Remove builtin support for background execution from the low-level `Database` api
- Support Dart 2.6, drop support for older versions

## 0.0.1

- Initial release. Contains standalone bindings and a moor implementation.