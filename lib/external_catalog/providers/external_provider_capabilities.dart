/// היכולות של ספק ספרים חיצוני.
///
/// הכלל שהמחלקה הזו אוכפת: פעולה בממשק נקבעת לפי **יכולת**, לא לפי שם
/// המחלקה של הספר או לפי ניחוש מתוך הקישור. כך ספק חדש אינו דורש `switch`
/// נוסף בכל מסך.
class ExternalProviderCapabilities {
  /// האם ניתן לפתוח את הספר באתר הספק בדפדפן.
  final bool webOpen;

  /// האם ניתן לפתוח את הספר בתוכנה מותקנת על המחשב.
  final bool localOpen;

  /// האם ניתן להוריד PDF של הספר.
  final bool pdfDownload;

  const ExternalProviderCapabilities({
    this.webOpen = false,
    this.localOpen = false,
    this.pdfDownload = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ExternalProviderCapabilities &&
      other.webOpen == webOpen &&
      other.localOpen == localOpen &&
      other.pdfDownload == pdfDownload;

  @override
  int get hashCode => Object.hash(webOpen, localOpen, pdfDownload);
}
