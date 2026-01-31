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
  // 1. Check for explicit --SlimPort= parameter (Highest Priority)
  for I := 1 to ParamCount do
  begin
    LParam := ParamStr(I);
    if LParam.StartsWith('--SlimPort=', True) and
       TryStrToInt(LParam.Substring(Length('--SlimPort=')), APort) then
      Exit(True);
  end;

  // 2. Check LAST parameter for plain integer (Standard FitNesse behavior)
  // Only if no explicit flag was found.
  Result := (ParamCount >= 1) and TryStrToInt(ParamStr(ParamCount), APort);
end;

end.
