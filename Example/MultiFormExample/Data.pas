// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Data;

interface

uses

  System.DateUtils,
  System.Generics.Collections,
  System.SysUtils;

type

  TEntry = class
  private
    class var FGlobalId: Integer;
  public
    class function GetNextId: Integer;
  private
    FEntryDate: TDateTime;
    FId       : Integer;
    FName     : String;
  public
    function WorkingYears: Double;
    property EntryDate: TDateTime read FEntryDate write FEntryDate;
    property Id: Integer read FId write FId;
    property Name: String read FName write FName;
  end;

  TEntries = TObjectList<TEntry>;

implementation

{ TEntry }

class function TEntry.GetNextId: Integer;
begin
  Inc(FGlobalId);
  Result := FGlobalId;
end;

function TEntry.WorkingYears: Double;
begin
  Result := YearSpan(FEntryDate, Date);
end;

end.
