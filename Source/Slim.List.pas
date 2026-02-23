// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.List;

interface

uses

  System.Character,
  System.Classes,
  System.Contnrs,
  System.Types,
  System.SysUtils,
  Slim.Common;

type

  TSlimEntryType = (setUndefined, setString, setList);

  TSlimEntry = class
  protected
    FEntryType: TSlimEntryType;
  public
    property EntryType: TSlimEntryType read FEntryType;
  end;

  TSlimString = class(TSlimEntry)
  private
    FValue: String;
  public
    constructor Create(const AValue: String);
    function ToString: String; override;
  end;

  TSlimList = class(TSlimEntry)
  private
    FList: TObjectList;
  protected
    function GetCount: Integer;
    function GetEntry(AIndex: Integer): TSlimEntry;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(AEntry: TSlimEntry): Integer;
    function Extract(AEntry: TSlimEntry): TSlimEntry;
    property Count: Integer read GetCount;
    property Entries[AIndex: Integer]: TSlimEntry read GetEntry; default;
  end;

  TSlimListSerializer = class
  private
    FBuilder : TStringBuilder;
    FSlimList: TSlimList;
    procedure WriteColon;
    procedure WriteLength(ALength: Integer);
    procedure WriteList(AList: TSlimList);
    procedure WriteString(const AValue: String);
  public
    constructor Create(ASlimList: TSlimList);
    destructor Destroy; override;
    function Serialize: String;
  end;

  TSlimListUnserializer = class
  private
    FContent: String;
    FPos    : Integer;
    function ReadChar: Char;
    procedure ReadColon;
    procedure ReadExpectedChar(AExpectedChar: Char);
    function ReadLength: Integer;
    function ReadString(ALength: Integer): String;
    procedure ReadLengthAndEntry(ATarget: TSlimList);
    procedure ReadList(ATarget: TSlimList);
  public
    constructor Create(const AContent: String);
    function Unserialize: TSlimList;
  end;

function SlimString(const AValue: String): TSlimString;
function SlimList(const AValues: Array of String): TSlimList; overload;
function SlimList(const AValues: Array of TSlimEntry): TSlimList; overload;

function SlimListSerialize(ASlimList: TSlimList): String;
function SlimListUnserialize(const AContent: String): TSlimList;

implementation

function SlimString(const AValue: String): TSlimString;
begin
  Result := TSlimString.Create(AValue);
end;

function SlimList(const AValues: Array of String): TSlimList;
begin
  Result := TSlimList.Create;
  for var Entry: String in AValues do
    Result.Add(TSlimString.Create(Entry));
end;

function SlimList(const AValues: Array of TSlimEntry): TSlimList;
begin
  Result := TSlimList.Create;
  for var Entry: TSlimEntry in AValues do
    Result.Add(Entry);
end;

function SlimListSerialize(ASlimList: TSlimList): String;
begin
  var Serializer: TSlimListSerializer := TSlimListSerializer.Create(ASlimList);
  try
    Result := Serializer.Serialize;
  finally
    Serializer.Free;
  end;
end;

function SlimListUnserialize(const AContent: String): TSlimList;
begin
  var Unserializer: TSlimListUnserializer := TSlimListUnserializer.Create(AContent);
  try
    Result := Unserializer.Unserialize;
  finally
    Unserializer.Free;
  end;
end;

{ TSlimStringEntry }

constructor TSlimString.Create(const AValue: String);
begin
  FValue := AValue;
  FEntryType := setString;
end;

function TSlimString.ToString: String;
begin
  Result := FValue;
end;

{ TSlimList }

constructor TSlimList.Create;
begin
  FList := TObjectList.Create(true);
  FEntryType := setList;
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

function TSlimList.Extract(AEntry: TSlimEntry): TSlimEntry;
begin
  Result := TSlimEntry(FList.Extract(AEntry));
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
    if Entry is TSlimList then
    begin
      PrevBuilder := FBuilder;
      try
        FBuilder := TStringBuilder.Create;
        WriteList(TSlimList(Entry));
        SubContent := FBuilder.ToString;
      finally
        FBuilder.Free;
        FBuilder := PrevBuilder;
      end;
      WriteString(SubContent);
    end
    else if Entry is TSlimString then
      WriteString(TSlimString(Entry).ToString);
  end;
  FBuilder.Append(']');
end;

procedure TSlimListSerializer.WriteString(const AValue: String);
begin
  WriteLength(Length(AValue));
  FBuilder.Append(AValue);
  WriteColon;
end;

{ TSlimListUnserializer }

constructor TSlimListUnserializer.Create(const AContent: String);
begin
  FContent := AContent;
  FPos := 1;
end;

function TSlimListUnserializer.ReadChar: Char;
begin
  if (FPos >= 1) and (FPos <= Length(FContent)) then
  begin
    Result := FContent[FPos];
    Inc(FPos);
  end
  else
    raise ESlim.Create('End reached');
end;

procedure TSlimListUnserializer.ReadColon;
begin
  ReadExpectedChar(':');
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
    raise Slim.Common.ESlim.CreateFmt('Invalid length "%s" at pos %d', [Value, FPos]);
  Inc(FPos, LengthLength);
  ReadColon;
end;

procedure TSlimListUnserializer.ReadLengthAndEntry(ATarget: TSlimList);
var
  LEntryLength : Integer;
  LEntryString : String;
  LSubEntryList: TSlimList;
  LSubUnserializer: TSlimListUnserializer;
begin
  LEntryLength := ReadLength;
  LEntryString := ReadString(LEntryLength);
  ReadColon;

  if LEntryString.StartsWith('[') then
  begin
    LSubEntryList := TSlimList.Create;
    try
      try
        LSubUnserializer := TSlimListUnserializer.Create(LEntryString);
        try
          LSubUnserializer.ReadList(LSubEntryList);
          // Commit nested list
          ATarget.Add(LSubEntryList);
        finally
          LSubUnserializer.Free;
        end;
      except
        on E: Exception do
        begin
          LSubEntryList.Free;
          ATarget.Add(TSlimString.Create(LEntryString));
        end;
      end;
    except
      LSubEntryList.Free;
      raise;
    end;
  end
  else
  begin
    ATarget.Add(TSlimString.Create(LEntryString));
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
    if FContent.StartsWith('[') then
      ReadList(Result)
    else
      raise ESlim.Create('Invalid Slim message format');
  except
    FreeAndNil(Result);
    raise;
  end;
end;

end.
