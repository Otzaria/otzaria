import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';
import 'package:otzaria/app_report/services/app_report_image_sources.dart';
import 'package:otzaria/core/messages/messages_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/services/plugin_file_drop_service.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// אזור צירוף צילומי מסך לדיווח: הדבקה (מכל מקום בטופס), שחרור קובץ
/// או לחיצה לבחירת קובץ, ומתחתיו התמונות שצורפו.
class AppReportImagesSection extends StatefulWidget {
  const AppReportImagesSection({
    super.key,
    required this.images,
    required this.onChanged,
    this.enabled = true,
    this.sources = const AppReportImageSources(),
  });

  final List<AppReportImage> images;
  final ValueChanged<List<AppReportImage>> onChanged;
  final bool enabled;
  final AppReportImageSources sources;

  @override
  State<AppReportImagesSection> createState() => _AppReportImagesSectionState();
}

class _AppReportImagesSectionState extends State<AppReportImagesSection> {
  final _dropAreaKey = GlobalKey();
  PluginFileDropService get _dropService => PluginFileDropService.instance;
  StreamSubscription<PluginFileDrag>? _dropSubscription;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _dropService.acquire();
    _dropService.drag.addListener(_onDragChanged);
    _dropSubscription = _dropService.drops.listen(_onDrop);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _dropService.drag.removeListener(_onDragChanged);
    _dropSubscription?.cancel();
    _dropService.setZoneAccepting(this, false);
    _dropService.release();
    super.dispose();
  }

  /// מאזין להדבקה בכל הטופס, גם כשהפוקוס בשדה טקסט. לא בולע את המקש,
  /// כדי שהדבקת טקסט לשדה תמשיך לעבוד.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !widget.enabled) return false;
    if (!_isPasteShortcut(event)) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    unawaited(_paste());
    return false;
  }

  static bool _isPasteShortcut(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final isV =
        event.logicalKey == LogicalKeyboardKey.keyV ||
        event.physicalKey == PhysicalKeyboardKey.keyV;
    final modifier = !kIsWeb && Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    return (isV && modifier) ||
        (event.logicalKey == LogicalKeyboardKey.insert &&
            keyboard.isShiftPressed);
  }

  Future<void> _paste() async {
    final inTextField =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    try {
      _add(await widget.sources.readClipboard(skipIfText: inTextField));
    } catch (error, stackTrace) {
      debugPrint('App report clipboard read failed: $error\n$stackTrace');
    }
  }

  Future<void> _pick() async {
    try {
      _add(await widget.sources.pickFiles());
    } catch (error, stackTrace) {
      debugPrint('App report image pick failed: $error\n$stackTrace');
      UiSnack.showError(ReportMessages.appReportImageReadFailed);
    }
  }

  void _add(List<AppReportImage> incoming) {
    if (incoming.isEmpty || !mounted || !widget.enabled) return;
    final merged = mergeAppReportImages(widget.images, incoming);
    switch (merged.rejection) {
      case AppReportImageRejection.tooLarge:
        UiSnack.showError(
          ReportMessages.appReportImageTooLarge(
            AppReportImage.maxBytes ~/ 1000000,
          ),
        );
      case AppReportImageRejection.totalTooLarge:
        UiSnack.showError(
          ReportMessages.appReportImagesTotalTooLarge(
            AppReportImage.maxTotalBytes ~/ 1000000,
          ),
        );
      case AppReportImageRejection.tooMany:
        UiSnack.showError(
          ReportMessages.appReportTooManyImages(AppReportImage.maxCount),
        );
      case null:
        break;
    }
    if (merged.images.length != widget.images.length) {
      widget.onChanged(merged.images);
    }
  }

  void _remove(int index) {
    widget.onChanged([...widget.images]..removeAt(index));
  }

  static bool _hasImagePath(List<String> paths) =>
      paths.any((path) => AppReportImage.mimeTypeForPath(path) != null);

  /// האם הסמן מעל אזור השחרור. המיקום מגיע בפיקסלים פיזיים.
  bool _contains(Offset physicalPosition) {
    final box = _dropAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio <= 0) return false;
    final local = box.globalToLocal(physicalPosition / ratio);
    return box.size.contains(local);
  }

  void _onDragChanged() {
    final drag = _dropService.drag.value;
    final hovering =
        widget.enabled &&
        drag != null &&
        _hasImagePath(drag.paths) &&
        _contains(drag.physicalPosition);
    _dropService.setZoneAccepting(this, hovering);
    if (hovering != _isHovering) setState(() => _isHovering = hovering);
  }

  Future<void> _onDrop(PluginFileDrag drop) async {
    if (_isHovering) setState(() => _isHovering = false);
    if (!widget.enabled || !_contains(drop.physicalPosition)) return;
    if (!_hasImagePath(drop.paths)) return;
    try {
      _add(await widget.sources.readPaths(drop.paths));
    } catch (error, stackTrace) {
      debugPrint('App report image drop failed: $error\n$stackTrace');
      UiSnack.showError(ReportMessages.appReportImageReadFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prompt = PluginFileDropService.isSupported
        ? 'הדביקו, שחררו או הקליקו לבחירת תמונה'
        : 'הדביקו או הקליקו לבחירת תמונה';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: _dropAreaKey,
          color: _isHovering
              ? AppSurfaces.paneDropPreview(colorScheme)
              : colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _isHovering
                  ? AppSurfaces.paneDropPreviewBorder(colorScheme)
                  : colorScheme.outlineVariant,
              width: _isHovering ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('app-report-image-area'),
            onTap: widget.enabled ? _pick : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  Icon(
                    FluentIcons.image_add_24_regular,
                    color: widget.enabled
                        ? colorScheme.primary
                        : theme.disabledColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prompt,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (!kIsWeb && Platform.isWindows) ...[
                    const SizedBox(height: 4),
                    Text(
                      'צילום מכלי החיתוך (Win+Shift+S) נקלט בהדבקה — Ctrl+V',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (widget.images.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.images.length; i++)
                _ImageThumbnail(
                  key: ValueKey('app-report-image-$i'),
                  image: widget.images[i],
                  onRemove: widget.enabled ? () => _remove(i) : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({super.key, required this.image, this.onRemove});

  static const double _size = 72;

  final AppReportImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Tooltip(
      message: image.fileName,
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                image.bytes,
                fit: BoxFit.cover,
                cacheHeight: (_size * ratio).round(),
                errorBuilder: (_, _, _) => ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    FluentIcons.image_off_24_regular,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              PositionedDirectional(
                top: 2,
                end: 2,
                child: IconButton.filledTonal(
                  key: const ValueKey('app-report-image-remove'),
                  tooltip: 'הסרת התמונה',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                  icon: const Icon(FluentIcons.dismiss_16_regular),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
