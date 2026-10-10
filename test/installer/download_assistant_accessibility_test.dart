import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `#include "x"` מילולי: הליבה המשותפת והמתאם נקראים כמו ש-ISPP רואה אותם.
final _includeLine = RegExp(
  r'^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$',
  multiLine: true,
);

String _read(String name) =>
    File('installer/$name').readAsStringSync().replaceAll('\r\n', '\n');

String _expand(String text) =>
    text.replaceAllMapped(_includeLine, (m) => _expand(_read(m[1]!)));

/// גוף השגרה; הצהרת `forward` של חוזה המתאם אינה גוף.
String routine(String script, String signature) {
  var start = script.indexOf(signature);
  while (start >= 0 && _isForward(script, start)) {
    start = script.indexOf(signature, start + signature.length);
  }
  expect(start, isNonNegative, reason: signature);
  return script.substring(start, script.indexOf('\nend;', start));
}

bool _isForward(String script, int start) {
  final open = script.indexOf('(', start);
  var header = script.indexOf(';', start);
  if (open >= 0 && open < header) {
    header = script.indexOf(';', script.indexOf(')', open));
  }
  return header >= 0 && script.startsWith(RegExp(r'\s*forward;'), header + 1);
}

void main() {
  final script = _expand(_read('download_assistant.iss'));
  final native = _read('download_assistant.iss');

  test('כל פעולות המסייע הן כפתורי Windows עם שם ומוקד גלוי', () {
    expect(script, contains('Img: TBitmapButton;'));
    final make = routine(script, 'procedure UiMakeButton(');
    expect(make, contains('TBitmapButton.Create(UiOwner(Parent))'));
    expect(make, contains('.TabStop := True;'));
    expect(make, contains('.Stretch := False;'));
    final set = routine(script, 'procedure UiSetButton(');
    expect(set, contains('.Img.Caption := Caption;'));
    expect(set, contains('.Img.Enabled := Enabled;'));
    final chrome = routine(script, 'procedure UiBuildChrome()');
    expect(chrome, contains("CustomMessage('Close')"));
    expect(chrome, contains("CustomMessage('Minimize')"));
  });

  test('שוליי המוקד משאירים את bounds וגודל הטקסט המקוריים', () {
    final render = routine(script, 'procedure UiRenderButton(');
    expect(render, contains('UiCanvas(W - 4, H - 4, UiButtons[I].Back)'));
    expect(render, contains('UiDrawButtonArt(Bmp.Canvas, Png, W - 4, H - 4)'));
    expect(render, contains('Bmp.Width, Bmp.Height, 14, True, Color'));
    expect(render, contains('UiButtons[I].Img.Top, W, H)'));
    expect(
      render,
      contains('UiDrawStretch(Bmp.Canvas, 0, 0, W - 4, H - 4, Png)'),
    );
    expect(render, contains('if (W <= 4) or (H <= 4) then'));
  });

  test('Enter מפעיל את הכפתור הגלוי שבמוקד גם בסיום ובדו שיח', () {
    final keys = routine(script, 'procedure UiKeyDown(');
    expect(keys, contains('if Key <> 13 then'));
    expect(keys, contains('.Img.Focused'));
    expect(keys, contains('Key := 0;'));
    expect(keys, contains('UiDialogButtonClick('));
    expect(keys, contains('UiButtonClick('));
    expect(keys, contains('UiAdapterEnterGoesNext()'));
    expect(
      routine(script, 'function UiAdapterEnterGoesNext('),
      contains('UiErrPanel.Visible'),
    );
    final wizard = routine(script, 'procedure UiInitializeWizard(');
    expect(wizard, contains('WizardForm.KeyPreview := True;'));
    expect(wizard, contains('WizardForm.OnKeyDown := @UiKeyDown;'));
    final ask = routine(script, 'function UiAskDialog(');
    expect(ask, contains('UiDlg.OnKeyDown := @UiKeyDown;'));
    expect(ask, contains('UiDlg.ActiveControl := UiButtons[UiBtnDlgNo].Img'));
    expect(ask, contains('UiDlg.ActiveControl := UiButtons[UiBtnDlgOk].Img'));
    expect(ask, contains('UiDlgNo.Cancel := not NoCancel;'));
    // במסייע Esc הוא תמיד "לא": UiAsk אינו מבקש NoCancel.
    expect(
      routine(script, 'function UiAsk('),
      contains('UiAskDialog(Title, Text, Yes, No, Danger, False)'),
    );
    expect(ask, contains('UiDlgOk.Default := False;'));
    expect(ask, contains('UiDlgNo.Default := False;'));
    expect(
      routine(script, 'procedure UiHideNativeChrome()'),
      contains('WizardForm.NextButton.Default := False;'),
    );
    final focus = routine(script, 'procedure UiFocusAction()');
    expect(focus, contains('if Assigned(UiDlg)'));
    expect(focus, contains('I := UiBtnStart'));
    expect(focus, contains('UiAdapterFocusTarget(Native, I)'));
    final target = routine(script, 'function UiAdapterFocusTarget(');
    expect(target, contains('for J := UiBtnInstall to UiBtnDone'));
    expect(target, contains('Result := UiBtnAbort'));
    expect(target, contains('Result := UiBtnRetry'));
  });

  test('Tab אינו עובר לכפתורי proxy נסתרים', () {
    final chrome = routine(script, 'procedure UiHideNativeChrome()');
    for (final name in ['NextButton', 'BackButton', 'CancelButton']) {
      expect(chrome, contains('WizardForm.$name.TabStop := False;'));
    }
    final ask = routine(script, 'function UiAskDialog(');
    for (final name in ['UiDlgOk', 'UiDlgNo']) {
      expect(ask, contains('$name.TabStop := False;'));
    }
    expect(
      routine(script, 'function UiBuildFolderField('),
      contains('Browse.TabStop := False;'),
    );
    expect(
      routine(script, 'procedure UiBuildFolder()'),
      contains('FolderPage.Buttons[0]'),
    );
    final build = routine(script, 'procedure UiAdapterBuildPage(');
    expect(build, contains('DownloadPage.AbortButton.TabStop := False;'));
    expect(build, contains('ConnectPage.AbortButton.TabStop := False;'));
  });

  test('ה-hover של כפתור חלון בודק את HWND שלו ולא רק את ההורה', () {
    final hit = routine(script, 'function UiHitButton(');
    expect(hit, contains('Wnd = Img.Handle'));
    expect(
      routine(script, 'procedure UiPollMouse()'),
      contains('UiHitButton(UiButtons[I].Img, Wnd)'),
    );
  });

  test('קנה המידה מותאם לכל אזורי העבודה גם ברוחב וגם בגובה', () {
    final fit = routine(script, 'function UiMeasureMonitor(');
    expect(fit, contains('UiGetMonitorInfo(Monitor, Info)'));
    expect(fit, contains('Info.Work.Right - Info.Work.Left'));
    expect(fit, contains('Info.Work.Bottom - Info.Work.Top'));
    final scale = routine(script, 'function UiPickScale()');
    expect(
      scale,
      contains(
        'UiEnumDisplayMonitors(0, 0, CreateCallback(@UiMeasureMonitor), 0)',
      ),
    );
    expect(scale, contains('UiWidth * S div 100 <= UiFitWidth'));
    expect(scale, contains('UiHeight * S div 100 <= UiFitHeight'));
    expect(scale, contains('if UiGetWorkArea(48, 0, Area, 0) then'));
    expect(scale, contains('UiFitWidth := Area.Right - Area.Left;'));
    expect(scale, contains('UiFitHeight := Area.Bottom - Area.Top;'));
  });

  test('הכרטיסים משמרים בחירה נעולה, רדיו ותלויות של מודל dev', () {
    final click = routine(script, 'procedure UiAdapterCardClick(');
    expect(
      click,
      contains('if not UiCardsPage.CheckListBox.ItemEnabled[I] then'),
    );
    expect(click, contains('UiCardsPage.Values[I] := True;'));
    expect(click, contains('UiCardsPage.CheckListBox.ItemIndex := I;'));
    expect(click, contains('CustomChoiceClicked(UiCardsPage.CheckListBox);'));
    expect(
      routine(script, 'function UiAdapterCardSelected('),
      contains('if UiCardsPage.ID = CustomPage.ID then'),
    );
    final cards = routine(script, 'procedure UiBuildCards(');
    for (final field in [
      'PresetLabel[I]',
      'PresetDesc[I]',
      'PresetSize[I]',
      'CompDesc[C]',
    ]) {
      expect(cards, contains(field));
    }
    expect(
      cards,
      contains('Card.Check := not (IsInstallerType(CompType[C]) and Radio);'),
    );
    expect(
      cards,
      contains('UiCards[I].Img.Enabled := Page.CheckListBox.ItemEnabled[I];'),
    );
    expect(
      cards,
      contains('(CompRequired[C] and not IsInstallerType(CompType[C]))'),
    );
    expect(cards, isNot(contains('if CompRequired[C] then')));
    expect(
      native,
      contains('CustomPage.CheckListBox.OnClickCheck := @CustomChoiceClicked;'),
    );
    expect(
      routine(native, 'procedure AddPreset('),
      contains('PresetSize[I] := PresetSize[I - 1];'),
    );
  });

  test('ההתקדמות והסיום שומרים תיאור עברי, נתיבים וגלילה בעיצוב', () {
    expect(
      routine(native, 'function OnDownloadProgress('),
      contains('DownloadStatus := Status;'),
    );
    final progress = routine(script, 'function UiAdapterProgress(');
    expect(progress, contains('DownloadStatus'));
    final finish = routine(script, 'procedure UiAdapterBuildFinish()');
    expect(finish, contains('UiPlaceHost(Page, Y + Px(16), Bottom);'));
    expect(finish, contains("ResultFile, True"));
    expect(finish, contains("ResultFolder, True"));
    expect(finish, contains('ResultGuide'));
    expect(
      routine(native, 'function PrepareOutput()'),
      contains('JoinNote := JoinNote + JoinCommand(A) + #13#10;'),
    );
  });

  test('מוקד native של בחירה מצויר בכרטיס ועוקב אחר הגלילה', () {
    final poll = routine(script, 'procedure UiPollMouse()');
    expect(poll, contains('UiAdapterCardFocused(I)'));
    expect(poll, contains('if Focused and not Card.Focused then'));
    expect(poll, contains('UiRevealCard(Card);'));
    expect(poll, contains('Hover := UiCards[I].Img.Enabled and'));
    final focused = routine(script, 'function UiAdapterCardFocused(');
    expect(focused, contains('UiCardsPage.CheckListBox.Focused'));
    expect(focused, contains('(UiCardsPage.CheckListBox.ItemIndex = I)'));
    final cards = routine(script, 'procedure UiBuildCards(');
    expect(cards, contains('if Page.CheckListBox.ItemIndex < 0 then'));
    expect(cards, contains('if Page.CheckListBox.ItemEnabled[I] then'));
    expect(cards, contains('Page.CheckListBox.ItemIndex := I;'));
    final render = routine(script, 'procedure UiRenderCardTo(');
    expect(render, contains('IntToStr(Ord(Card.Focused))'));
    expect(render, contains('UiDrawFocusRect(Bmp.Canvas.Handle, R);'));
    expect(render, contains('Card.Height - Px(UiCardShadow + 6)'));
    final scroll = routine(script, 'procedure UiRevealCard(');
    expect(scroll, contains('Card.Top + Card.Height - UiHost.Height'));
    expect(scroll, contains('UiScrollTarget := UiScrollY;'));
  });

  // אותה שכבה, אותו מודל מקלדת: כל מה שתלוי בעמוד — במתאם של המתקינים.
  group('מתקיני אוצריא — אותה נגישות מקלדת כמו במסייע', () {
    for (final name in const ['otzaria.iss', 'otzaria_full.iss']) {
      final installer = _expand(_read(name));
      final full = name == 'otzaria_full.iss';

      test('$name: כפתורי Windows, Enter, Tab וקנה המידה של הליבה', () {
        expect(installer, contains('Img: TBitmapButton;'));
        expect(
          routine(installer, 'procedure UiKeyDown('),
          contains('.Img.Focused'),
        );
        final wizard = routine(installer, 'procedure UiInitializeWizard(');
        expect(wizard, contains('WizardForm.OnKeyDown := @UiKeyDown;'));
        final chrome = routine(installer, 'procedure UiHideNativeChrome()');
        for (final button in ['NextButton', 'BackButton', 'CancelButton']) {
          expect(chrome, contains('WizardForm.$button.TabStop := False;'));
        }
        expect(chrome, contains('WizardForm.NextButton.Default := False;'));
        expect(
          routine(installer, 'function UiBuildFolderField('),
          contains('Browse.TabStop := False;'),
        );
        expect(
          routine(installer, 'function UiPickScale()'),
          contains('UiHeight * S div 100 <= UiFitHeight'),
        );
        expect(
          routine(installer, 'procedure UiFocusAction()'),
          contains('UiAdapterFocusTarget(Native, I)'),
        );
      });

      test('$name: בסיום Enter מפעיל את הפעולה שבמוקד, לא את "סיום" הנסתר', () {
        final target = routine(installer, 'function UiAdapterFocusTarget(');
        expect(target, contains('UiPage <> wpFinished'));
        expect(target, contains('for J := UiBtnOpenApp to UiBtnDone do'));
        expect(
          routine(installer, 'function UiAdapterEnterGoesNext('),
          contains('Result := True;'),
        );
        expect(
          routine(installer, 'procedure UiAdapterBuildFinish('),
          contains('WizardForm.RunList.TabStop := False;'),
        );
      });

      test('$name: "איך להתקין" — רדיו אמיתי מאחורי כל כרטיס, בקבוצה משלו', () {
        final create = routine(
          installer,
          'procedure CreateInstallModeChoice()',
        );
        expect(create, isNot(contains('.Visible := False')));
        expect(create, contains('Group.SetBounds(-ScaleX(4000)'));
        final focused = routine(installer, 'function UiAdapterCardFocused(');
        for (final radio in const [
          'CurrentUserModeRadio',
          'AllUsersModeRadio',
          'PortableModeRadio',
        ]) {
          expect(create, contains('$radio.Parent := Group;'));
          expect(create, contains('$radio.OnClick := @UiModeRadioClick;'));
          expect(focused, contains('$radio.Focused'));
        }
        // חץ לרדיו בוחר בו (VCL): אותה בחירה, תיקייה ושיגור-מחדש כמו בלחיצה.
        final click = routine(installer, 'procedure UiModeRadioClick(');
        expect(click, contains('ApplyInstallModeChoice();'));
        expect(click, contains('UiSyncModePage();'));
        expect(click, contains('(UiPage <> wpSelectDir)'));
      });

      test('$name: משימות, הכנה ואתחול — המוקד האמיתי מסומן בכרטיס', () {
        final focused = routine(installer, 'function UiAdapterCardFocused(');
        for (final task in const [
          'desktopicon',
          'calendaricon',
          'resetsettings',
        ]) {
          expect(
            focused,
            contains(
              "List.Focused and (List.ItemIndex = UiTaskIndex('$task'))",
            ),
          );
        }
        for (final radio in const [
          'PreparingYesRadio',
          'PreparingNoRadio',
          'YesRadio',
          'NoRadio',
        ]) {
          expect(focused, contains('WizardForm.$radio.Focused'));
        }
        if (full) expect(focused, contains('WV2Check.Focused'));
        expect(
          routine(installer, 'procedure UiBuildTasksPage()'),
          contains('WizardForm.TasksList.TabStop := not PortableMode;'),
          reason: 'בנייד אין כרטיסי משימות: Space אינו מסמן משימה נסתרת',
        );
        expect(
          routine(installer, 'function UiAdapterPageHint('),
          contains('WizardForm.PreparingMemo.Enabled := False;'),
        );
        expect(
          routine(installer, 'procedure UiPollMouse()'),
          contains('UiAdapterCardFocused(I)'),
        );
      });
    }
  });
}
