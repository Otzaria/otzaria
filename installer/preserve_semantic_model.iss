const
  // חייב להתאים ל-SemanticPaths.modelDirectory באפליקציה.
  SemanticModelFolderName = 'meivin-qa491-onnx';

// מעתיק לפני ההחלפה: כשל כתיבה או rename חייב להשאיר גם את המודל הישן שלם.
function CopySemanticModelDirectory(const SourceDir, TargetDir: String): Boolean;
var
  FindRec: TFindRec;
  SourcePath, TargetPath: String;
begin
  Result := True;
  if not DirExists(SourceDir) then
    exit;
  Result := False;
  if not ForceDirectories(TargetDir) then
    exit;
  if not FindFirst(SourceDir + '\*', FindRec) then
    exit;
  try
    Result := True;
    repeat
      if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
      begin
        SourcePath := SourceDir + '\' + FindRec.Name;
        TargetPath := TargetDir + '\' + FindRec.Name;
        if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          Result := CopySemanticModelDirectory(SourcePath, TargetPath)
        else
          Result := CopyFile(SourcePath, TargetPath, True);
        if not Result then
          exit;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;
