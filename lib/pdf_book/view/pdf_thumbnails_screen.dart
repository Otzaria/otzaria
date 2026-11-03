import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:otzaria/pdf_book/utils/bounded_image_cache.dart';
import 'package:otzaria/pdf_book/utils/pdf_image_budget.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/theme/app_motion.dart';

class ThumbnailsView extends StatefulWidget {
  const ThumbnailsView({
    required this.documentRef,
    required this.controller,
    this.onNavigateToPage,
    this.shownPagesFor,
    this.thumbnailCache,
    this.isPaneOpen = true,
    super.key,
  });

  final PdfDocumentRef? documentRef;
  final PdfViewerController? controller;

  /// ניווט של המסך (שומר זום ונעילת זוגות); בלעדיו goToPage מאפס את הזום.
  final Future<void> Function(int pageNumber)? onNavigateToPage;

  /// העמודים שמוצגים יחד עם [pageNumber] — בתצוגת ספר כל הכפולה מודגשת.
  final ({int startPage, int endPageExclusive}) Function(int pageNumber)?
  shownPagesFor;

  /// מטמון של הבעלים, שמרוקן אותו כשהטאב מוסתר; בלעדיו לתצוגה יש מטמון משלה.
  final PdfThumbnailCache? thumbnailCache;

  /// חלונית סגורה או לשונית מוסתרת נשארות בעץ; בלי זה כל דפדוף גולל ובונה אותן.
  final bool isPaneOpen;

  @override
  State<ThumbnailsView> createState() => _ThumbnailsViewState();
}

class _ThumbnailsViewState extends State<ThumbnailsView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  bool _isManuallyScrolling = false;
  int? _lastScrolledPage;
  int? _lastKnownPage;

  PdfThumbnailCache? _ownCache;

  /// פריט שנגלל מחוץ למסך נבנה מחדש בחזרה; בלי המטמון העמוד היה מרונדר שוב.
  PdfThumbnailCache get _thumbnailCache =>
      widget.thumbnailCache ?? (_ownCache ??= createPdfThumbnailCache());

  /// גובה הפריט (250) ועוד השוליים (8 מכל צד) — גם לגלילה אל העמוד הנוכחי.
  static const double _itemExtent = 266;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _lastKnownPage = _currentPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
      _scrollToActiveItem();
    });
  }

  @override
  void didUpdateWidget(covariant ThumbnailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _lastKnownPage = _currentPage;
    }
    if (!oldWidget.isPaneOpen && widget.isPaneOpen) {
      // קפיצה ולא אנימציה: חלונית פתוחה הייתה כבר נמצאת בעמוד הנוכחי.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActiveItem(animate: false),
      );
    }
    if (oldWidget.documentRef != widget.documentRef) {
      _thumbnailCache.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
        _scrollToActiveItem();
      });
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _scrollController.dispose();
    _ownCache?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final page = _currentPage;
    if (page == _lastKnownPage) return;
    _lastKnownPage = page;
    if (!widget.isPaneOpen) {
      _lastScrolledPage = null;
      return;
    }
    setState(() {});
    _scrollToActiveItem();
  }

  int? get _currentPage => (widget.controller?.isReady ?? false)
      ? widget.controller!.pageNumber
      : null;

  void _scrollToActiveItem({bool animate = true}) {
    if (!mounted ||
        !widget.isPaneOpen ||
        _isManuallyScrolling ||
        !(widget.controller?.isReady ?? false)) {
      return;
    }
    final currentPage = widget.controller?.pageNumber;
    if (currentPage == null || _lastScrolledPage == currentPage) return;
    if (!_scrollController.hasClients) return;

    const itemExtent = _itemExtent;
    final viewportHeight = _scrollController.position.viewportDimension;
    final target =
        itemExtent * (currentPage - 1) -
        (viewportHeight / 2) +
        (itemExtent / 2);
    final offset = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (animate) {
      AppMotion.scrollPosition(
        _scrollController.position,
        offset,
        AppTokens.animPanelSlide,
      );
    } else {
      _scrollController.jumpTo(offset);
    }
    _lastScrolledPage = currentPage;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.documentRef == null) return const SizedBox.shrink();
    return PdfDocumentViewBuilder(
      documentRef: widget.documentRef!,
      builder: (context, document) => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _isManuallyScrolling = true;
          } else if (notification is ScrollEndNotification) {
            _isManuallyScrolling = false;
          }
          return false;
        },
        child: ListView.builder(
          key: const PageStorageKey('pdfThumbnails'),
          controller: _scrollController,
          itemExtent: _itemExtent,
          itemCount: document?.pages.length ?? 0,
          itemBuilder: (context, index) {
            final currentPage = _currentPage;
            final shown = currentPage == null
                ? null
                : widget.shownPagesFor?.call(currentPage) ??
                      (
                        startPage: currentPage,
                        endPageExclusive: currentPage + 1,
                      );
            final isSelected =
                shown != null &&
                index + 1 >= shown.startPage &&
                index + 1 < shown.endPageExclusive;
            return Container(
              margin: const EdgeInsets.all(8),
              height: 250,
              decoration: isSelected
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: AppTokens.borderRadiusAll,
                    )
                  : null,
              child: Column(
                children: [
                  SizedBox(
                    height: 220,
                    child: InkWell(
                      onTap: () =>
                          widget.onNavigateToPage?.call(index + 1) ??
                          widget.controller?.goToPage(
                            pageNumber: index + 1,
                            anchor: PdfPageAnchor.top,
                          ),
                      child: document == null || !widget.isPaneOpen
                          ? const SizedBox()
                          : _PageThumbnail(
                              page: document.pages[index],
                              cache: _thumbnailCache,
                            ),
                    ),
                  ),
                  Text('${index + 1}'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// עמוד שנמדד מחדש הוא אובייקט [PdfPage] חדש, ולכן תמונה ישנה לא תוחזר עבורו.
typedef PdfThumbnailCache =
    BoundedImageCache<(PdfPage page, int width, int height)>;

PdfThumbnailCache createPdfThumbnailCache() =>
    PdfThumbnailCache(maxBytes: 32 * 1024 * 1024, budget: pdfSharedImageBudget);

typedef _ThumbnailKey = (PdfPage page, int width, int height);

class _PageThumbnail extends StatefulWidget {
  const _PageThumbnail({required this.page, required this.cache});

  final PdfPage page;
  final PdfThumbnailCache cache;

  @override
  State<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<_PageThumbnail> {
  static const double _maximumDpi = 300;
  // ui-lint: allow UIL-030 — צל הנייר של עמוד PDF הוא תוכן (JX-05, q10 Q11)
  static const BoxShadow _pageShadow = BoxShadow(
    color: Colors.black54,
    blurRadius: 4,
    offset: Offset(2, 2),
  );

  ui.Image? _image;
  _ThumbnailKey? _requestedKey;
  _ThumbnailKey? _waitingForBudget;
  PdfImageCacheEntry? _imageBudgetEntry;
  PdfPageRenderCancellationToken? _cancellationToken;

  @override
  void initState() {
    super.initState();
    widget.cache.budget?.addListener(_budgetChanged);
  }

  @override
  void didUpdateWidget(covariant _PageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache.budget != widget.cache.budget) {
      oldWidget.cache.budget?.removeListener(_budgetChanged);
      widget.cache.budget?.addListener(_budgetChanged);
    }
  }

  void _budgetChanged() {
    if (!mounted || _waitingForBudget == null || _cancellationToken != null) {
      return;
    }
    _waitingForBudget = null;
    setState(() {});
  }

  void _releaseImage() {
    _imageBudgetEntry?.dispose();
    _imageBudgetEntry = null;
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    widget.cache.budget?.removeListener(_budgetChanged);
    _cancellationToken?.cancel();
    _releaseImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final page = widget.page;
        if (page.width <= 0 || page.height <= 0) return const SizedBox();
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final scale = math.min(
          _maximumDpi / 72,
          math.min(
            constraints.maxWidth * pixelRatio / page.width,
            constraints.maxHeight * pixelRatio / page.height,
          ),
        );
        final width = (page.width * scale).round();
        final height = (page.height * scale).round();
        if (width <= 0 || height <= 0) return const SizedBox();
        _requestImage((page, width, height));

        final image = _image;
        return Align(
          child: AspectRatio(
            aspectRatio: page.width / page.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // ui-lint: allow UIL-015 — נייר העמוד עד שתמונת ה־PDF נטענת (תוכן, DESIGN_SYSTEM §2.1.3)
                color: image == null ? Colors.white : null,
                boxShadow: const [_pageShadow],
              ),
              child: image == null
                  ? null
                  : RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
        );
      },
    );
  }

  /// נקרא מתוך build: פגיעה במטמון מוצגת באותה בנייה, ורינדור מסתיים ב-setState.
  void _requestImage(_ThumbnailKey key) {
    if (key == _requestedKey) return;
    _requestedKey = key;
    _waitingForBudget = null;
    _cancellationToken?.cancel();
    _cancellationToken = null;
    final cached = widget.cache.lookup(key);
    if (cached != null) {
      _adoptImage(cached, key);
      return;
    }
    _render(key);
  }

  bool _adoptImage(
    ui.Image image,
    _ThumbnailKey key, {
    PdfImageReservation? reservation,
  }) {
    final budget = widget.cache.budget;
    final allocation =
        reservation ?? _reserveImageBytes(image.width * image.height * 8);
    if (budget != null && allocation == null) {
      image.dispose();
      _requestedKey = null;
      _waitingForBudget = key;
      return false;
    }
    try {
      final entry = allocation?.commit(
        retainedBytes: image.width * image.height * 8,
        isPinned: true,
        onEvict: () {
          if (!identical(_image, image)) return;
          _releaseImage();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        },
      );
      if (budget != null && entry == null) {
        image.dispose();
        _requestedKey = null;
        _waitingForBudget = key;
        return false;
      }
      _releaseImage();
      _image = image;
      _imageBudgetEntry = entry;
      return true;
    } finally {
      allocation?.dispose();
    }
  }

  PdfImageReservation? _reserveImageBytes(int bytes) {
    final budget = widget.cache.budget;
    if (budget == null) return null;
    var reservation = budget.tryReserve(bytes);
    if (reservation == null && _image != null && bytes <= budget.maximumBytes) {
      _releaseImage();
      reservation = budget.tryReserve(bytes);
    }
    return reservation;
  }

  Future<void> _render(_ThumbnailKey key) async {
    final (page, width, height) = key;
    final generation = widget.cache.generation;
    final reservation = _reserveImageBytes(width * height * 12);
    if (widget.cache.budget != null && reservation == null) {
      _requestedKey = null;
      _waitingForBudget = key;
      return;
    }
    final token = _cancellationToken = page.createCancellationToken();
    try {
      final pageImage = await page.render(
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        cancellationToken: token,
        priority: PdfPageRenderPriority.low,
      );
      if (pageImage == null) return;
      try {
        if (!mounted ||
            token.isCanceled ||
            generation != widget.cache.generation) {
          return;
        }
        final image = await pageImage.createImage();
        if (!mounted ||
            key != _requestedKey ||
            token.isCanceled ||
            generation != widget.cache.generation) {
          image.dispose();
          return;
        }
        if (_adoptImage(image, key, reservation: reservation)) {
          widget.cache.put(key, image, generation: generation);
          setState(() {});
        }
      } finally {
        pageImage.dispose();
      }
    } catch (_) {
      // בלי איפוס הבקשה העמוד היה נשאר ריק עד שגודלו ישתנה.
      if (key == _requestedKey) _requestedKey = null;
    } finally {
      if (identical(_cancellationToken, token)) _cancellationToken = null;
      reservation?.dispose();
      if (mounted &&
          generation != widget.cache.generation &&
          key == _requestedKey) {
        _requestedKey = null;
        setState(() {});
      }
    }
  }
}
