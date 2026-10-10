// משותף ל-otzaria.iss ול-otzaria_full.iss (ראה docs/bundled_plugins.md).
// תוסף שאין בו תועלת בלי רשת מועתק רק אם https://otzaria.org/ עונה 200.

var
  OtzariaSiteChecked: Boolean;
  OtzariaSiteReachableResult: Boolean;

function OtzariaSiteReachable(): Boolean;
var
  Request: Variant;
begin
  if not OtzariaSiteChecked then
  begin
    OtzariaSiteChecked := True;
    OtzariaSiteReachableResult := False;
    try
      // WinHttp ולא DownloadTemporaryFile: רק כאן אפשר לקבוע timeout.
      Request := CreateOleObject('WinHttp.WinHttpRequest.5.1');
      Request.SetTimeouts(5000, 5000, 5000, 5000);
      Request.Open('GET', 'https://otzaria.org/', False);
      Request.Send('');
      OtzariaSiteReachableResult := Request.Status = 200;
    except
      Log('otzaria.org check failed: ' + GetExceptionMessage);
    end;
    Log('otzaria.org reachable: ' + IntToStr(Ord(OtzariaSiteReachableResult)));
  end;
  Result := OtzariaSiteReachableResult;
end;
