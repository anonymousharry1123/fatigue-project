import 'package:cloud_firestore/cloud_firestore.dart';

/// Converts SDK timestamps at every nesting depth before domain decoding.
///
/// Keep Timestamp.toDate() semantics consistent with the original top-level
/// adapter. Do not mutate SDK snapshots or reinterpret zero/null values.
Map<String, dynamic> normalizeFirestoreDocument(Map<String, dynamic> data) =>
    data.map((key, value) => MapEntry(key, _normalizeValue(value)));

Object? _normalizeValue(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  Map map => map.map((key, child) => MapEntry(key, _normalizeValue(child))),
  Iterable values => values.map(_normalizeValue).toList(),
  _ => value,
};

/// Native DateTime encoding retains only milliseconds. Use Timestamp for
/// writes compared with a durable sync journal, which retains microseconds.
/// Sentinels and ordinary values pass through without mutating the payload.
Map<String, dynamic> encodeFirestoreDocument(Map<String, dynamic> data) =>
    data.map((key, value) => MapEntry(key, _encodeValue(value)));

Object? _encodeValue(Object? value) => switch (value) {
  DateTime instant => Timestamp.fromDate(instant),
  Map map => map.map((key, child) => MapEntry(key, _encodeValue(child))),
  Iterable values => values.map(_encodeValue).toList(),
  _ => value,
};
