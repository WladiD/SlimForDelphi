unit Slim.CmdUtils;

interface

/// <summary>
/// Checks command line parameters for --SlimPort=x (case insensitive).
/// Returns True if found and valid, populating APort.
/// </summary>
function HasSlimPortParam(out APort: Integer): Boolean;

implementation

uses
  System.SysUtils;

function HasSlimPortParam(out APort: Integer): Boolean;
var
  I: Integer;
  LParam: String;
begin
  Result := False;
  for I := 1 to ParamCount do
  begin
    LParam := ParamStr(I);
    if LParam.StartsWith('--SlimPort=', True) then
    begin
      if TryStrToInt(LParam.Substring(Length('--SlimPort=')), APort) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
end;

end.
