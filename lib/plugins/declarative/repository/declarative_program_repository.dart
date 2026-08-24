import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_program_executor.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';

typedef DeclarativeProgramRun =
    Future<DeclarativeProgramResult> Function({
      required CompiledDeclarativeProgram program,
      required InstalledPlugin plugin,
      required Set<String> grantedPermissions,
      required Map<String, dynamic> context,
    });

typedef DeclarativeProgramErrorHandler =
    void Function(
      String pluginId,
      String programId,
      Object error,
      StackTrace stackTrace,
    );

class DeclarativeProgramRepository extends ChangeNotifier {
  /// טריגרים שאינם תלויים בהקשר הקריאה. תכנית שכל הטריגרים שלה כאן שומרת
  /// את הפלט שלה ביציאה מספר — אחרת פקד שנקשר אליה לא היה חוזר.
  static const Set<String> contextFreeTriggers = {
    'app.startup',
    'settings.changed',
  };

  final DeclarativeProgramRun _runProgram;
  final DeclarativeProgramErrorHandler? onError;

  DeclarativeProgramRepository({
    DeclarativeProgramExecutor? executor,
    DeclarativeProgramRun? runProgram,
    this.onError,
  }) : assert(executor == null || runProgram == null),
       _runProgram =
           runProgram ?? (executor ?? DeclarativeProgramExecutor()).execute;

  final Map<String, _ProgramRegistration> _registrations = {};
  final Map<String, Map<String, Map<String, dynamic>>> _outputs = {};
  final Map<String, int> _generations = {};
  final Map<String, String> _contextSignatures = {};

  /// חתימת הריצה האחרונה של כל תכנית בנפרד. דור ברמת התוסף אינו מספיק:
  /// ריצה של טריגר אחד הייתה מבטלת ריצה של טריגר אחר שעדיין באוויר.
  final Map<String, Map<String, _RunStamp>> _programRuns = {};

  /// [preserveOutputs] — התכניות וההרשאות זהות לרישום הקיים, ולכן הפלט שחושב
  /// עדיין תקף ואין צורך להריץ מחדש (סנכרון של נעיצה/סדר).
  void syncPlugin({
    required InstalledPlugin plugin,
    required List<CompiledDeclarativeProgram> programs,
    required Set<String> grantedPermissions,
    bool preserveOutputs = false,
  }) {
    final existing = _registrations[plugin.pluginId];
    if (preserveOutputs &&
        existing != null &&
        plugin.enabled &&
        programs.isNotEmpty) {
      existing.plugin = plugin;
      return;
    }
    _invalidate(plugin.pluginId);
    if (!plugin.enabled || programs.isEmpty) {
      _registrations.remove(plugin.pluginId);
      return;
    }
    _registrations[plugin.pluginId] = _ProgramRegistration(
      plugin: plugin,
      programs: List.unmodifiable(programs),
      grantedPermissions: Set.unmodifiable(grantedPermissions),
    );
  }

  void removePlugin(String pluginId) {
    _invalidate(pluginId);
    _registrations.remove(pluginId);
  }

  void clearContexts() {
    var changed = _contextSignatures.isNotEmpty;
    for (final pluginId in _registrations.keys) {
      _generations[pluginId] = (_generations[pluginId] ?? 0) + 1;
    }
    for (final pluginId in {..._outputs.keys, ..._programRuns.keys}) {
      final programs = _registrations[pluginId]?.programs ?? const [];
      final retainedIds = {
        for (final program in programs)
          if (_isContextFree(program) && _ranWithoutContext(pluginId, program))
            program.id,
      };
      _programRuns[pluginId]?.removeWhere(
        (programId, _) => !retainedIds.contains(programId),
      );
      final outputs = _outputs[pluginId];
      if (outputs == null) continue;
      final retained = {
        for (final programId in retainedIds)
          if (outputs.containsKey(programId)) programId: outputs[programId]!,
      };
      if (retained.length != outputs.length) changed = true;
      if (retained.isEmpty) {
        _outputs.remove(pluginId);
      } else {
        _outputs[pluginId] = Map.unmodifiable(retained);
      }
    }
    _contextSignatures.clear();
    if (changed) notifyListeners();
  }

  /// פלט של תכנית שרצה כשספר היה פתוח עלול לשאת את זהות אותו ספר, ולכן
  /// אינו נשמר ביציאה ממנו — גם כשהטריגר עצמו אינו תלוי-הקשר.
  bool _ranWithoutContext(
    String pluginId,
    CompiledDeclarativeProgram program,
  ) => _programRuns[pluginId]?[program.id]?.contextBound == false;

  bool _isContextFree(CompiledDeclarativeProgram program) =>
      program.triggers.every(contextFreeTriggers.contains);

  /// [pluginIds] מגביל את הריצה לתוספים מסוימים — לטריגר `app.startup`
  /// שמופעל פעם אחת לכל תוסף.
  Future<void> runTrigger({
    required String trigger,
    required Map<String, dynamic> context,
    required String contextSignature,
    Set<String>? pluginIds,
  }) async {
    final pending = <Future<void>>[];
    var clearedAny = false;
    final contextBound = context.isNotEmpty;
    for (final entry in _registrations.entries.toList()) {
      if (pluginIds != null && !pluginIds.contains(entry.key)) continue;
      final relevant = entry.value.programs
          .where((program) => program.triggers.contains(trigger))
          .toList();
      if (relevant.isEmpty) continue;
      final pluginId = entry.key;
      final generation = (_generations[pluginId] ?? 0) + 1;
      _generations[pluginId] = generation;
      _contextSignatures[pluginId] = contextSignature;
      final runs = _programRuns.putIfAbsent(pluginId, () => {});
      for (final program in relevant) {
        runs[program.id] = _RunStamp(generation, contextBound);
      }
      if (_dropOutputs(pluginId, relevant)) clearedAny = true;
      pending.add(
        _runPluginGeneration(
          registration: entry.value,
          programs: relevant,
          generation: generation,
          context: Map.unmodifiable(context),
        ),
      );
    }
    if (clearedAny) notifyListeners();
    await Future.wait(pending);
  }

  /// מפנה את הפלט של התכניות שמתחילות לרוץ; פלט של טריגר אחר נשמר.
  bool _dropOutputs(
    String pluginId,
    List<CompiledDeclarativeProgram> programs,
  ) {
    final outputs = _outputs[pluginId];
    if (outputs == null) return false;
    final next = Map<String, Map<String, dynamic>>.from(outputs);
    var changed = false;
    for (final program in programs) {
      if (next.remove(program.id) != null) changed = true;
    }
    if (next.isEmpty) {
      _outputs.remove(pluginId);
    } else if (changed) {
      _outputs[pluginId] = Map.unmodifiable(next);
    }
    return changed;
  }

  Map<String, dynamic>? getProgramOutputs(
    String pluginId,
    String programId,
  ) {
    return _outputs[pluginId]?[programId];
  }

  Map<String, Map<String, dynamic>> getPluginOutputs(String pluginId) {
    return UnmodifiableMapView(_outputs[pluginId] ?? const {});
  }

  String? getContextSignature(String pluginId) => _contextSignatures[pluginId];

  int getGeneration(String pluginId) => _generations[pluginId] ?? 0;

  Future<void> _runPluginGeneration({
    required _ProgramRegistration registration,
    required List<CompiledDeclarativeProgram> programs,
    required int generation,
    required Map<String, dynamic> context,
  }) async {
    final completed = <String, Map<String, dynamic>>{};
    for (final program in programs) {
      try {
        final result = await _runProgram(
          program: program,
          plugin: registration.plugin,
          grantedPermissions: registration.grantedPermissions,
          context: context,
        );
        completed[program.id] = result.outputs;
      } catch (error, stackTrace) {
        onError?.call(
          registration.plugin.pluginId,
          program.id,
          error,
          stackTrace,
        );
        completed[program.id] = const {};
      }
    }

    final pluginId = registration.plugin.pluginId;
    if (!identical(_registrations[pluginId], registration)) return;
    // רק תכניות שהריצה הזו היא עדיין האחרונה שלהן מפרסמות פלט; ריצה של
    // טריגר אחר, או יציאה מספר, מפקיעה את התכניות שלה בלבד.
    final runs = _programRuns[pluginId];
    final fresh = {
      for (final entry in completed.entries)
        if (runs?[entry.key]?.generation == generation) entry.key: entry.value,
    };
    if (fresh.isEmpty) return;
    _outputs[pluginId] = Map.unmodifiable({...?_outputs[pluginId], ...fresh});
    notifyListeners();
  }

  void _invalidate(String pluginId) {
    _generations[pluginId] = (_generations[pluginId] ?? 0) + 1;
    _contextSignatures.remove(pluginId);
    _programRuns.remove(pluginId);
    if (_outputs.remove(pluginId) != null) notifyListeners();
  }
}

class _RunStamp {
  final int generation;

  /// האם ההקשר שהועבר לריצה כלל ספר פתוח.
  final bool contextBound;

  const _RunStamp(this.generation, this.contextBound);
}

class _ProgramRegistration {
  /// מתעדכן בסנכרון שאינו נוגע לתכניות, כדי לא לפסול פלט שחושב.
  InstalledPlugin plugin;
  final List<CompiledDeclarativeProgram> programs;
  final Set<String> grantedPermissions;

  _ProgramRegistration({
    required this.plugin,
    required this.programs,
    required this.grantedPermissions,
  });
}
