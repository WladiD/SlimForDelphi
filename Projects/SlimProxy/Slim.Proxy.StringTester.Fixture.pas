// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy.StringTester.Fixture;

interface

uses

  System.Classes,
  System.RegularExpressions,
  System.SysUtils,

  Slim.Fixture,
  Slim.Proxy.Base;

type

  [SlimFixture('StringTester', 'SlimProxy')]
  TSlimProxyStringTesterFixture = class(TSlimProxyBaseFixture)
  private
    FText: string;
  public
    constructor Create(const AText: String);
    function Contains(const AValue: string): Boolean;
    function ContainsCount(const AValue: string): Integer;
    function MatchCount(const APattern: string): Integer;
    function Matches(const APattern: string): Boolean;
    property Text: String read FText write FText;
  end;

implementation

{ TSlimProxyStringTesterFixture }

constructor TSlimProxyStringTesterFixture.Create(const AText: String);
begin
  FText:=AText;
end;

function TSlimProxyStringTesterFixture.Contains(const AValue: string): Boolean;
begin
  Result := Pos(AValue, FText) > 0;
end;

function TSlimProxyStringTesterFixture.ContainsCount(const AValue: string): Integer;
var
  LPos: Integer;
begin
  Result := 0;
  if AValue = '' then Exit;
  LPos := Pos(AValue, FText);
  while LPos > 0 do
  begin
    Inc(Result);
    LPos := Pos(AValue, FText, LPos + Length(AValue));
  end;
end;

function TSlimProxyStringTesterFixture.Matches(const APattern: string): Boolean;
begin
  Result := TRegEx.IsMatch(FText, APattern, [roIgnoreCase, roMultiLine]);
end;

function TSlimProxyStringTesterFixture.MatchCount(const APattern: string): Integer;
begin
  Result := TRegEx.Matches(FText, APattern, [roIgnoreCase, roMultiLine]).Count;
end;

initialization
  RegisterSlimFixture(TSlimProxyStringTesterFixture);

end.
