#ifndef OtzariaUiProduct
procedure InstTellSuppressible(const Title, Text: String);
begin
  SuppressibleMsgBox(Text, mbError, MB_OK, IDOK);
end;
#endif
