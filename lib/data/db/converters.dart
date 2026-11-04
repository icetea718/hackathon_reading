import 'package:drift/drift.dart';

/// Stores [DateTime] as a fixed-width UTC ISO-8601 string.
///
/// The rest of the database keeps drift's default INTEGER (unix seconds), which
/// cannot order two rows written in the same second. Chat rows are appended in
/// bursts — a user question and the first assistant token — so their order must
/// survive sub-second writes, and a lexicographic TEXT comparison gives exactly
/// chronological order.
class IsoDateTimeConverter extends TypeConverter<DateTime, String> {
  const IsoDateTimeConverter();

  @override
  DateTime fromSql(String fromDb) => DateTime.parse(fromDb).toLocal();

  @override
  String toSql(DateTime value) => value.toUtc().toIso8601String();
}
