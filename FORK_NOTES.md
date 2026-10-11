# FORK_NOTES — `postgrest` 2.4.2 (Factura)

This is a **private fork of [`postgrest` 2.4.2](https://pub.dev/packages/postgrest)**
whose only purpose is to make FlutterFlow's generated Postgres backend compile.

It is consumed by the FlutterFlow project `factura-d7br62` through a
**dependency override** with a Git source:

```yaml
dependency_overrides:
  postgrest:
    git:
      url: <this repo>
      ref: <commit sha>
```

`dependencies` still pins `postgrest: 2.4.2` (FlutterFlow's own template), and
the override swaps in this fork.

---

## Why this fork exists

FlutterFlow's code generator emits `lib/backend/postgres/` unconditionally
whenever the app uses a Postgres/Supabase backend. Two of those generated files
are **incompatible with the `postgrest` version FlutterFlow itself pins**, and
they cannot be edited because they are regenerated on every build.

Upstream bug: **FlutterFlow/flutterflow-issues#7402** — *“Chrome Preview fails
to compile due to generated Supabase/PostgREST compatibility error”*. Closed
automatically as stale; **never fixed**.

That produced **34 compile errors**, all inside generated code:

| # | Errors | Cause |
|---|---|---|
| 1 | 8 × `UNDEFINED_CLASS` + 23 × `AMBIGUOUS_EXTENSION_MEMBER_ACCESS` | `table.dart` extends `SupabaseStreamFilterBuilder` and returns `SupabaseStreamBuilder`; neither type exists in `postgrest`, and `database.dart` only re-exports `package:postgrest`. |
| 2 | 1 × `MISSING_REQUIRED_ARGUMENT`, 1 × `EXTRA_POSITIONAL_ARGUMENTS_COULD_BE_NAMED`, 1 × `ARGUMENT_TYPE_NOT_ASSIGNABLE` | `postgres.dart` is written against the **postgrest 1.x** API: `PostgrestQueryBuilder` is called with a positional `url`, and `PostgrestClient.schema` is read as a getter. |

### The cascade

Because `SupabaseStreamFilterBuilder` is undefined, Dart types it as
`InvalidType`. `InvalidType` is simultaneously a subtype and a supertype of
everything, so `NullSafeSupabaseStreamFilters` becomes applicable to *every*
receiver — and `eqOrNull` turns ambiguous against `NullSafePostgrestFilters` at
every `PostgrestFilterBuilder` call site:

```
A member named 'eqOrNull' is defined in
'extension NullSafePostgrestFilters on PostgrestFilterBuilder<dynamic>' and
'extension NullSafeSupabaseStreamFilters on InvalidType',
and neither is more specific.
```

**31 of the 34 errors are this single defect.** Defining the two types fixes
all of them at once.

---

## The three changes

### 1. `lib/src/supabase_stream_builder.dart` (new file, exported)

Adds minimal, behaviour-free stand-ins for `SupabaseStreamBuilder` and
`SupabaseStreamFilterBuilder`, and exports them from `lib/postgrest.dart`.

```dart
class SupabaseStreamFilterBuilder extends SupabaseStreamBuilder {
  SupabaseStreamBuilder eq(String column, Object value) => this;
  // ... neq, lt, lte, gt, gte, inFilter
}
```

`SupabaseStreamFilterBuilder` **extends** `SupabaseStreamBuilder` because the
generated extension returns `this` when a value is null.

These classes are never instantiated — the app's Postgres backend only ever
builds `PostgrestFilterBuilder` queries. They exist purely so that the
generated extension type-checks.

### 2. `PostgrestQueryBuilder` — positional `url`

Upstream 2.4.2:

```dart
PostgrestQueryBuilder({required Uri url, String? method, ...})
```

Generated call site:

```dart
PostgrestQueryBuilder<T>(
  '${FFPostgresClient.client.url}/$table',   // positional String
  headers: ..., schema: ..., httpClient: ...,
);
```

Dart forbids mixing optional positional and named parameters, so `url` becomes
positional and accepts `String` or `Uri`:

```dart
PostgrestQueryBuilder(Object url, {String? method, ...})
```

This matches the shape `PostgrestRpcBuilder` already has upstream, which is
what FlutterFlow's template was originally written against.

Internal call sites updated: `PostgrestClient.from()` and
`PostgrestQueryBuilder.setHeader()`.

### 3. `PostgrestClient.schema` — getter

Upstream declares a **method** `PostgrestClient schema(String schema)`. The
generated `postgres.dart` reads it as a **getter** and forwards it to
`PostgrestQueryBuilder(schema:)`, yielding the tear-off
`PostgrestClient Function(String)` where `String?` is expected.

`schema` is now a getter returning `_schema`, and the schema-selection method is
preserved under a new name, **`withSchema(String)`**.

---

## The two runtime changes (added 2026-10-12)

Changes 1–3 made the generated code **compile**. These two make it **work**:
without them, every write to the database failed at runtime against Neon's
PostgREST. Both are in `lib/src/postgrest_transform_builder.dart`.

### 4. `select()` emitted a malformed `Prefer` header

`insert()`, `update()` and `delete()` in `postgrest_query_builder.dart` seed the
header as an **empty string**, not `null`:

```dart
newHeaders['Prefer'] = '';
```

Upstream `select()` then did:

```dart
if (newHeaders['Prefer'] != null) {              // '' is not null — always true
  newHeaders['Prefer'] = '${newHeaders['Prefer']},';
}
newHeaders['Prefer'] = '${newHeaders['Prefer']}return=representation';
```

which produces **`Prefer: ,return=representation`** — a leading comma. PostgREST
rejects it outright:

```
400 {"message":"\"failed to parse Prefer header (,return=representation)\"",
     "code":"PGRST100"}
```

Fixed by only inserting the separator when a non-empty `Prefer` is already
present, and by not string-interpolating a possible `null`.

### 5. `limit()` / `range()` are rejected on mutations

Neon's PostgREST refuses `limit`/`offset` on **any** mutation — POST, PATCH and
DELETE alike:

```
POST   /profiles?select=*&limit=1  -> 400 PGRST114
PATCH  /profiles?limit=1           -> 400 PGRST114
DELETE /profiles?limit=1           -> 400 PGRST114
GET    /profiles?select=*&limit=1  -> 200
```

```
{"message":"limit/offset querystring parameters are not allowed for PUT",
 "code":"PGRST114"}
```

(the message says PUT but the restriction covers all mutations)

FlutterFlow's generated `lib/backend/postgres/database/table.dart` appends
`.limit(1)` to **both** `insert()` and `upsert()`:

```dart
Future<T> insert(Map<String, dynamic> data) => FFPostgresClient.client
    .from(tableName).insert(data).select().limit(1).single().then(createRow);
```

So **every write in the app failed**. Since the file is regenerated on each
build and cannot be edited, the fork makes `limit()` and `range()` no-ops when
the request is a mutation (`referencedTable == null` only — limits on embedded
resources belong to the `select` and are left alone).

Dropping the limit is behaviour-preserving: on a mutation it only bounds the
rows *returned*, and a single-row insert/upsert returns one row anyway.

---

## Verification

The fix was validated before deployment by pointing a locally exported copy of
the generated project at this fork:

```
before:  analyzed_files=87  errors=38
after :  analyzed_files=87  errors=4
```

The 4 remaining errors are artifacts of substituting `dropdown_button2` locally
(the real dependency is a Git fork that cannot be resolved without a `git`
subprocess) — they do **not** exist in FlutterFlow's build. Measured against
FlutterFlow's own build output, the delta is **34 → 0**.

---

## Maintenance

Rebasing onto a newer upstream release requires re-applying the three changes
above; they are each marked with a `FORK:` / `FORK ADDITION` comment in the
source. The upstream tarball is a single `curl`:

```bash
curl -sL -o pg.tar.gz https://pub.dev/api/archives/postgrest-<version>.tar.gz
```

If FlutterFlow ever fixes #7402, delete this fork and the override.

## License

MIT, inherited from upstream — see `LICENSE`.
