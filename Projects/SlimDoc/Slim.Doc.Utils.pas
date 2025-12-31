// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Utils;

interface

uses
  System.SysUtils;

function CamelCaseToSpaced(const S: String): String;

implementation

function CamelCaseToSpaced(const S: String): String;
begin
  Result := '';
  if S.IsEmpty then
    Exit;

  for var Loop: Integer := 1 to S.Length do
  begin
    if (Loop > 1) and CharInSet(S[Loop], ['A'..'Z']) then
      Result := Result + ' ';
    Result := Result + S[Loop];
  end;
end;

end.
