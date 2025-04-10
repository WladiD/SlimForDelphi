﻿unit Slim.List;

interface

uses

  System.Character,
  System.Classes,
  System.Contnrs,
  System.SysUtils;

type

  TSlimEntryType = (setUndefined, setString, setList);

  TSlimList = class;

  TSlimEntry = class
  protected
    FEntryType: TSlimEntryType;
  public
    property EntryType: TSlimEntryType read FEntryType;
  end;

  TSlimStringEntry = class(TSlimEntry)
  private
    FValue: String;
  public
    constructor Create(const AValue: String);
    function ToString: String; override;
  end;

  TSlimListEntry = class(TSlimEntry)
  private
    FList: TSlimList;
  public
    constructor Create;
    destructor Destroy; override;
    property List: TSlimList read FList;
  end;

  TSlimList = class
  private
    FList: TObjectList;
  protected
    function GetCount: Integer;
    function GetEntry(AIndex: Integer): TSlimEntry;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(AEntry: TSlimEntry): Integer;
    property Count: Integer read GetCount;
    property Entries[AIndex: Integer]: TSlimEntry read GetEntry; default;
  end;

  TSlimListSerializer = class
  private
    FSlimList: TSlimList;
    FBuilder : TStringBuilder;
    procedure WriteColon;
    procedure WriteLength(ALength: Integer);
    procedure WriteList(AList: TSlimList);
    procedure WriteListEntry(AEntry: TSlimListEntry);
    procedure WriteString(const AValue: String);
    procedure WriteStringEntry(AEntry: TSlimStringEntry);
  public
    constructor Create(ASlimList: TSlimList);
    destructor Destroy; override;
    function Serialize: String;
  end;

  TSlimListUnserializer = class
  private
    FContent: String;
    FPos    : Integer;
    function LookChar: Char;
    function ReadChar: Char;
    procedure ReadColon;
    procedure ReadContent(const AContent: String; ATarget: TSlimList);
    procedure ReadExpectedChar(AExpectedChar: Char);
    function ReadLength: Integer;
    function ReadString(ALength: Integer): String;
    procedure ReadLengthAndEntry(ATarget: TSlimList);
    procedure ReadList(ATarget: TSlimList);
  public
    constructor Create(const AContent: String);
    function Unserialize: TSlimList;
  end;

implementation

{ TSlimStringEntry }

constructor TSlimStringEntry.Create(const AValue: String);
begin
  FValue := AValue;
  FEntryType := setString;
end;

function TSlimStringEntry.ToString: String;
begin
  Result := FValue;
end;

{ TSlimListEntry }

constructor TSlimListEntry.Create;
begin
  FList := TSlimList.Create;
  FEntryType := setList;
end;

destructor TSlimListEntry.Destroy;
begin
  FList.Free;
  inherited;
end;

{ TSlimList }

constructor TSlimList.Create;
begin
  FList := TObjectList.Create(true);
end;

destructor TSlimList.Destroy;
begin
  FList.Free;
  inherited;
end;

function TSlimList.Add(AEntry: TSlimEntry): Integer;
begin
  Result := FList.Add(AEntry);
end;

function TSlimList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TSlimList.GetEntry(AIndex: Integer): TSlimEntry;
begin
  Result := TSlimEntry(FList[AIndex]);
end;

{ TSlimListSerializer }

constructor TSlimListSerializer.Create(ASlimList: TSlimList);
begin
  FSlimList := ASlimList;
  FBuilder := TStringBuilder.Create;
end;

destructor TSlimListSerializer.Destroy;
begin
  FBuilder.Free;
  inherited;
end;

function TSlimListSerializer.Serialize: String;
begin
  WriteList(FSlimList);
  Result := FBuilder.ToString;
end;

procedure TSlimListSerializer.WriteColon;
begin
  FBuilder.Append(':');
end;

procedure TSlimListSerializer.WriteLength(ALength: Integer);
var
  LenStr: String;
begin
  LenStr := Format('%.6d', [ALength]);
  FBuilder.Append(LenStr);
  WriteColon;
end;

procedure TSlimListSerializer.WriteList(AList: TSlimList);
var
  PrevBuilder: TStringBuilder;
  Entry      : TSlimEntry;
  SubContent : String;
begin
  FBuilder.Append('[');
  WriteLength(AList.Count);
  for var Loop := 0 to AList.Count - 1 do
  begin
    Entry := AList[Loop];
    if Entry is TSlimListEntry then
    begin
      PrevBuilder := FBuilder;
      try
        FBuilder := TStringBuilder.Create;
        WriteListEntry(TSlimListEntry(Entry));
        SubContent := FBuilder.ToString;
      finally
        FBuilder.Free;
        FBuilder := PrevBuilder;
      end;
      WriteString(SubContent);
    end
    else if Entry is TSlimStringEntry then
      WriteStringEntry(TSlimStringEntry(Entry));
  end;
  FBuilder.Append(']');
end;

procedure TSlimListSerializer.WriteListEntry(AEntry: TSlimListEntry);
begin
  WriteList(AEntry.List);
end;

procedure TSlimListSerializer.WriteString(const AValue: String);
begin
  WriteLength(Length(AValue));
  FBuilder.Append(AValue);
  WriteColon;
end;

procedure TSlimListSerializer.WriteStringEntry(AEntry: TSlimStringEntry);
begin
  WriteString(AEntry.ToString);
end;

{ TSlimListUnserializer }

constructor TSlimListUnserializer.Create(const AContent: String);
begin
  FContent := AContent;
end;

function TSlimListUnserializer.LookChar: Char;
begin
  if FPos <= Length(FContent) then
    Result := FContent[FPos]
  else
    Result := #0;
end;

function TSlimListUnserializer.ReadChar: Char;
begin
  if FPos <= Length(FContent) then
  begin
    Result := FContent[FPos];
    Inc(FPos);
  end
  else
    raise Exception.Create('End reached');
end;

procedure TSlimListUnserializer.ReadColon;
begin
  ReadExpectedChar(':');
end;

procedure TSlimListUnserializer.ReadContent(const AContent: String; ATarget: TSlimList);
var
  CurChar    : Char;
  PrevContent: String;
  PrevPos    : Integer;
begin
  PrevContent := FContent;
  PrevPos := FPos;
  try
    FContent := AContent;
    FPos := 1;
    CurChar := LookChar;
    if CurChar = '[' then
      ReadList(ATarget)
    else if TCharacter.IsNumber(CurChar) then
      ReadLengthAndEntry(ATarget);
  finally
    FContent := PrevContent;
    FPos := PrevPos;
  end;
end;

procedure TSlimListUnserializer.ReadExpectedChar(AExpectedChar: Char);
var
  CurChar: Char;
begin
  CurChar := ReadChar;
  if CurChar <> AExpectedChar then
    raise Exception.CreateFmt('"%s" expected, but "%s" found', [AExpectedChar, CurChar]);
end;

function TSlimListUnserializer.ReadLength: Integer;
const
  LengthLength = 6;
var
  Value: String;
begin
  Value := Copy(FContent, FPos, LengthLength);
  if not((Length(Value) = LengthLength) and TryStrToInt(Value, Result)) then
    raise Exception.CreateFmt('Invalid length "%s" at pos %d', [Value, FPos]);
  Inc(FPos, LengthLength);
  ReadColon;
end;

procedure TSlimListUnserializer.ReadLengthAndEntry(ATarget: TSlimList);
var
  CurChar       : Char;
  EntryLength   : Integer;
  EntryString   : String;
  SubEntryList  : TSlimListEntry;
  SubEntryString: TSlimStringEntry;
begin
  EntryLength := ReadLength;
  CurChar := LookChar;
  EntryString := ReadString(EntryLength);
  ReadColon;
  if CurChar = '[' then
  begin
    SubEntryList := TSlimListEntry.Create;
    ATarget.Add(SubEntryList);
    ReadContent(EntryString, SubEntryList.List);
  end
  else
  begin
    ATarget.Add(TSlimStringEntry.Create(EntryString))
  end;
end;

procedure TSlimListUnserializer.ReadList(ATarget: TSlimList);
var
  ItemsCount: Integer;
begin
  ReadExpectedChar('[');
  ItemsCount := ReadLength;
  while ItemsCount > 0 do
  begin
    ReadLengthAndEntry(ATarget);
    Dec(ItemsCount);
  end;
  ReadExpectedChar(']');
end;

function TSlimListUnserializer.ReadString(ALength: Integer): String;
begin
  Result := Copy(FContent, FPos, ALength);
  Inc(FPos, ALength);
end;

function TSlimListUnserializer.Unserialize: TSlimList;
begin
  Result := TSlimList.Create;
  try
    FPos := 1;
    ReadContent(FContent, Result);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

end.
