// ---------------------------------------------------------------------------
// FORK ADDITION — compatibility shims required by FlutterFlow's Postgres
// template. See FORK_NOTES.md at the package root.
// ---------------------------------------------------------------------------
//
// FlutterFlow's code generator emits, in
// `lib/backend/postgres/database/table.dart`:
//
//     extension NullSafeSupabaseStreamFilters on SupabaseStreamFilterBuilder {
//       SupabaseStreamBuilder eqOrNull(String column, dynamic value) { ... }
//       // ... 6 more methods
//     }
//
// but the sibling `database.dart` only re-exports `package:postgrest`:
//
//     export 'package:postgrest/postgrest.dart' hide Provider;
//
// `SupabaseStreamFilterBuilder` and `SupabaseStreamBuilder` only exist in the
// `supabase` package, so the generated code does not compile. Worse, because
// `SupabaseStreamFilterBuilder` resolves to `InvalidType`, the
// `NullSafeSupabaseStreamFilters` extension becomes applicable to *every*
// receiver and `eqOrNull` turns ambiguous against `NullSafePostgrestFilters`
// on every `PostgrestFilterBuilder` call site (~23 cascading errors).
//
// Upstream FlutterFlow bug: FlutterFlow/flutterflow-issues#7402 (closed as
// stale, not fixed).
//
// Exporting these two types from `postgrest` is the smallest change that makes
// the generated code resolve:
//
//   * the 8 `UNDEFINED_CLASS` errors disappear;
//   * `SupabaseStreamFilterBuilder` becomes a real, *unrelated* type, so the
//     `NullSafeSupabaseStreamFilters` extension no longer applies to
//     `PostgrestFilterBuilder` receivers and the 23 ambiguities disappear.
//
// The Postgres backend never instantiates these classes — it only ever builds
// `PostgrestFilterBuilder` queries — so they carry no runtime behaviour. They
// exist so that the generated extension type-checks.

/// Stand-in for the `SupabaseStreamBuilder` type referenced by FlutterFlow's
/// generated Postgres backend.
///
/// See the file header for why this lives in the `postgrest` package.
class SupabaseStreamBuilder {
  const SupabaseStreamBuilder();

  @override
  String toString() => 'SupabaseStreamBuilder()';
}

/// Stand-in for the `SupabaseStreamFilterBuilder` type referenced by
/// FlutterFlow's generated Postgres backend.
///
/// Declares the filter methods that `NullSafeSupabaseStreamFilters` calls, so
/// the generated extension body resolves. Extends [SupabaseStreamBuilder]
/// because those extension methods return `this` when the value is null.
class SupabaseStreamFilterBuilder extends SupabaseStreamBuilder {
  const SupabaseStreamFilterBuilder();

  SupabaseStreamBuilder eq(String column, Object value) => this;

  SupabaseStreamBuilder neq(String column, Object value) => this;

  SupabaseStreamBuilder lt(String column, Object value) => this;

  SupabaseStreamBuilder lte(String column, Object value) => this;

  SupabaseStreamBuilder gt(String column, Object value) => this;

  SupabaseStreamBuilder gte(String column, Object value) => this;

  SupabaseStreamBuilder inFilter(String column, List<Object> values) => this;
}
