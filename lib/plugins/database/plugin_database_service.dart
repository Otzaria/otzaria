import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3_pkg;
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'plugin_database_source.dart';
import 'plugin_database_registry.dart';

/// שגיאה מובנית בשירות מסד הנתונים לתוספים
class PluginDatabaseException implements Exception {
  final String code;
  final String message;

  const PluginDatabaseException(this.code, this.message);

  @override
  String toString() => 'PluginDatabaseException($code): $message';
}

class _CachedResult {
  final Map<String, dynamic> result;
  final DateTime timestamp;

  _CachedResult(this.result, this.timestamp);
}

/// שירות מרכזי לגישת תוספים למסדי נתונים SQLite.
///
/// מנהל:
/// - רזולוציה של מקורות
/// - ולידציה של בקשות מול policy
/// - קומפילציה ל-SQL פרמטרי
/// - ביצוע ב-read-only
/// - cache תוצאות קצר-מועד
class PluginDatabaseService {
  final PluginDatabaseRegistry _registry;

  final Map<String, sqlite3_pkg.Database> _connections = {};
  final Map<String, _CachedResult> _resultCache = {};

  static const _resultCacheTtl = Duration(seconds: 5);

  PluginDatabaseService({PluginDatabaseRegistry? registry})
    : _registry = registry ?? PluginDatabaseRegistry.instance;

  // ----------------------------------------------------------------
  // Public API
  // ----------------------------------------------------------------

  /// מחזיר רשימת מקורות שהוצהרו במניפסט וזמינים ב-registry
  List<Map<String, dynamic>> listSourcesForPlugin(InstalledPlugin plugin) {
    final result = <Map<String, dynamic>>[];
    for (final declared in plugin.manifest.databaseSources) {
      final sourceId = declared['id'] as String?;
      if (sourceId == null) continue;
      final source = _registry.getSource(sourceId);
      result.add({
        'id': sourceId,
        'label': source?.label ?? sourceId,
        'available': source != null && File(source.databasePath).existsSync(),
      });
    }
    return result;
  }

  /// מחזיר schema חשוף לתוסף (לפי policy בלבד)
  Map<String, dynamic> describeSource(InstalledPlugin plugin, String sourceId) {
    _ensureSourceDeclared(plugin, sourceId);
    final source = _resolveSource(sourceId);
    final policy = source.policy;

    final tables =
        policy.tables.map((tableName) {
          final cols = (policy.columnsByTable[tableName] ?? <String>{}).toList()
            ..sort();
          return {'name': tableName, 'columns': cols};
        }).toList()..sort(
          (a, b) => (a['name'] as String).compareTo(b['name'] as String),
        );

    return {
      'source': {'id': source.sourceId, 'label': source.label},
      'schema': {'tables': tables},
      'limits': {
        'maxLimit': policy.maxLimit,
        'maxBatchQueries': policy.maxBatchQueries,
      },
    };
  }

  /// ביצוע שאילתה דקלרטיבית
  Map<String, dynamic> query(
    InstalledPlugin plugin,
    Map<String, dynamic> spec,
  ) {
    final sourceId = spec['sourceId'] as String?;
    if (sourceId == null) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'sourceId is required',
      );
    }

    _ensureSourceDeclared(plugin, sourceId);
    final source = _resolveSource(sourceId);
    final policy = source.policy;

    // Validate (throws on any violation)
    _validateSpec(spec, policy);

    // Apply effective limits
    final rawLimit = (spec['limit'] as num?)?.toInt();
    final effectiveLimit = rawLimit != null
        ? min(rawLimit, policy.maxLimit)
        : policy.maxLimit;
    final offset = (spec['offset'] as num?)?.toInt() ?? 0;

    // Compile
    final compiled = _compileSpec(spec, effectiveLimit, offset);

    // Cache check
    final cacheKey =
        '$sourceId::${compiled.sql}::${jsonEncode(compiled.params)}';
    final cached = _resultCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _resultCacheTtl) {
      return cached.result;
    }

    // Execute (sqlite3 is synchronous — fetch limit+1 to detect hasMore)
    final db = _getConnection(source);
    final fetchLimit = effectiveLimit + 1;
    final compiledWithProbe = _compileSpec(spec, fetchLimit, offset);
    final sw = Stopwatch()..start();
    final resultSet = db.select(
      compiledWithProbe.sql,
      compiledWithProbe.params,
    );
    sw.stop();

    // Format
    final rowFormat = spec['rowFormat'] as String? ?? 'array';
    final columns = resultSet.columnNames;
    final hasMore = resultSet.length > effectiveLimit;
    final rawRows = hasMore
        ? resultSet.take(effectiveLimit).toList()
        : resultSet.toList();

    final List<dynamic> rows;
    if (rowFormat == 'object') {
      // בדיקת ייחוד שמות עמודות בפועל (לאחר ש-SQLite קבע את השמות)
      final seen = <String>{};
      for (final col in columns) {
        if (!seen.add(col)) {
          throw PluginDatabaseException(
            'database.invalid_spec',
            'Duplicate column name "$col" in result set — add "as" aliases to disambiguate',
          );
        }
      }
      rows = rawRows.map((row) {
        final obj = <String, dynamic>{};
        for (var i = 0; i < columns.length; i++) {
          obj[columns[i]] = row.columnAt(i);
        }
        return obj;
      }).toList();
    } else {
      rows = rawRows.map((row) => row.values.toList()).toList();
    }

    final result = {
      'meta': {
        'sourceId': sourceId,
        'rowCount': rows.length,
        'limit': effectiveLimit,
        'offset': offset,
        'hasMore': hasMore,
        'elapsedMs': sw.elapsedMilliseconds,
      },
      'columns': columns.map((c) => {'name': c}).toList(),
      'rows': rows,
    };

    _resultCache[cacheKey] = _CachedResult(result, DateTime.now());
    return result;
  }

  /// ביצוע batch של שאילתות
  List<Map<String, dynamic>> batchQuery(
    InstalledPlugin plugin,
    List<Map<String, dynamic>> queries,
  ) {
    if (queries.isEmpty) return [];

    for (final querySpec in queries) {
      final sourceId = querySpec['sourceId'] as String?;
      if (sourceId == null) continue;
      final source = _registry.getSource(sourceId);
      if (source != null && queries.length > source.policy.maxBatchQueries) {
        throw PluginDatabaseException(
          'database.query_too_large',
          'Batch exceeds maxBatchQueries (${source.policy.maxBatchQueries})',
        );
      }
    }

    return queries.map((q) => query(plugin, q)).toList();
  }

  // ----------------------------------------------------------------
  // Private: source resolution
  // ----------------------------------------------------------------

  void _ensureSourceDeclared(InstalledPlugin plugin, String sourceId) {
    final declared = plugin.manifest.databaseSources;
    if (!declared.any((s) => s['id'] == sourceId)) {
      throw PluginDatabaseException(
        'database.source_not_found',
        'Source "$sourceId" is not declared in plugin manifest',
      );
    }
  }

  PluginDatabaseSource _resolveSource(String sourceId) {
    final source = _registry.getSource(sourceId);
    if (source == null) {
      throw PluginDatabaseException(
        'database.source_unavailable',
        'Source "$sourceId" is not registered',
      );
    }
    if (!File(source.databasePath).existsSync()) {
      throw PluginDatabaseException(
        'database.source_unavailable',
        'Database file not found for source "$sourceId"',
      );
    }
    return source;
  }

  sqlite3_pkg.Database _getConnection(PluginDatabaseSource source) {
    return _connections.putIfAbsent(source.sourceId, () {
      final mode = source.readOnly
          ? sqlite3_pkg.OpenMode.readOnly
          : sqlite3_pkg.OpenMode.readWrite;
      return sqlite3_pkg.sqlite3.open(source.databasePath, mode: mode);
    });
  }

  // ----------------------------------------------------------------
  // Private: validation
  // ----------------------------------------------------------------

  /// מוודא את spec מול policy ומחזיר alias→table map
  Map<String, String> _validateSpec(
    Map<String, dynamic> spec,
    PluginDatabasePolicy policy,
  ) {
    final aliasMap = <String, String>{};

    // --- from ---
    final from = spec['from'] as Map<String, dynamic>?;
    if (from == null) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        '"from" is required',
      );
    }
    final fromTable = from['table'] as String?;
    if (fromTable == null) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        '"from.table" is required',
      );
    }
    if (!policy.isTableAllowed(fromTable)) {
      throw PluginDatabaseException(
        'database.table_not_allowed',
        'Table "$fromTable" is not allowed',
      );
    }
    final fromAlias = (from['alias'] as String?) ?? fromTable;
    _assertValidIdentifier(fromAlias, 'from.alias');
    aliasMap[fromAlias] = fromTable;

    // --- joins (first pass: build alias map) ---
    final joins = (spec['joins'] as List<dynamic>?) ?? [];
    if (joins.length > policy.maxJoins) {
      throw PluginDatabaseException(
        'database.query_too_large',
        'Too many joins (max: ${policy.maxJoins})',
      );
    }
    for (final join in joins) {
      final jm = join as Map<String, dynamic>;
      final joinTable = jm['table'] as String?;
      if (joinTable == null) {
        throw const PluginDatabaseException(
          'database.invalid_spec',
          'Join "table" is required',
        );
      }
      if (!policy.isTableAllowed(joinTable)) {
        throw PluginDatabaseException(
          'database.table_not_allowed',
          'Table "$joinTable" is not allowed',
        );
      }
      final joinAlias = (jm['alias'] as String?) ?? joinTable;
      _assertValidIdentifier(joinAlias, 'join.alias');
      aliasMap[joinAlias] = joinTable;

      final joinType = (jm['type'] as String? ?? 'inner').toLowerCase();
      if (joinType != 'inner' && joinType != 'left') {
        throw PluginDatabaseException(
          'database.invalid_spec',
          'Unsupported join type: "$joinType" (allowed: inner, left)',
        );
      }
    }

    // --- joins (second pass: validate ON conditions with complete alias map) ---
    for (final join in joins) {
      final jm = join as Map<String, dynamic>;
      final onConditions = (jm['on'] as List<dynamic>?) ?? [];
      if (onConditions.isEmpty) {
        final joinTable = jm['table'] as String;
        throw PluginDatabaseException(
          'database.invalid_spec',
          'Join on "$joinTable" must have at least one ON condition',
        );
      }
      for (final cond in onConditions) {
        final cm = cond as Map<String, dynamic>;
        final operator = cm['op'] as String?;
        final leftRef = cm['left'] as String?;
        final rightRef = cm['right'] as String?;
        if (leftRef == null || rightRef == null) {
          throw const PluginDatabaseException(
            'database.invalid_spec',
            'Join ON condition requires "left" and "right"',
          );
        }
        if (operator != '=') {
          throw PluginDatabaseException(
            'database.invalid_spec',
            'Join operator must be "=" (found: "${operator ?? ""}")',
          );
        }
        final left = _resolveRef(leftRef, aliasMap, policy);
        final right = _resolveRef(rightRef, aliasMap, policy);
        if (!policy.isJoinAllowed(left.$1, left.$2, right.$1, right.$2)) {
          throw PluginDatabaseException(
            'database.join_not_allowed',
            'Join "$leftRef = $rightRef" is not allowed by policy',
          );
        }
      }
    }

    // --- select ---
    final select = (spec['select'] as List<dynamic>?) ?? [];
    if (select.isEmpty) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'Select list must not be empty',
      );
    }
    if (select.length > policy.maxColumns) {
      throw PluginDatabaseException(
        'database.query_too_large',
        'Too many select columns (max: ${policy.maxColumns})',
      );
    }
    for (final sel in select) {
      final sm = sel as Map<String, dynamic>;
      final expr = sm['expr'] as String?;
      if (expr == null) {
        throw const PluginDatabaseException(
          'database.invalid_spec',
          'Select "expr" is required',
        );
      }
      _resolveRef(expr, aliasMap, policy);
      final alias = sm['as'] as String?;
      if (alias != null) {
        _assertValidIdentifier(alias, 'select.as');
      }
    }

    // ייחוד שמות פלט — רלוונטי במיוחד ל-rowFormat: object
    final outputNames = <String>{};
    for (final sel in select) {
      final sm = sel as Map<String, dynamic>;
      final outputName = (sm['as'] as String?) ?? (sm['expr'] as String);
      if (!outputNames.add(outputName)) {
        throw PluginDatabaseException(
          'database.invalid_spec',
          'Duplicate output column name: "$outputName" — use distinct "as" aliases',
        );
      }
    }

    // --- where ---
    final where = spec['where'] as Map<String, dynamic>?;
    if (where != null) {
      _validateWhere(where, aliasMap, policy, 0);
    }

    // --- orderBy ---
    final orderBy = (spec['orderBy'] as List<dynamic>?) ?? [];
    for (final ob in orderBy) {
      final om = ob as Map<String, dynamic>;
      final expr = om['expr'] as String?;
      if (expr == null) {
        throw const PluginDatabaseException(
          'database.invalid_spec',
          'orderBy "expr" is required',
        );
      }
      _resolveRef(expr, aliasMap, policy);
      final direction = (om['direction'] as String? ?? 'asc').toLowerCase();
      if (direction != 'asc' && direction != 'desc') {
        throw PluginDatabaseException(
          'database.invalid_spec',
          'Invalid ORDER BY direction: "$direction"',
        );
      }
    }

    // --- limit ---
    final limit = (spec['limit'] as num?)?.toInt();
    if (limit != null && limit > policy.maxLimit) {
      throw PluginDatabaseException(
        'database.query_too_large',
        'limit $limit exceeds maxLimit ${policy.maxLimit}',
      );
    }
    if (limit != null && limit < 0) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'limit must be non-negative',
      );
    }
    final offset = (spec['offset'] as num?)?.toInt();
    if (offset != null && offset < 0) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'offset must be non-negative',
      );
    }
    final rowFormat = spec['rowFormat'] as String?;
    if (rowFormat != null && rowFormat != 'array' && rowFormat != 'object') {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'rowFormat must be "array" or "object"',
      );
    }

    return aliasMap;
  }

  void _validateWhere(
    Map<String, dynamic> where,
    Map<String, String> aliasMap,
    PluginDatabasePolicy policy,
    int depth,
  ) {
    if (depth > 5) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'WHERE clause is too deeply nested',
      );
    }
    final op = where['op'] as String?;
    if (op == null) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'WHERE condition requires "op"',
      );
    }

    if (op == 'and' || op == 'or') {
      final conditions = where['conditions'] as List<dynamic>?;
      if (conditions == null || conditions.isEmpty) {
        throw PluginDatabaseException(
          'database.invalid_spec',
          'WHERE "$op" requires a non-empty "conditions" list',
        );
      }
      for (final cond in conditions) {
        _validateWhere(
          cond as Map<String, dynamic>,
          aliasMap,
          policy,
          depth + 1,
        );
      }
      return;
    }

    // Leaf condition
    final left = where['left'] as String?;
    if (left == null) {
      throw const PluginDatabaseException(
        'database.invalid_spec',
        'WHERE condition requires "left"',
      );
    }
    _resolveRef(left, aliasMap, policy);

    const validOps = {
      '=',
      '!=',
      '>',
      '>=',
      '<',
      '<=',
      'in',
      'between',
      'like',
      'isNull',
      'isNotNull',
    };
    if (!validOps.contains(op)) {
      throw PluginDatabaseException(
        'database.invalid_spec',
        'Unsupported WHERE operator: "$op"',
      );
    }

    if (op == 'in') {
      if (where['value'] is! List) {
        throw const PluginDatabaseException(
          'database.invalid_spec',
          '"in" operator requires a list value',
        );
      }
    }
    if (op == 'between') {
      final v = where['value'];
      if (v is! List || v.length != 2) {
        throw const PluginDatabaseException(
          'database.invalid_spec',
          '"between" operator requires a 2-element list value',
        );
      }
    }
  }

  /// מפרש ref בפורמט alias.column ומאמת מול policy.
  /// מחזיר (tableName, columnName).
  (String, String) _resolveRef(
    String ref,
    Map<String, String> aliasMap,
    PluginDatabasePolicy policy,
  ) {
    final parts = ref.split('.');
    if (parts.length != 2) {
      throw PluginDatabaseException(
        'database.invalid_spec',
        'Column reference must be in "alias.column" format: "$ref"',
      );
    }
    final alias = parts[0];
    final column = parts[1];
    _assertValidIdentifier(alias, 'column reference alias');
    _assertValidIdentifier(column, 'column name');

    final table = aliasMap[alias] ?? alias;
    if (!policy.isColumnAllowed(table, column)) {
      throw PluginDatabaseException(
        'database.column_not_allowed',
        'Column "$ref" ($table.$column) is not allowed',
      );
    }
    return (table, column);
  }

  void _assertValidIdentifier(String value, String context) {
    final re = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    if (!re.hasMatch(value)) {
      throw PluginDatabaseException(
        'database.invalid_spec',
        'Invalid identifier in $context: "$value"',
      );
    }
  }

  // ----------------------------------------------------------------
  // Private: SQL compilation
  // ----------------------------------------------------------------

  _CompiledQuery _compileSpec(
    Map<String, dynamic> spec,
    int effectiveLimit,
    int offset,
  ) {
    final params = <Object?>[];
    final sb = StringBuffer();

    // SELECT
    final select = (spec['select'] as List<dynamic>?) ?? [];
    final parts = select
        .map((s) {
          final sm = s as Map<String, dynamic>;
          final expr = sm['expr'] as String;
          final alias = sm['as'] as String?;
          return alias != null ? '$expr AS $alias' : expr;
        })
        .join(', ');
    sb.write('SELECT $parts');

    // FROM
    final from = spec['from'] as Map<String, dynamic>;
    final fromTable = from['table'] as String;
    final fromAlias = from['alias'] as String?;
    sb.write('\nFROM $fromTable');
    if (fromAlias != null && fromAlias != fromTable) {
      sb.write(' $fromAlias');
    }

    // JOINS
    for (final join in (spec['joins'] as List<dynamic>?) ?? []) {
      final jm = join as Map<String, dynamic>;
      final type = (jm['type'] as String? ?? 'inner').toUpperCase();
      final table = jm['table'] as String;
      final alias = jm['alias'] as String?;
      sb.write('\n$type JOIN $table');
      if (alias != null && alias != table) sb.write(' $alias');
      final onConds = (jm['on'] as List<dynamic>?) ?? [];
      if (onConds.isNotEmpty) {
        final onParts = onConds
            .map((c) {
              final cm = c as Map<String, dynamic>;
              return '${cm['left']} = ${cm['right']}';
            })
            .join(' AND ');
        sb.write(' ON $onParts');
      }
    }

    // WHERE
    final where = spec['where'] as Map<String, dynamic>?;
    if (where != null) {
      final clause = _compileWhere(where, params);
      sb.write('\nWHERE $clause');
    }

    // ORDER BY
    final orderBy = (spec['orderBy'] as List<dynamic>?) ?? [];
    if (orderBy.isNotEmpty) {
      final parts = orderBy
          .map((o) {
            final om = o as Map<String, dynamic>;
            final expr = om['expr'] as String;
            final dir = (om['direction'] as String? ?? 'asc').toUpperCase();
            return '$expr $dir';
          })
          .join(', ');
      sb.write('\nORDER BY $parts');
    }

    // LIMIT / OFFSET
    sb.write('\nLIMIT ?');
    params.add(effectiveLimit);
    sb.write('\nOFFSET ?');
    params.add(offset);

    return _CompiledQuery(sb.toString(), params);
  }

  String _compileWhere(Map<String, dynamic> where, List<Object?> params) {
    final op = where['op'] as String;

    if (op == 'and' || op == 'or') {
      final conditions = where['conditions'] as List<dynamic>;
      final parts = conditions
          .map((c) => _compileWhere(c as Map<String, dynamic>, params))
          .toList();
      return '(${parts.join(' ${op.toUpperCase()} ')})';
    }

    final left = where['left'] as String;

    switch (op) {
      case 'isNull':
        return '$left IS NULL';
      case 'isNotNull':
        return '$left IS NOT NULL';
      case 'in':
        final values = where['value'] as List;
        final placeholders = List.filled(values.length, '?').join(', ');
        params.addAll(values.cast<Object?>());
        return '$left IN ($placeholders)';
      case 'between':
        final values = where['value'] as List;
        params.add(values[0] as Object?);
        params.add(values[1] as Object?);
        return '$left BETWEEN ? AND ?';
      default:
        params.add(where['value'] as Object?);
        return '$left $op ?';
    }
  }
}

class _CompiledQuery {
  final String sql;
  final List<Object?> params;

  _CompiledQuery(this.sql, this.params);
}
