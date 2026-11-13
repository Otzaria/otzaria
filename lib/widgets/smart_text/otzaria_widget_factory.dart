import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:fwfh_svg/fwfh_svg.dart';
import 'package:fwfh_url_launcher/fwfh_url_launcher.dart';
import 'package:otzaria/widgets/smart_text/display_sized_memory_image.dart';

/// WidgetFactory לכל HtmlWidget באפליקציה: SVG (מ-EPUB/Markdown), פתיחת
/// קישור חיצוני כש-onTapUrl לא טיפל בו, ותמונות data: בגודל התצוגה.
class OtzariaWidgetFactory extends WidgetFactory
    with SvgFactory, UrlLauncherFactory {
  @override
  Widget? buildImageWidget(BuildTree meta, ImageSource src) {
    final url = src.url;
    final bytes = url.startsWith('data:image/') ? bytesFromDataUri(url) : null;
    final pixelSize = bytes == null ? null : encodedImagePixelSize(bytes);
    if (bytes == null || pixelSize == null) {
      return super.buildImageWidget(meta, src);
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
}
