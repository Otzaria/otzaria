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

  @override
  Widget? buildImageWidget(BuildTree meta, ImageSource src) {
    final url = src.url;
    if (!_sizedDataImage.hasMatch(url)) {
      return super.buildImageWidget(meta, src);
    }
    final bytes = bytesFromDataUri(url);
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
