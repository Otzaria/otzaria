part of 'context_menu_region.dart';

class _PreserveSelectionSecondaryTapRecognizer extends EagerGestureRecognizer {
  _PreserveSelectionSecondaryTapRecognizer({required this.shouldPreserve})
    : super(allowedButtonsFilter: (buttons) => buttons & kSecondaryButton != 0);

  final bool Function(Offset globalPosition) shouldPreserve;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (shouldPreserve(event.position)) {
      super.addAllowedPointer(event); // resolve(accepted) — זכייה מיידית
    }
    // אחרת: לא מצטרפים לזירה — SelectableRegion מטפל כרגיל (בחירה ריקה ממילא).
  }

  @override
  String get debugDescription => 'preserve-selection secondary tap';
}

// זוכה לפני ה-deadline שמנקה בחירה; גרירה מאוחרת מועברת ל-Scrollable
// שנדחה בזירת המחוות, כדי שלא ייווצר חלון מגע מת.

class _PreserveSelectionLongPressRecognizer
    extends PrimaryPointerGestureRecognizer {
  _PreserveSelectionLongPressRecognizer({
    required this.shouldPreserve,
    required this.onOpenMenu,
    required this.startScroll,
  }) : super(
         deadline: _winDeadline,
         postAcceptSlopTolerance: null,
         supportedDevices: const {
           PointerDeviceKind.touch,
           PointerDeviceKind.stylus,
           PointerDeviceKind.invertedStylus,
         },
         allowedButtonsFilter: _primaryOnly,
       );

  /// חייב להיות קטן מ-kPressTimeout — הזכייה דוחה את SelectableRegion מהזירה
  /// לפני שה-deadline שלו מריץ clearSelection.
  static final Duration _winDeadline =
      kPressTimeout - const Duration(milliseconds: 10);

  static bool _primaryOnly(int buttons) => buttons & kPrimaryButton != 0;

  final bool Function(Offset globalPosition) shouldPreserve;
  final void Function(Offset globalPosition) onOpenMenu;
  final ({Drag drag, Axis axis})? Function(
    DragStartDetails details,
    VoidCallback onCanceled,
  )
  startScroll;

  Timer? _menuTimer;
  ({Drag drag, Axis axis})? _scroll;
  bool _accepted = false;
  bool _menuOpened = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (shouldPreserve(event.position)) {
      super.addAllowedPointer(event);
    }
    // אחרת: לא מצטרפים לזירה — מגע מחוץ לבחירה מתנהג כרגיל.
  }

  @override
  void didExceedDeadline() {
    resolve(GestureDisposition.accepted);
  }

  @override
  void acceptGesture(int pointer) {
    super.acceptGesture(pointer);
    if (pointer != primaryPointer || _menuTimer != null) return;
    _accepted = true;
    final position = initialPosition?.global;
    if (position == null) return;
    _menuTimer = Timer(kLongPressTimeout - _winDeadline, () {
      _menuTimer = null;
      _menuOpened = true;
      onOpenMenu(position);
    });
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (event is PointerMoveEvent && _accepted) {
      _handleAcceptedMove(event);
      return;
    }
    if (event is PointerUpEvent) {
      if (_scroll case final scroll?) {
        scroll.drag.end(
          DragEndDetails(
            primaryVelocity: 0,
            velocity: Velocity.zero,
            globalPosition: event.position,
            localPosition: event.localPosition,
          ),
        );
        _scroll = null;
      }
      // Winning early only protects the selection. Releasing before the
      // long-press timer expires is still a tap, not a context-menu request.
      _cancelMenuTimer();
      resolve(GestureDisposition.rejected);
      return;
    }
    if (event is PointerCancelEvent) {
      _scroll?.drag.cancel();
      _scroll = null;
      _cancelMenuTimer();
      resolve(GestureDisposition.rejected);
    }
  }

  void _handleAcceptedMove(PointerMoveEvent event) {
    if (_menuOpened) return;
    if (_scroll == null) {
      final initial = initialPosition;
      if (initial == null ||
          (event.position - initial.global).distance <=
              computeHitSlop(event.kind, gestureSettings)) {
        return;
      }
      _cancelMenuTimer();
      _scroll = startScroll(
        DragStartDetails(
          sourceTimeStamp: event.timeStamp,
          globalPosition: initial.global,
          localPosition: initial.local,
          kind: event.kind,
        ),
        () => _scroll = null,
      );
    }

    final scroll = _scroll;
    if (scroll == null) return;
    scroll.drag.update(
      DragUpdateDetails(
        sourceTimeStamp: event.timeStamp,
        delta: event.delta,
        primaryDelta: scroll.axis == Axis.vertical
            ? event.delta.dy
            : event.delta.dx,
        globalPosition: event.position,
        localPosition: event.localPosition,
      ),
    );
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _scroll?.drag.cancel();
    _scroll = null;
    _cancelMenuTimer();
    _accepted = false;
    _menuOpened = false;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void dispose() {
    _scroll?.drag.cancel();
    _scroll = null;
    _cancelMenuTimer();
    super.dispose();
  }

  void _cancelMenuTimer() {
    _menuTimer?.cancel();
    _menuTimer = null;
  }

  @override
  String get debugDescription => 'preserve-selection long press';
}
