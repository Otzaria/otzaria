part of 'tikkun_korim_bloc.dart';

sealed class TikkunKorimEvent extends Equatable {
  const TikkunKorimEvent();

  @override
  List<Object?> get props => [];
}

/// טעינה ראשונה: הגדרות, מצב ניווט אחרון ופרשת השבוע (לפי [startupMode]).
class TikkunStarted extends TikkunKorimEvent {
  const TikkunStarted();
}

class TikkunSectionChanged extends TikkunKorimEvent {
  final TikkunSection section;
  const TikkunSectionChanged(this.section);

  @override
  List<Object?> get props => [section];
}

class TikkunMethodChanged extends TikkunKorimEvent {
  final String methodId;
  const TikkunMethodChanged(this.methodId);

  @override
  List<Object?> get props => [methodId];
}

/// חומש (בתורה) או ספר נביאים/כתובים — לפי המדור הנוכחי.
class TikkunBookChanged extends TikkunKorimEvent {
  final String bookId;
  const TikkunBookChanged(this.bookId);

  @override
  List<Object?> get props => [bookId];
}

class TikkunParashaChanged extends TikkunKorimEvent {
  final String parashaName;
  const TikkunParashaChanged(this.parashaName);

  @override
  List<Object?> get props => [parashaName];
}

/// `null` = "כל הפרשה".
class TikkunAliyaSelected extends TikkunKorimEvent {
  final int? aliyaIdx;
  const TikkunAliyaSelected(this.aliyaIdx);

  @override
  List<Object?> get props => [aliyaIdx];
}

class TikkunChapterSelected extends TikkunKorimEvent {
  final int chapter;
  const TikkunChapterSelected(this.chapter);

  @override
  List<Object?> get props => [chapter];
}

class TikkunHaftarahChanged extends TikkunKorimEvent {
  final String haftarahId;
  const TikkunHaftarahChanged(this.haftarahId);

  @override
  List<Object?> get props => [haftarahId];
}

class TikkunReadingChanged extends TikkunKorimEvent {
  final String readingId;
  const TikkunReadingChanged(this.readingId);

  @override
  List<Object?> get props => [readingId];
}

class TikkunColumnSelected extends TikkunKorimEvent {
  final int index;
  const TikkunColumnSelected(this.index);

  @override
  List<Object?> get props => [index];
}

class TikkunNextColumn extends TikkunKorimEvent {
  const TikkunNextColumn();
}

class TikkunPrevColumn extends TikkunKorimEvent {
  const TikkunPrevColumn();
}

class TikkunSettingsUpdated extends TikkunKorimEvent {
  final TikkunSettings settings;
  const TikkunSettingsUpdated(this.settings);

  @override
  List<Object?> get props => [settings];
}

/// החלפה זמנית בין הטור הגלוי למוסתר — אינה נשמרת.
class TikkunPeekToggled extends TikkunKorimEvent {
  const TikkunPeekToggled();
}

/// השורה הראשונה הגלויה השתנתה — מסנכרן את בוררי הסרגל.
class TikkunVisibleLineChanged extends TikkunKorimEvent {
  final int lineIdx;
  const TikkunVisibleLineChanged(this.lineIdx);

  @override
  List<Object?> get props => [lineIdx];
}

/// התצוגה ביצעה את בקשת הגלילה האחרונה.
class TikkunScrollHandled extends TikkunKorimEvent {
  const TikkunScrollHandled();
}
