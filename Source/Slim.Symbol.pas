// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Symbol;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  System.Rtti,
  System.SysUtils;

type

  TSlimSymbolDictionary = class(TDictionary<String, TValue>)
  private
    function EvalSymbolsMatch(const AMatch: TMatch): String;
  public
    function EvalSymbols(const AInput: String): String;
  end;

const

  SymbolRegExPattern = '\$(([A-Za-z\p{L}][\w\p{L}]*)|`([^`]+)`)';

implementation

{ TSlimSymbolDictionary }

function TSlimSymbolDictionary.EvalSymbols(const AInput: String): String;
begin
  Result := TRegEx.Replace(AInput, SymbolRegExPattern, EvalSymbolsMatch);
end;

function TSlimSymbolDictionary.EvalSymbolsMatch(const AMatch: TMatch): String;
var
  Found      : Boolean;
  SymbolName : String;
  SymbolValue: TValue;
begin
  Found := AMatch.Groups.Count>0;
  if Found then
  begin
    SymbolName := AMatch.Groups[1].Value;
    Found := TryGetValue(SymbolName,SymbolValue);
    if Found then
      Result := SymbolValue.ToString;
  end;
  if not Found then
    Result := AMatch.Value;
end;

end.
