unit Data;

interface

uses

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

end.
