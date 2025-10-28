import 'package:equatable/equatable.dart';

sealed class TextBookEvent extends Equatable {
  const TextBookEvent();

  @override
  List<Object?> get props => [];
}

class LoadContent extends TextBookEvent {
  final double fontSize;
  final bool showSplitView;
  final bool removeNikud;
  final bool preserveState; // Whether to preserve current state during reload

  const LoadContent({
    required this.fontSize,
    required this.showSplitView,
    required this.removeNikud,
    this.preserveState = false, // Default to false for backward compatibility
  });

  @override
  List<Object?> get props => [fontSize, showSplitView, removeNikud, preserveState];
}

class UpdateFontSize extends TextBookEvent {
  final double fontSize;

  const UpdateFontSize(this.fontSize);

  @override
  List<Object?> get props => [fontSize];
}

class ToggleLeftPane extends TextBookEvent {
  final bool show;

  const ToggleLeftPane(this.show);

  @override
  List<Object?> get props => [show];
}

class ToggleSplitView extends TextBookEvent {
  final bool show;

  const ToggleSplitView(this.show);

  @override
  List<Object?> get props => [show];
}

class UpdateCommentators extends TextBookEvent {
  final List<String> commentators;

  const UpdateCommentators(this.commentators);

  @override
  List<Object?> get props => [commentators];
}

class ToggleNikud extends TextBookEvent {
  final bool remove;

  const ToggleNikud(this.remove);

  @override
  List<Object?> get props => [remove];
}

class UpdateVisibleIndecies extends TextBookEvent {
  final List<int> visibleIndecies;

  const UpdateVisibleIndecies(this.visibleIndecies);

  @override
  List<Object?> get props => [visibleIndecies];
}

class UpdateSelectedIndex extends TextBookEvent {
  final int? index;

  const UpdateSelectedIndex(this.index);

  @override
  List<Object?> get props => [index];
}

class TogglePinLeftPane extends TextBookEvent {
  final bool pin;

  const TogglePinLeftPane(this.pin);

  @override
  List<Object?> get props => [pin];
}

class UpdateSearchText extends TextBookEvent {
  final String text;

  const UpdateSearchText(this.text);

  @override
  List<Object?> get props => [text];
}

class CreateNoteFromToolbar extends TextBookEvent {
  const CreateNoteFromToolbar();

  @override
  List<Object?> get props => [];
}

class UpdateSelectedTextForNote extends TextBookEvent {
  final String? text;
  final int? start;
  final int? end;

  const UpdateSelectedTextForNote(this.text, this.start, this.end);

  @override
  List<Object?> get props => [text, start, end];
}

// Editor Events
class OpenEditor extends TextBookEvent {
  final int index;

  const OpenEditor({required this.index});

  @override
  List<Object?> get props => [index];
}

class SaveEditedSection extends TextBookEvent {
  final int index;
  final String sectionId;
  final String markdown;

  const SaveEditedSection({
    required this.index,
    required this.sectionId,
    required this.markdown,
  });

  @override
  List<Object?> get props => [index, sectionId, markdown];
}

class LoadDraftIfAny extends TextBookEvent {
  final int index;
  final String sectionId;

  const LoadDraftIfAny({required this.index, required this.sectionId});

  @override
  List<Object?> get props => [index, sectionId];
}

class DiscardDraft extends TextBookEvent {
  final int index;
  final String sectionId;

  const DiscardDraft({required this.index, required this.sectionId});

  @override
  List<Object?> get props => [index, sectionId];
}

class CloseEditor extends TextBookEvent {
  const CloseEditor();

  @override
  List<Object?> get props => [];
}

class UpdateEditorText extends TextBookEvent {
  final String text;

  const UpdateEditorText(this.text);

  @override
  List<Object?> get props => [text];
}

class AutoSaveDraft extends TextBookEvent {
  final int index;
  final String sectionId;
  final String markdown;

  const AutoSaveDraft({
    required this.index,
    required this.sectionId,
    required this.markdown,
  });

  @override
  List<Object?> get props => [index, sectionId, markdown];
}

class OpenFullFileEditor extends TextBookEvent {
  const OpenFullFileEditor();

  @override
  List<Object?> get props => [];
}
