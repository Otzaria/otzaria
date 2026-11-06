program FullInstallerSemanticModelProbe;
{$mode objfpc}{$H+}
uses Classes, SysUtils;

type
  TFindRec = record
    Search: TSearchRec;
    Name: String;
    Attributes: LongInt;
  end;
  TStatusLabel = class
    Caption: String;
    procedure Update;
  end;
  TWizard = class
    StatusLabel: TStatusLabel;
  end;

const
  FILE_ATTRIBUTE_DIRECTORY = 16;
  PartsVariant = {PARTS_VARIANT};
  {MODEL_FOLDER_CONSTANT}
var
  Root, Scenario, SelectedBooksPath, Failure: String;
  PreparedLibraryArchive, PreparedIndexArchive: String;
  WizardForm: TWizard;
  LibrarySwapStarted: Boolean;

function NativePath(const Value: String): String;
begin Result := StringReplace(Value, '\', PathDelim, [rfReplaceAll]); end;
function DirExists(const Path: String): Boolean;
begin Result := DirectoryExists(NativePath(Path)); end;
function FileExists(const Path: String): Boolean;
begin Result := SysUtils.FileExists(NativePath(Path)); end;
function ExtractFileDir(const Path: String): String;
begin Result := SysUtils.ExtractFileDir(NativePath(Path)); end;
function IsStagingPath(const Path: String): Boolean;
begin
  Result := (Pos('.otzaria-books-staging', Path) > 0) or
    (Pos('.otzaria-library-install', Path) > 0);
end;
function ForceDirectories(const Path: String): Boolean;
begin
  if (Scenario = 'mkdir-fails') and
     IsStagingPath(Path) and
     (Pos(SemanticModelFolderName, Path) > 0) then exit(False);
  Result := SysUtils.ForceDirectories(NativePath(Path));
end;
function FindFirst(const Pattern: String; var Rec: TFindRec): Boolean;
begin
  Result := SysUtils.FindFirst(NativePath(Pattern), faAnyFile, Rec.Search) = 0;
  if Result then begin Rec.Name := Rec.Search.Name; Rec.Attributes := Rec.Search.Attr; end;
end;
function FindNext(var Rec: TFindRec): Boolean;
begin
  Result := SysUtils.FindNext(Rec.Search) = 0;
  if Result then begin Rec.Name := Rec.Search.Name; Rec.Attributes := Rec.Search.Attr; end;
end;
procedure FindClose(var Rec: TFindRec);
begin SysUtils.FindClose(Rec.Search); end;
function CopyFile(const Source, Dest: String; FailIfExists: Boolean): Boolean;
var Input, Output: TFileStream;
begin
  Result := False;
  if (Scenario = 'copy-fails') and (Pos('tokenizer.json', Source) > 0) then exit;
  if FailIfExists and FileExists(Dest) then exit;
  try
    Input := TFileStream.Create(NativePath(Source), fmOpenRead);
    try
      Output := TFileStream.Create(NativePath(Dest), fmCreate);
      try Output.CopyFrom(Input, 0); finally Output.Free; end;
    finally Input.Free; end;
    Result := True;
  except
    Result := False;
  end;
end;
function RenameFile(const Source, Dest: String): Boolean;
begin
  if (Scenario = 'swap-fails') and IsStagingPath(Source) then exit(False);
  if (Scenario = 'index-swap-fails') and (Pos('.otzaria-index-install', Source) > 0) then exit(False);
  Result := SysUtils.RenameFile(NativePath(Source), NativePath(Dest));
end;
procedure DelTree(const Path: String; A, B, C: Boolean);
var Rec: TSearchRec; Child: String;
begin
  if not DirectoryExists(NativePath(Path)) then exit;
  if SysUtils.FindFirst(NativePath(Path) + PathDelim + '*', faAnyFile, Rec) = 0 then
  begin
    repeat
      if (Rec.Name = '.') or (Rec.Name = '..') then continue;
      Child := NativePath(Path) + PathDelim + Rec.Name;
      if (Rec.Attr and faDirectory) <> 0 then DelTree(Child, A, B, C)
      else SysUtils.DeleteFile(Child);
    until SysUtils.FindNext(Rec) <> 0;
    SysUtils.FindClose(Rec);
  end;
  RemoveDir(NativePath(Path));
end;
function SaveStringToFile(const Path, Value: String; Append: Boolean): Boolean;
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(NativePath(Path), fmCreate);
  try
    if Value <> '' then Stream.WriteBuffer(Value[1], Length(Value));
    Result := True;
  finally Stream.Free; end;
end;
function ReadFile(const Path: String): String;
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(NativePath(Path), fmOpenRead);
  try
    SetLength(Result, Stream.Size);
    if Result <> '' then Stream.ReadBuffer(Result[1], Length(Result));
  finally Stream.Free; end;
end;
procedure TStatusLabel.Update;
begin end;
function CustomMessage(const Key: String): String;
begin Result := Key; end;
function GetSHA256OfFile(const Path: String): String;
begin Result := 'fixture-digest'; end;
function GetExceptionMessage: String;
begin Result := Exception(ExceptObject).Message; end;
procedure Log(const Value: String);
begin end;
procedure InstReportFailure(const Text, Detail: String; Retry: Boolean);
begin Failure := Text; end;
procedure ExtractBundledDatabase(const Archive, Database, Target: String);
begin SaveStringToFile(Target + '/' + Database, 'new-library', False); end;
procedure ExtractBundledTarArchive(const Archive, Folder, Target: String);
begin ForceDirectories(Target + '/' + Folder); end;

procedure LibraryInstallFailed(const Text, Detail: String);
begin Failure := Text; end;
procedure ExtractTemporaryFile(const Name: String);
begin end;
function GetLibraryIndexPath(const BooksPath: String): String;
begin Result := ExtractFileDir(BooksPath) + '/index'; end;
function UnpackArchive(const Archive, Dest: String; var ErrOutput: String): Boolean;
begin
  if Archive = PreparedLibraryArchive then
  begin
    ForceDirectories(Dest + '/books');
    SaveStringToFile(Dest + '/books/seforim.db', 'new-library', False);
  end
  else
  begin
    ForceDirectories(Dest + '/index');
    SaveStringToFile(Dest + '/index/.otzaria_prebuilt_index', 'new-index', False);
  end;
  Result := True;
end;

{EXTRACTED_ROUTINES}

procedure Check(Condition: Boolean; const Message: String);
begin if not Condition then raise Exception.Create(Message); end;

var Model: String; Failed: Boolean;
begin
  Scenario := ParamStr(1);
  Root := ParamStr(2) + '/' + Scenario;
  SelectedBooksPath := Root + '/books';
  ForceDirectories(SelectedBooksPath);
  SaveStringToFile(SelectedBooksPath + '/seforim.db', 'old-library', False);
  ForceDirectories(Root + '/index');
  SaveStringToFile(Root + '/index/.otzaria_prebuilt_index', 'old-index', False);
  PreparedLibraryArchive := 'library.tar.zst';
  if Scenario <> 'no-index' then PreparedIndexArchive := 'index.tar.zst';
  Model := SelectedBooksPath + '/' + SemanticModelFolderName;
  if Scenario = 'empty-model' then ForceDirectories(Model);
  if (Scenario <> 'no-model') and (Scenario <> 'empty-model') then
  begin
    ForceDirectories(Model + '/cache');
    ForceDirectories(Model + '/empty');
    SaveStringToFile(Model + '/query.int8.onnx', 'query-graph', False);
    SaveStringToFile(Model + '/tokenizer.json', 'tokenizer', False);
    SaveStringToFile(Model + '/document.fp32.onnx', 'passage-graph', False);
    SaveStringToFile(Model + '/model.json', 'identity', False);
    SaveStringToFile(Model + '/.otzaria-semantic', '', False);
    SaveStringToFile(Model + '/LICENSE', 'license', False);
    SaveStringToFile(Model + '/cache/entry', 'nested-data', False);
  end;
  WizardForm := TWizard.Create;
  WizardForm.StatusLabel := TStatusLabel.Create;
  Failed := False;
  try
    try {INSTALL_ROUTINE} except on E: EAbort do Failed := True; end;
    if PartsVariant then Failed := Failure <> '';
    if (Scenario = 'copy-fails') or (Scenario = 'mkdir-fails') or (Scenario = 'swap-fails') or (Scenario = 'index-swap-fails') then
    begin
      Check(Failed and (Failure <> ''), 'failed preservation or swap must report failure');
      Check(ReadFile(SelectedBooksPath + '/seforim.db') = 'old-library', 'failed installation changed original database');
      Check(ReadFile(Root + '/index/.otzaria_prebuilt_index') = 'old-index', 'failed installation changed original index');
      Check(not DirExists(Root + '/.otzaria-books-staging'), 'failed installation retained staged books');
      Check(not DirExists(Root + '/.otzaria-library-install'), 'failed installation retained staged library');
    end
    else
    begin
      Check(not Failed, 'successful installation aborted');
      Check(ReadFile(SelectedBooksPath + '/seforim.db') = 'new-library', 'new database missing');
      Check(not DirExists(Root + '/.otzaria-books-backup'), 'successful swap retained old library');
      if PartsVariant and (Scenario <> 'no-index') then
        Check(ReadFile(Root + '/index/.otzaria_prebuilt_index') = 'new-index', 'new index missing')
      else
        Check(ReadFile(Root + '/index/.otzaria_prebuilt_index') = 'old-index', 'unrequested index changed');
    end;
    if Scenario = 'no-model' then Check(not DirExists(Model), 'fresh install manufactured a model')
    else if Scenario = 'empty-model' then Check(DirExists(Model), 'empty model directory lost')
    else
    begin
      Check(ReadFile(Model + '/query.int8.onnx') = 'query-graph', 'query graph lost');
      Check(ReadFile(Model + '/tokenizer.json') = 'tokenizer', 'tokenizer lost');
      Check(ReadFile(Model + '/document.fp32.onnx') = 'passage-graph', 'passage graph lost');
      Check(ReadFile(Model + '/model.json') = 'identity', 'model identity lost');
      Check(ReadFile(Model + '/LICENSE') = 'license', 'license lost');
      Check(FileExists(Model + '/.otzaria-semantic'), 'ownership marker lost');
      Check(ReadFile(Model + '/cache/entry') = 'nested-data', 'nested model data lost');
      Check(DirExists(Model + '/empty'), 'empty nested model directory lost');
    end;
  finally
    WizardForm.StatusLabel.Free;
    WizardForm.Free;
  end;
  WriteLn('OK ', Scenario);
end.
