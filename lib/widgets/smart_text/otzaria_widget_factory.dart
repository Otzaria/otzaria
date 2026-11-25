import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:fwfh_svg/fwfh_svg.dart';
import 'package:fwfh_url_launcher/fwfh_url_launcher.dart';
import 'package:otzaria/widgets/smart_text/display_sized_memory_image.dart';

/// WidgetFactory לכל HtmlWidget באפליקציה: SVG (מ-EPUB/Markdown), פתיחת
/// קישור חיצוני כש-onTapUrl לא טיפל בו, ותמונות data: בגודל התצוגה.
class OtzariaWidgetFactory extends WidgetFactory
    with SvgFactory, UrlLauncherFactory {
  static final _sizedDataImage = RegExp(r'^data:image/(png|jpe?g);');

  /// הבתים שכבר פוענחו מ-[_decodedUri], כדי ש-fwfh לא יפענח את ה-base64 שוב.
  String? _decodedUri;
  Uint8List? _decodedBytes;

  // הבתים ומקור התמונה חיים כל עוד הווידג'ט מציג אותם; המטמון אינו מאריך את חייהם.
  final _recentImages =
      <int, (WeakReference<ImageSource>, WeakReference<Uint8List>)>{};

  Uint8List? _imageBytes(ImageSource src) {
    final hash = src.url.hashCode;
    final cached = _recentImages.remove(hash);
    final previous = cached?.$1.target?.url == src.url
        ? cached?.$2.target
        : null;
    final bytes = previous ?? bytesFromDataUri(src.url);
    if (bytes != null) {
      _recentImages[hash] = (WeakReference(src), WeakReference(bytes));
      if (_recentImages.length > 8) {
        _recentImages.remove(_recentImages.keys.first);
      }
    }
    return bytes;
  }

  @override
  Widget? buildImageWidget(BuildTree meta, ImageSource src) {
    final url = src.url;
    if (!_sizedDataImage.hasMatch(url)) {
      return super.buildImageWidget(meta, src);
    }
    final bytes = _imageBytes(src);
    final pixelSize = bytes == null ? null : encodedImagePixelSize(bytes);
    if (bytes == null || pixelSize == null) {
      _decodedUri = url;
      _decodedBytes = bytes;
      try {
        return super.buildImageWidget(meta, src);
      } finally {
        _decodedUri = _decodedBytes = null;
      }
    }
    final image = src.image;
    return DisplaySizedMemoryImage(
      bytes: bytes,
      pixelWidth: pixelSize.width,
      pixelHeight: pixelSize.height,
      semanticLabel: image?.alt ?? image?.title,
      errorBuilder: (context, error, _) =>
          onErrorBuilder(context, meta, error, src) ?? widget0,
    );
  }

  @override
  ImageProvider? imageProviderFromDataUri(String dataUri) {
    if (!identical(dataUri, _decodedUri)) {
      return super.imageProviderFromDataUri(dataUri);
    }
    final bytes = _decodedBytes;
    return bytes == null ? null : MemoryImage(bytes);
  }
}
