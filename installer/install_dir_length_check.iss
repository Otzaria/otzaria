// מגבלת תאימות ל-MAX_PATH: אורך תיקיית היעד תלוי בנתיב הקובץ הארוך ביותר בחבילה.

#define AppBuildDir AddBackslash(SourcePath) + "..\build\windows\" + AppArch + "\runner\Release"

#define LongestRelPathFrom(int H, str Dir, str Rel) \
  Local[0] = FindGetFileName(H), \
  Local[1] = (Local[0] == "." || Local[0] == "..") ? 0 : \
    DirExists(Dir + "\" + Local[0]) ? LongestRelPath(Dir + "\" + Local[0], Rel + Local[0] + "\") : \
    Len(Rel + Local[0]), \
  Local[2] = FindNext(H) ? LongestRelPathFrom(H, Dir, Rel) : 0, \
  Local[1] > Local[2] ? Local[1] : Local[2]

#define LongestRelPath(str Dir, str Rel) \
  Local[0] = FindFirst(Dir + "\*", faAnyFile), \
  Local[1] = Local[0] ? LongestRelPathFrom(Local[0], Dir, Rel) : 0, \
  Local[0] ? FindClose(Local[0]) : 0, \
  Local[1]

#define MaxInstallDirLength 258 - LongestRelPath(AppBuildDir, "")

[CustomMessages]
hebrew.InstallDirTooLongTitle=נתיב ההתקנה ארוך מדי
hebrew.InstallDirTooLongText=הנתיב של תיקיית ההתקנה ארוך מדי (%1 תווים), ו-Windows לא יוכל לשמור בה את כל קובצי התוכנה.%n%nבחרו תיקייה שהנתיב שלה עד %2 תווים.
#ifdef OtzariaUiProduct
english.InstallDirTooLongTitle=Installation path is too long
english.InstallDirTooLongText=The installation folder path is too long (%1 characters), so Windows cannot save all application files there.%n%nChoose a folder whose path is no longer than %2 characters.
#endif

[Code]
procedure InstTellSuppressible(const Title, Text: String); forward;

function InstallDirTooLong(): Boolean;
begin
  Result := Length(WizardDirValue) > {#MaxInstallDirLength};
  if Result then
    InstTellSuppressible(CustomMessage('InstallDirTooLongTitle'),
      FmtMessage(CustomMessage('InstallDirTooLongText'),
        [IntToStr(Length(WizardDirValue)), IntToStr({#MaxInstallDirLength})]));
end;
