{ שכבת התצוגה של המסייע: המתאם בין הליבה המשותפת (otzaria_ui_core.iss) לעמודים של
  download_assistant.iss, שהם מודל הנתונים. אין כאן אף כלל בחירה. }
#if Pos(",preset_full_indexed,", "," + AA_ICON_NAMES + ",") == 0
  #error "עיצוב המסייע ישן: נדרשת גרסה 1.4.0 ומעלה (Assistant art too old: 1.4.0 or newer required)"
#endif

[CustomMessages]
; הטקסטים שרק המסייע מציג. המשותפים ב-otzaria_ui_core.iss, ושל הלוגיקה ב-download_assistant.iss.
english.CardSize=Download size: %1
english.RowVersion=Version
english.RowWhat=What to download
english.RowFor=For
english.RowSavedIn=Saved in
english.RowFile=File
english.RowFolder=In folder
english.ConnectingProgress=Connecting to the Otzaria website…
english.StartButton=Let's Get Started
english.InstallNow=Install Now on This Computer
english.OpenFolder=Open the Installation Folder
english.TechDetails=Technical details
english.Resume=Continue
english.Retry=Try Again
english.OpenDownloads=Open the Downloads Page
english.ConnectStopTitle=Stop connecting?
english.ConnectStopText=You can start again whenever you like.
english.ConnectStopYes=Stop
english.ConnectStopNo=Keep Connecting
english.StopTitle=Stop the download?
english.StopText=Files that were already downloaded will be kept, and running the assistant again continues from the same point.
english.StopYes=Stop
english.StopNo=Keep Downloading
english.InstallFailedTitle=Couldn't start the installer
english.InstallFailedText=You can run it yourself from the folder:%n%1

hebrew.CardSize=גודל ההורדה: %1
hebrew.RowVersion=גרסה
hebrew.RowWhat=מה יורד
hebrew.RowFor=עבור
hebrew.RowSavedIn=נשמר בתיקייה
hebrew.RowFile=הקובץ
hebrew.RowFolder=בתיקייה
hebrew.ConnectingProgress=מתחבר לאתר אוצריא…
hebrew.StartButton=בואו נתחיל
hebrew.InstallNow=התקן עכשיו במחשב הזה
hebrew.OpenFolder=פתח את תיקיית ההתקנה
hebrew.TechDetails=פרטים טכניים
hebrew.Resume=המשך
hebrew.Retry=נסה שוב
hebrew.OpenDownloads=פתח את עמוד ההורדות
hebrew.ConnectStopTitle=להפסיק את ההתחברות?
hebrew.ConnectStopText=אפשר להתחיל שוב מתי שתרצה.
hebrew.ConnectStopYes=הפסק
hebrew.ConnectStopNo=המשך להתחבר
hebrew.StopTitle=לעצור את ההורדה?
hebrew.StopText=קבצים שכבר ירדו יישמרו, והפעלה חוזרת תמשיך מאותו מקום.
hebrew.StopYes=עצור
hebrew.StopNo=המשך להוריד
hebrew.InstallFailedTitle=לא ניתן היה להפעיל את המתקין
hebrew.InstallFailedText=אפשר להפעיל אותו ידנית מתוך התיקייה:%n%1

[Code]
const
  UiBtnRetry = UiBtnFirstAdapter;
  UiBtnOpenPage = UiBtnFirstAdapter + 1;
  UiBtnQuit = UiBtnFirstAdapter + 2;
  UiBtnInstall = UiBtnFirstAdapter + 3;
  UiBtnOpenFolder = UiBtnFirstAdapter + 4;
  UiBtnDone = UiBtnFirstAdapter + 5;

  UiSrcDownload = UiSrcFirstAdapter;
  UiSrcWork = UiSrcFirstAdapter + 1;
  UiSrcConnect = UiSrcFirstAdapter + 2;

var
  UiCardsPage: TInputOptionWizardPage;
  UiReveal: TUiCard;
  UiBadge: TBitmapImage;
  UiFinishTitle: TNewStaticText;
  UiErrPanel: TPanel;
  UiErrBadge: TBitmapImage;
  UiErrTitle, UiErrBody, UiErrLink: TNewStaticText;
  UiErrTech: TRichEditViewer;

{ ============================ כרטיסים ============================ }

function UiOptionIcon(PageID, Index: Integer): String;
var
  Value: String;
begin
  Result := 'component';
  if PageID = ModePage.ID then
  begin
    if Index = ModeThisComputer then
      Result := 'this_pc'
    else
      Result := 'other_pc';
  end
  else if (PageID = OtherPage.ID) and (Index < GetArrayLength(OtherPlatform)) then
  begin
    Result := OtherPlatform[Index];
    Value := OtherFormat[Index];
    if (Value = 'deb') or (Value = 'rpm') or (Value = PortableFormat) then
      Result := 'fmt_' + Value;
  end
  else if PageID = PresetPage.ID then
  begin
    if Index = CustomPresetIndex then
      Result := 'preset_custom'
    else if (Index < GetArrayLength(PresetId)) and (DisplayRank(PresetId[Index]) > 0) then
    begin
      Value := PresetId[Index];
      StringChangeEx(Value, '-', '_', True);
      Result := 'preset_' + Value;
    end;
  end;
end;

function UiAdapterCardSelected(I: Integer): Boolean;
begin
  if UiCardsPage.ID = CustomPage.ID then
    Result := UiCardsPage.Values[I]
  else
    Result := UiCardsPage.SelectedValueIndex = I;
end;

procedure UiAdapterCardClick(I: Integer);
begin
  if not Assigned(UiCardsPage) then
    exit;
  if not UiCardsPage.CheckListBox.ItemEnabled[I] then
    exit;
  if UiCardsPage.ID = CustomPage.ID then
  begin
    if UiCards[I].Check then
      UiCardsPage.Values[I] := not UiCardsPage.Values[I]
    else
      UiCardsPage.Values[I] := True;
    UiCardsPage.CheckListBox.ItemIndex := I;
    CustomChoiceClicked(UiCardsPage.CheckListBox);
  end
  else
    UiCardsPage.SelectedValueIndex := I;
end;

function UiAdapterCardFocused(I: Integer): Boolean;
begin
  Result := Assigned(UiCardsPage) and UiCardsPage.CheckListBox.Focused and
    (UiCardsPage.CheckListBox.ItemIndex = I);
end;

procedure UiBuildCards(Page: TInputOptionWizardPage; PageID: Integer);
var
  I, N, Y, C: Integer;
  Card: TUiCard;
  Exclusive, Radio: Boolean;
begin
  UiCardsPage := Page;
  Exclusive := PageID <> CustomPage.ID;
  Radio := CustomInstallersAreRadio(InstallerTakesLibrary());
  N := Page.CheckListBox.Items.Count;
  if Page.CheckListBox.ItemIndex < 0 then
    for I := 0 to N - 1 do
      if Page.CheckListBox.ItemEnabled[I] then
      begin
        Page.CheckListBox.ItemIndex := I;
        break;
      end;
  Y := 0;
  for I := 0 to N - 1 do
  begin
    Card.Check := not Exclusive;
    Card.Icon := UiOptionIcon(PageID, I);
    Card.Side := '';
    Card.Desc := Page.CheckListBox.ItemSubItem[I];
    if PageID = CustomPage.ID then
    begin
      C := CustomIndex[I];
      Card.Title := CompName[C];
      Card.Desc := CompDesc[C];
      Card.Check := not (IsInstallerType(CompType[C]) and Radio);
      if not Page.CheckListBox.ItemEnabled[I] or
         (CompRequired[C] and not IsInstallerType(CompType[C])) then
        Card.Title := Card.Title + ' ' + CustomMessage('RequiredTag');
      Card.Side := HumanSize(CustomChoiceSize(C));
    end
    else if PageID = PresetPage.ID then
    begin
      if I <> CustomPresetIndex then
      begin
        Card.Title := PresetLabel[I];
        Card.Desc := PresetDesc[I];
        Card.Side := PresetSize[I];
      end
      else
      begin
        Card.Title := CustomMessage('PresetCustom');
        Card.Desc := CustomMessage('PresetCustomDesc');
      end;
    end
    else
      Card.Title := Page.CheckListBox.ItemCaption[I];
    if Card.Side <> '' then
      Card.Side := Msg1('CardSize', Card.Side);
    Y := UiAddCard(Card, Y);
    UiCards[I].Img.Enabled := Page.CheckListBox.ItemEnabled[I];
  end;
  UiEndCards(Y);
end;

{ ============================ עמוד התיקייה ============================ }

procedure UiBuildFolder();
begin
  UiSetContentHeight(UiBuildFolderField(FolderPage.Edits[0], FolderPage.Buttons[0], 0));
end;

{ ============================ עמוד הסיכום ============================ }

function UiSelectedSize(): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to GetArrayLength(CompId) - 1 do
    if CompSelected[I] then
      Result := Result + CompDownloadSize[I];
end;

function UiSummaryWhat(): String;
var
  Title: String;
  I: Integer;
begin
  I := PresetPage.SelectedValueIndex;
  if (I >= 0) and (I < CustomPresetIndex) then
    Title := PresetLabel[I]
  else
    Title := CustomMessage('PresetCustom');
  Result := Title + ' · ' + HumanSize(UiSelectedSize());
end;

function UiSummaryTarget(): String;
begin
  if IsThisComputerMode() then
    Result := ModePage.CheckListBox.ItemCaption[ModeThisComputer]
  else
    Result := TargetTitle(TargetPlatform, TargetArchitecture);
  if TargetFormat <> '' then
    Result := Result + ' · ' + FormatDisplayName(TargetFormat);
end;

procedure UiBuildReady();
var
  TargetIcon: String;
begin
  WizardForm.ReadyLabel.Visible := False;
  WizardForm.ReadyMemo.Visible := False;
  if IsThisComputerMode() then
    TargetIcon := 'this_pc'
  else
    TargetIcon := TargetPlatform;
  UiAddRow('preset_update', CustomMessage('RowVersion'), OtzariaVersionLabel(), False);
  UiAddRow(UiOptionIcon(PresetPage.ID, PresetPage.SelectedValueIndex),
    CustomMessage('RowWhat'), UiSummaryWhat(), False);
  UiAddRow(TargetIcon, CustomMessage('RowFor'), UiSummaryTarget(), False);
  UiAddRow('folder', CustomMessage('RowSavedIn'), FolderPage.Values[0], True);
  UiSetContentHeight(UiPlaceSummary(0));
end;

{ ============================ התקדמות ============================ }

{ ההתקדמות הכוללת: קבצים שהושלמו ועוד החלק של הקובץ הנוכחי לפי פס העמוד. }
function UiDownloadFraction(): Extended;
var
  I: Integer;
  Before, Current: Int64;
  Part, Done: Extended;
  Bar: TNewProgressBar;
begin
  Result := 0;
  if ProgressTotal <= 0 then
    exit;
  Before := 0;
  Current := 0;
  for I := 0 to GetArrayLength(QueueSize) - 1 do
  begin
    if Before = ProgressDone then
    begin
      Current := QueueSize[I];
      Break;
    end;
    Before := Before + QueueSize[I];
  end;
  Part := 0;
  Bar := DownloadPage.ProgressBar;
  if Bar.Visible and (Bar.Style = npbstNormal) and (Bar.Max > 0) then
  begin
    Part := Bar.Position;
    Part := Part / Bar.Max;
  end;
  Done := Current;
  Done := Done * Part + ProgressDone;
  Result := Done / ProgressTotal;
  if Result > 1 then
    Result := 1;
end;

{ בחיבור אין מה למדוד; ההורדה נמדדת על כל התור, וההכנה לפי הפס של העמוד. }
function UiAdapterProgress(Source: Integer; var Caption, Speed, Bytes: String;
  var Bar: TNewProgressBar; var Fraction: Extended; var Known: Boolean): Boolean;
var
  Page: TOutputProgressWizardPage;
  P: Integer;
begin
  Result := Source <> UiSrcConnect;
  if not Result then
  begin
    UiSetProgressCaption(CustomMessage('ConnectingProgress'));
    UiSetCaption(UiProgPercent, '');
    UiRenderBar(0, True);
    exit;
  end;
  if Source = UiSrcDownload then
    Page := DownloadPage
  else
    Page := WorkPage;
  Caption := Page.Msg1Label.Caption;
  Bytes := Page.Msg2Label.Caption;
  if Source <> UiSrcDownload then
  begin
    Bar := Page.ProgressBar;
    exit;
  end;
  Bytes := DownloadStatus;
  P := Pos(' · ', Bytes);
  if P > 0 then
  begin
    Speed := Copy(Bytes, P + 3, Length(Bytes));
    Bytes := Copy(Bytes, 1, P - 1);
  end;
  Fraction := UiDownloadFraction();
  Known := ProgressTotal > 0;
end;

{ ============================ שלבים ============================ }

function UiAdapterStepOf(PageID: Integer; var Total: Integer): Integer;
var
  Other: Boolean;
begin
  Other := not IsThisComputerMode();
  if Other then
    Total := 6
  else
    Total := 5;
  Result := 0;
  if PageID = ModePage.ID then
    Result := 1
  else if PageID = OtherPage.ID then
    Result := 2
  else if (PageID = PresetPage.ID) or (PageID = CustomPage.ID) then
  begin
    if Other then
      Result := 3
    else
      Result := 2;
  end
  else if PageID = FolderPage.ID then
    Result := Total - 2
  else if PageID = wpReady then
    Result := Total - 1
  else if (PageID = DownloadPage.ID) or (PageID = WorkPage.ID) or
          (PageID = wpInstalling) or (PageID = wpPreparing) then
    Result := Total;
end;

{ ============================ סיום ============================ }

function UiRevealClickTarget(): Boolean;
begin
  Result := (RevealPath <> '') and Assigned(RevealCheck);
end;

procedure UiRenderReveal();
var
  Bmp: TBitmap;
  Key: String;
  Mark: TBitmap;
  W, H, TextW: Integer;
begin
  if not Assigned(UiReveal.Img) or not UiRevealClickTarget() then
    exit;
  UiReveal.Sel := RevealCheck.Checked;
  UiReveal.Title := RevealCheck.Caption;
  Key := UiCardArt(UiReveal) + '|' + UiReveal.Title;
  if Key = UiReveal.Drawn then
    exit;
  UiReveal.Drawn := Key;
  W := Px(UiContentW);
  H := Px(52);
  Bmp := UiCanvas(W, H, UiPageColor);
  { שורת סימון ולא כרטיס בחירה: מסגרת רגילה גם כשהיא מסומנת. }
  if UiReveal.Hover then
    UiDrawVSlices(Bmp.Canvas, 'card_h', 0, 0, H, UiCardColor)
  else
    UiDrawVSlices(Bmp.Canvas, 'card_n', 0, 0, H, UiCardColor);
  if UiReveal.Sel then
    Mark := UiArt('check_on')
  else
    Mark := UiArt('check_off');
  UiDraw(Bmp.Canvas, UiX(W - Px(16) - Mark.Width, Mark.Width, W),
    (H - Px(UiCardShadow) - Mark.Height) div 2, Mark);
  TextW := W - Px(16 + UiToggle + 12 + 16);
  UiText(Bmp.Canvas, UiReveal.Title, UiX(Px(16), TextW, W), 0, TextW,
    H - Px(UiCardShadow), 16, False, UiTextColor, UiAlign() or DT_VCENTER or
    DT_SINGLELINE or DT_NOPREFIX or UiReading(UiReveal.Title));
  UiShowBitmap(UiReveal.Img, Bmp);
end;

procedure UiRevealClick(Sender: TObject);
begin
  if UiRevealClickTarget() then
    RevealCheck.Checked := not RevealCheck.Checked;
end;

{ משפט ממורכז, ורשימה עם השורה שמציגה אותה צמודות לצד שבו הקריאה מתחילה. שורה
  בלי עברית (פקודה, שם קובץ) נקראת משמאל לימין ונשברת גם באמצע מילה. }
function UiResultLineFlags(const Line: String; Center: Boolean): LongWord;
begin
  if Center then
    Result := DT_CENTER
  else
    Result := UiAlign();
  Result := Result or DT_WORDBREAK or DT_EDITCONTROL or DT_NOPREFIX;
  if UiHasHebrew(Line) then
    Result := Result or DT_RTLREADING;
end;

function UiLayoutResult(C: TCanvas; const Text: String; Draw: Boolean): Integer;
var
  Lines: TArrayOfString;
  I, N, W, H, Bullet, Y, Size: Integer;
  Line: String;
  Flags: LongWord;
  Value, Center: Boolean;
  Color: TColor;
begin
  W := Px(UiContentW);
  Size := 14;
  Bullet := UiTextW('•', Size, False) + Px(8);
  Lines := StringSplitEx(Text, [#13#10], #0, stAll);
  N := GetArrayLength(Lines);
  Y := 0;
  for I := 0 to N - 1 do
  begin
    Line := Lines[I];
    if Line = '' then
    begin
      Y := Y + Px(8);
      Continue;
    end;
    if Copy(Line, 1, 2) = '• ' then
    begin
      Line := Copy(Line, 3, Length(Line));
      Flags := UiResultLineFlags(Line, False);
      H := UiTextH(Line, Size, True, W - Bullet, Flags);
      if Draw then
      begin
        UiText(C, '•', UiX(W - Bullet, Bullet, W), Y, Bullet, H, Size, False, UiFaintColor,
          UiAlign() or DT_NOPREFIX);
        UiText(C, Line, UiX(0, W - Bullet, W), Y, W - Bullet, H, Size, True, UiTextColor,
          Flags);
      end;
    end
    else
    begin
      Center := True;
      if I + 1 < N then
        Center := Copy(Lines[I + 1], 1, 2) <> '• ';
      Flags := UiResultLineFlags(Line, Center);
      Value := ListIndex(ResultCommands, Line) >= 0;
      if Value then
        Color := UiTextColor
      else
        Color := UiSecondaryColor;
      if not Value and UiHasHebrew(Line) then
      begin
        { RLM סביב סוגריים עם טקסט לטיני, אחרת הסוגר והנקודה קופצים לצד הלא נכון. }
        StringChangeEx(Line, ' (', ' ' + #$200F + '(', True);
        StringChangeEx(Line, ').', ')' + #$200F + '.', True);
      end;
      H := UiTextH(Line, Size, Value, W, Flags);
      if Draw then
        UiText(C, Line, 0, Y, W, H, Size, Value, Color, Flags);
    end;
    Y := Y + H + Px(2);
  end;
  Result := Y;
end;

{ פעולות הסיום בערימה אחת מעל התחתית, כמו בעמודי השגיאה: במחשב הזה להתקין או
  לפתוח את התיקייה ו"סגור"; למחשב אחר "סיום". מחזיר את הגבול העליון שלהן. }
function UiPlaceFinishActions(Page: TNewNotebookPage): Integer;
var
  This, Install: Boolean;
begin
  if not Assigned(UiButtons[UiBtnDone].Img) then
  begin
    UiMakeButton(UiBtnInstall, Page, 'btn_primary', Px(UiMargin), 0);
    UiMakeButton(UiBtnOpenFolder, Page, 'btn_tonalwide', Px(UiMargin), 0);
    UiMakeButton(UiBtnDone, Page, 'btn_ghost', Px(UiMargin), 0);
    UiButtons[UiBtnInstall].Width := Px(UiContentW);
    UiButtons[UiBtnOpenFolder].Width := Px(UiContentW);
    UiButtons[UiBtnDone].Width := Px(UiContentW);
  end;
  This := IsThisComputerMode();
  Install := This and (RunAfterExe <> '');
  UiButtons[UiBtnDone].Img.Top := Px(UiStackTop(0, 1) - UiBarH);
  if This then
  begin
    UiButtons[UiBtnDone].Art := 'btn_ghost';
    UiButtons[UiBtnOpenFolder].Img.Top := Px(UiStackTop(0, 2) - UiBarH);
    UiButtons[UiBtnInstall].Img.Top := Px(UiStackTop(0, 3) - UiBarH);
  end
  else
    UiButtons[UiBtnDone].Art := 'btn_primary';
  UiButtons[UiBtnDone].Drawn := '';
  UiSetButton(UiBtnInstall, Install, True, CustomMessage('InstallNow'));
  UiSetButton(UiBtnOpenFolder, This, True, CustomMessage('OpenFolder'));
  if This then
    UiSetButton(UiBtnDone, True, True, CustomMessage('Close'))
  else
    UiSetButton(UiBtnDone, True, True, UiStrip(WizardForm.NextButton.Caption));
  UiFooter.Visible := False;
  if Install then
    Result := UiButtons[UiBtnInstall].Img.Top
  else if This then
    Result := UiButtons[UiBtnOpenFolder].Img.Top
  else
    Result := UiButtons[UiBtnDone].Img.Top;
end;

{ כרטיס עם הקובץ והתיקייה, כמו בסיכום שלפני ההורדה, ומתחתיו ההנחיה. }
procedure UiAdapterBuildFinish();
var
  Page: TNewNotebookPage;
  Bmp: TBitmap;
  ResultImg: TBitmapImage;
  H, Y, Bottom: Integer;
begin
  Page := WizardForm.FinishedPage;
  WizardForm.WizardBitmapImage2.Visible := False;
  WizardForm.FinishedHeadingLabel.Visible := False;
  WizardForm.FinishedLabel.Visible := False;
  WizardForm.RunList.Visible := False;
  WizardForm.YesRadio.Visible := False;
  WizardForm.NoRadio.Visible := False;
  if Assigned(RevealCheck) then
    RevealCheck.Left := -Px(4000);

  if not Assigned(UiBadge) then
  begin
    UiBadge := UiImage(Page);
    UiBadge.SetBounds(0, Px(UiBadgeTop - UiBarH), 1, 1);
    UiShowArt(UiBadge, 'badge_ok');
    UiBadge.Left := (Px(UiWidth) - UiBadge.Width) div 2;
    UiFinishTitle := UiLabel(Page, 20, True, UiTextColor, taCenter);
  end;
  Y := UiPlaceLabel(UiFinishTitle, WizardForm.FinishedHeadingLabel.Caption, Px(UiMargin),
    UiBadge.Top + UiBadge.Height + Px(16), Px(UiContentW));

  Bottom := UiPlaceFinishActions(Page) - Px(12);
  if not IsThisComputerMode() and UiRevealClickTarget() then
  begin
    if not Assigned(UiReveal.Img) then
    begin
      UiReveal.Img := UiImage(Page);
      UiReveal.Img.Cursor := crHand;
      UiReveal.Img.OnClick := @UiRevealClick;
      UiReveal.Check := True;
    end;
    UiReveal.Img.SetBounds(Px(UiMargin), Bottom - Px(52), Px(UiContentW), Px(52));
    UiReveal.Drawn := '';
    UiRenderReveal();
    UiReveal.Img.Visible := True;
    Bottom := Bottom - Px(52 + 12);
  end;

  UiPlaceHost(Page, Y + Px(16), Bottom);
  UiAddRow('preset_update', CustomMessage('RowVersion'), OtzariaVersionLabel(), False);
  UiAddRow('component', CustomMessage('RowFile'), ResultFile, True);
  UiAddRow('folder', CustomMessage('RowFolder'), ResultFolder, True);
  Y := UiPlaceSummary(0) + Px(16);
  H := UiLayoutResult(nil, ResultGuide, False);
  Bmp := UiCanvas(Px(UiContentW), H, UiPageColor);
  UiLayoutResult(Bmp.Canvas, ResultGuide, True);
  ResultImg := UiImage(UiContent);
  ResultImg.SetBounds(0, Y, 1, 1);
  UiShowBitmap(ResultImg, Bmp);
  UiSetContentHeight(Y + H);
end;

{ ============================ שגיאות ============================ }

procedure UiErrLinkClick(Sender: TObject);
begin
  UiErrTech.Visible := not UiErrTech.Visible;
end;

procedure UiBuildErrorPanel();
var
  W: Integer;
begin
  W := Px(UiContentW);
  UiErrPanel := UiPanel(WizardForm, UiPageColor);
  UiErrPanel.SetBounds(0, Px(UiBarH), Px(UiWidth), Px(UiHeight - UiBarH));
  UiErrPanel.Visible := False;
  UiErrBadge := UiImage(UiErrPanel);
  UiErrBadge.SetBounds(0, Px(UiBadgeTop - UiBarH), 1, 1);
  UiErrTitle := UiLabel(UiErrPanel, 20, True, UiTextColor, taCenter);
  UiErrBody := UiLabel(UiErrPanel, 14, False, UiSecondaryColor, taCenter);
  UiErrLink := UiLabel(UiErrPanel, 13, True, UiPrimaryColor, taCenter);
  UiErrLink.Cursor := crHand;
  UiErrLink.OnClick := @UiErrLinkClick;
  UiErrTech := TRichEditViewer.Create(WizardForm);
  UiErrTech.Parent := UiErrPanel;
  UiErrTech.ReadOnly := True;
  UiErrTech.BorderStyle := bsNone;
  UiErrTech.ScrollBars := ssVertical;
  UiErrTech.Color := UiCardColor;
  UiErrTech.UseRichEdit := True;
  UiErrTech.Visible := False;

  UiMakeButton(UiBtnRetry, UiErrPanel, 'btn_primary', Px(UiMargin), 0);
  UiMakeButton(UiBtnOpenPage, UiErrPanel, 'btn_tonalwide', Px(UiMargin),
    Px(UiStackTop(1, 3) - UiBarH));
  UiMakeButton(UiBtnQuit, UiErrPanel, 'btn_ghost', Px(UiMargin), Px(UiStackTop(2, 3) - UiBarH));
  UiButtons[UiBtnRetry].Img.OnClick := @UiButtonClick;
  UiButtons[UiBtnOpenPage].Img.OnClick := @UiButtonClick;
  UiButtons[UiBtnQuit].Img.OnClick := @UiButtonClick;
  UiButtons[UiBtnRetry].Width := W;
  UiButtons[UiBtnOpenPage].Width := W;
  UiButtons[UiBtnQuit].Width := W;
end;

{ עמוד השגיאה מכסה את העמוד שבו קרה הכישלון. "נסה שוב" מסתיר אותו ולוחץ שוב על
  "הבא" של אותו עמוד, ולכן ניסיון חוזר עובר בדיוק באותם כללים של האשף. }
procedure UiShowFailure(Stage: Integer; const Title, Body, Tech: String; Offline: Boolean);
var
  Y, W, X: Integer;
  Heading: String;
  Stopped: Boolean;
begin
  if not UiReady or UiFailed or UiCloseIfRequested() then
    exit;
  if not Assigned(UiErrPanel) then
    UiBuildErrorPanel();
  W := Px(UiContentW);
  X := Px(UiMargin);
  Stopped := Stage = RunStopped;
  UiButtons[UiBtnRetry].Img.Top := Px(UiStackTop(0, 3) - UiBarH);
  if Stopped then
  begin
    { בעצירה אין מה לפתוח בדפדפן, ו"המשך" יורד אל מעל "סגור". }
    UiButtons[UiBtnRetry].Img.Top := Px(UiStackTop(0, 2) - UiBarH);
    UiShowArt(UiErrBadge, 'badge_paused');
  end
  else if Offline and (UiArt('badge_offline').Width > 0) then
    UiShowArt(UiErrBadge, 'badge_offline')
  else
    UiShowArt(UiErrBadge, 'badge_err');
  UiErrBadge.Left := (Px(UiWidth) - UiErrBadge.Width) div 2;
  { הנוסח הקיים הוא משפט שלם; ככותרת הוא מוצג בלי הנקודה. }
  Heading := Title;
  if Copy(Heading, Length(Heading), 1) = '.' then
    Heading := Copy(Heading, 1, Length(Heading) - 1);
  Y := UiPlaceLabel(UiErrTitle, Heading, X, UiErrBadge.Top + UiErrBadge.Height + Px(16), W);
  Y := UiPlaceLabel(UiErrBody, Body, X, Y + Px(8), W);
  UiErrTech.Visible := False;
  if Tech <> '' then
  begin
    Y := UiPlaceLabel(UiErrLink, CustomMessage('TechDetails'), X, Y + Px(14), W);
    UiErrTech.RTFText := UiRtf(Tech);
    UiErrTech.SetBounds(X, Y + Px(10), W,
      UiButtons[UiBtnRetry].Img.Top - Px(16) - Y - Px(10));
  end
  else
    UiErrLink.Visible := False;
  if Stopped then
    UiSetButton(UiBtnRetry, True, True, CustomMessage('Resume'))
  else
    UiSetButton(UiBtnRetry, True, True, CustomMessage('Retry'));
  UiSetButton(UiBtnOpenPage, not Stopped, True, CustomMessage('OpenDownloads'));
  UiSetButton(UiBtnQuit, True, True, CustomMessage('Close'));
  UiErrPanel.Visible := True;
  UiErrPanel.BringToFront;
  UiFrameToFront();
end;

procedure UiHideFailure();
begin
  if not Assigned(UiErrPanel) or not UiErrPanel.Visible then
    exit;
  UiErrPanel.Visible := False;
  UiButtons[UiBtnRetry].Shown := False;
  UiButtons[UiBtnOpenPage].Shown := False;
  UiButtons[UiBtnQuit].Shown := False;
end;

{ ============================ בניית עמוד ============================ }

function UiOptionPage(PageID: Integer): TInputOptionWizardPage;
begin
  Result := nil;
  if PageID = ModePage.ID then
    Result := ModePage
  else if PageID = OtherPage.ID then
    Result := OtherPage
  else if PageID = PresetPage.ID then
    Result := PresetPage
  else if PageID = CustomPage.ID then
    Result := CustomPage;
end;

procedure UiAdapterLeavePage();
begin
  UiHideFailure();
  UiCardsPage := nil;
end;

function UiAdapterPageHint(PageID: Integer): String;
var
  Option: TInputOptionWizardPage;
begin
  Result := '';
  Option := UiOptionPage(PageID);
  if Assigned(Option) then
  begin
    Result := Option.SubCaptionLabel.Caption;
    Option.SubCaptionLabel.Visible := False;
    Option.CheckListBox.Left := -Px(4000);
  end
  else if PageID = FolderPage.ID then
  begin
    Result := FolderPage.SubCaptionLabel.Caption;
    FolderPage.SubCaptionLabel.Visible := False;
  end
  else if PageID = wpReady then
    Result := WizardForm.ReadyLabel.Caption;
end;

procedure UiAdapterBuildPage(PageID: Integer);
var
  Option: TInputOptionWizardPage;
begin
  Option := UiOptionPage(PageID);
  if Assigned(Option) then
    UiBuildCards(Option, PageID)
  else if PageID = FolderPage.ID then
    UiBuildFolder()
  else if PageID = wpReady then
    UiBuildReady()
  else if PageID = DownloadPage.ID then
  begin
    UiHideProgressNative(DownloadPage);
    DownloadPage.AbortButton.Left := -Px(4000);
    DownloadPage.AbortButton.TabStop := False;
    UiBuildProgress(UiSrcDownload);
  end
  else if PageID = ConnectPage.ID then
  begin
    UiHideProgressNative(ConnectPage);
    ConnectPage.AbortButton.Left := -Px(4000);
    ConnectPage.AbortButton.TabStop := False;
    UiBuildProgress(UiSrcConnect);
  end
  else if PageID = WorkPage.ID then
  begin
    UiHideProgressNative(WorkPage);
    UiBuildProgress(UiSrcWork);
  end
  else if PageID = wpInstalling then
    UiBuildInstalling();
end;

{ ============================ כפתורים ============================ }

{ Inno מקבל סגירה רק בעמוד שיש בו "ביטול". בעמודי ההתקדמות השאלה נשאלת כאן,
  והסגירה מחכה עד שהשלב חוזר לעמוד רגיל (UiCloseIfRequested). }
procedure UiRequestClose();
begin
  if UiPage = wpFinished then
    UiClickReal(WizardForm.NextButton)
  else if WizardForm.CancelButton.CanFocus then
    PostMessage(WizardForm.Handle, UiWmSysCommand, UiScClose, 0)
  else if UiAskExit() then
  begin
    UiClosing := True;
    StopRequested := True;
  end;
end;

procedure UiButtonClick(Sender: TObject);
var
  I: Integer;
begin
  { בזמן דו-שיח החלון מושבת; לחיצה שבכל זאת הגיעה הייתה פותחת שאלה שנייה. }
  if UiIsWindowEnabled(WizardForm.Handle) = 0 then
    exit;
  for I := 0 to GetArrayLength(UiButtons) - 1 do
    if (Sender = UiButtons[I].Img) and UiButtons[I].Shown and UiButtons[I].Enabled then
      case I of
        UiBtnAbort:
          if UiPage = ConnectPage.ID then
          begin
            if UiAsk(CustomMessage('ConnectStopTitle'), CustomMessage('ConnectStopText'),
              CustomMessage('ConnectStopYes'), CustomMessage('ConnectStopNo'), True) then
              StopRequested := True;
          end
          else if UiAsk(CustomMessage('StopTitle'), CustomMessage('StopText'),
            CustomMessage('StopYes'), CustomMessage('StopNo'), True) then
            StopRequested := True;
        UiBtnRetry:
          begin
            UiHideFailure();
            UiClickReal(WizardForm.NextButton);
          end;
        UiBtnOpenPage: OpenDownloadsPage();
        UiBtnInstall:
          if RunInstaller() then
            UiClickReal(WizardForm.NextButton)
          else
            UiTell(CustomMessage('InstallFailedTitle'),
              Msg1('InstallFailedText', ExtractFileDir(RunAfterExe)));
        UiBtnOpenFolder: OpenOutputFolder();
        UiBtnDone: UiClickReal(WizardForm.NextButton);
        UiBtnQuit:
          begin
            UiClosing := True;
            WizardForm.Close;
          end;
        UiBtnClose: UiRequestClose();
      else
        UiCoreButtonClick(I);
      end;
end;

{ ============================ עכבר וכותרת תחתונה ============================ }

procedure UiAdapterPollMouse(Wnd: Longint; const P: TUiPoint);
var
  Hover: Boolean;
begin
  if Assigned(UiReveal.Img) and UiReveal.Img.Visible and (UiPage = wpFinished) then
  begin
    Hover := UiHitImage(UiReveal.Img, Wnd, P);
    if Hover <> UiReveal.Hover then
      UiReveal.Hover := Hover;
    UiRenderReveal();
  end;
end;

{ ההורדה והחיבור — לכפתור העצירה; עמוד שגיאה — ל"נסה שוב"; הסיום — לפעולה הראשונה. }
function UiAdapterFocusTarget(Native: TWinControl; I: Integer): Integer;
var
  J: Integer;
begin
  Result := I;
  if Native = DownloadPage.AbortButton then
    Result := UiBtnAbort
  else if Native = ConnectPage.AbortButton then
    Result := UiBtnAbort;
  if Result < 0 then
    exit;
  if Assigned(UiErrPanel) and UiErrPanel.Visible then
    Result := UiBtnRetry
  else if UiPage = wpFinished then
  begin
    Result := -1;
    for J := UiBtnInstall to UiBtnDone do
      if Assigned(UiButtons[J].Img) and UiButtons[J].Img.CanFocus then
      begin
        WizardForm.ActiveControl := UiButtons[J].Img;
        exit;
      end;
  end;
end;

function UiAdapterEnterGoesNext(): Boolean;
begin
  Result := not Assigned(UiErrPanel) or not UiErrPanel.Visible;
end;

procedure UiAdapterSyncFooter();
begin
  if UiPage = ConnectPage.ID then
    UiSetButton(UiBtnAbort, ConnectPage.AbortButton.Visible,
      ConnectPage.AbortButton.Enabled and not StopRequested, CustomMessage('Cancel'))
  else
    UiSetButton(UiBtnAbort, (UiPage = DownloadPage.ID) and DownloadPage.AbortButton.Visible,
      DownloadPage.AbortButton.Enabled and not StopRequested,
      UiStrip(DownloadPage.AbortButton.Caption));
end;

{ ============================ חיבור לאשף ============================ }

procedure UiAssistantInitializeWizard();
begin
  UiInitializeWizard('title_', 'title_en_', CustomMessage('StartButton'));
  { MinimizePathName מקצר את שורת המצב לרוחב התווית, והתווית עצמה מוסתרת. }
  DownloadPage.Msg2Label.Width := Px(4000);
  WorkPage.Msg2Label.Width := Px(4000);
end;
