// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Main;

interface

uses

  Winapi.Windows,
  Winapi.Messages,

  System.Classes,
  System.DateUtils,
  System.Rtti,
  System.SysUtils,
  System.Variants,

  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Grids,
  Vcl.StdCtrls,

  Slim.Fixture,
  Slim.Server,

  Data,
  Entry;

type

  TMainForm = class(TForm)
    AddButton  : TButton;
    BottomPanel: TPanel;
    MainGrid   : TStringGrid;
    procedure AddButtonClick(Sender: TObject);
  private
    FEntries: TEntries;
    procedure UpdateMainGrid;
    class constructor Create;
  public
    destructor Destroy; override;
    procedure AfterConstruction; override;
  end;

  [SlimFixture('AddEntries', 'mfe')]
  TSlimAddTableFixture = class(TSlimFixture)
  private
    function TryGetEntryForm(out AForm: TEntryForm): Boolean;
  public
    function  Add: Boolean;
    function  HasDelayedInfo(AMethod: TRttiMethod; out AInfo: TDelayedInfo): Boolean; override;
    function  Id: Integer;
    procedure Reset; override;
    procedure SetEntryDate(const AValue: String);
    procedure SetName(const AValue: String);
    function  WorkingYearsForTAIFUN: Double;
    function  SyncMode(AMethod: TRttiMethod): TFixtureSyncMode; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

{ TMainForm }

class constructor TMainForm.Create;
begin
  RegisterSlimFixture(TSlimAddTableFixture);
end;

procedure TMainForm.AfterConstruction;
begin
  inherited;
  FEntries := TEntries.Create(true);
  MainGrid.ColCount := 4;
  MainGrid.ColWidths[1] := 50;
  MainGrid.ColWidths[2] := 200;
  MainGrid.ColWidths[3] := 100;
  UpdateMainGrid;

  var SlimServer: TSlimServer := TSlimServer.Create(Self);
  SlimServer.DefaultPort := 9000;
  SlimServer.Active := True;
end;

destructor TMainForm.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TMainForm.UpdateMainGrid;
begin
  if FEntries.Count = 0 then
    MainGrid.RowCount := 2
  else
    MainGrid.RowCount := FEntries.Count + 1;
  MainGrid.Cells[1, 0] := 'Id';
  MainGrid.Cells[2, 0] := 'Name';
  MainGrid.Cells[3, 0] := 'Entry date';

  for var Loop: Integer := 0 to FEntries.Count - 1 do
  begin
    var LEntry: TEntry := FEntries[Loop];
    var RowIndex: Integer := Loop + 1;
    MainGrid.Cells[1, RowIndex] := LEntry.Id.ToString;
    MainGrid.Cells[2, RowIndex] := LEntry.Name;
    MainGrid.Cells[3, RowIndex] := DateToStr(LEntry.EntryDate);
  end;
end;

procedure TMainForm.AddButtonClick(Sender: TObject);
begin
  var NewEntry: TEntry := TEntry.Create;
  NewEntry.Id := TEntry.GetNextId;
  NewEntry.EntryDate := Date;

  var Form: TEntryForm := TEntryForm.Create(Self, NewEntry);
  try
    Form.PopupParent := Self;
    if Form.ShowModal = mrOk then
    begin
      FEntries.Add(NewEntry);
      NewEntry := nil;
      UpdateMainGrid;
    end;
  finally
    NewEntry.Free;
    Form.Free;
  end;
end;

{ TSlimAddTableFixture }

function TSlimAddTableFixture.Add: Boolean;
begin
  var EntryForm: TEntryForm := Screen.FocusedForm as TEntryForm;
  Result := EntryForm.OkButton.Enabled;
  EntryForm.OkButton.Click;
end;

function TSlimAddTableFixture.Id: Integer;
begin
  Result := MainForm.FEntries.Last.Id;
end;

function TSlimAddTableFixture.HasDelayedInfo(AMethod: TRttiMethod; out AInfo: TDelayedInfo): Boolean;
begin
  Result := true;
  if SameText(AMethod.Name, 'Reset') then
    AInfo.Owner := MainForm
  else
    Result := false;
end;

procedure TSlimAddTableFixture.Reset;
begin
  MainForm.AddButton.Click;
end;

procedure TSlimAddTableFixture.SetEntryDate(const AValue: String);
var
  EntryForm: TEntryForm;
  EntryDate: TDateTime;
begin
  if TryGetEntryForm(EntryForm) and TryISO8601ToDate(AValue, EntryDate) then
    EntryForm.EntryDatePicker.Date := EntryDate;
end;

procedure TSlimAddTableFixture.SetName(const AValue: String);
var
  EntryForm: TEntryForm;
begin
  if TryGetEntryForm(EntryForm) then
    EntryForm.NameEdit.Text := AValue;
end;

function TSlimAddTableFixture.SyncMode(AMethod: TRttiMethod): TFixtureSyncMode;
begin
  if SameText(AMethod.Name, 'Reset') then
    Result := smSynchronizedAndDelayed
  else
    Result := smSynchronized;
end;

function TSlimAddTableFixture.TryGetEntryForm(out AForm: TEntryForm): Boolean;
begin
  Result := Assigned(Screen.FocusedForm) and (Screen.FocusedForm is TEntryForm);
  if Result then
    AForm := Screen.FocusedForm as TEntryForm;
end;

function TSlimAddTableFixture.WorkingYearsForTAIFUN: Double;
begin
  Result := MainForm.FEntries.Last.WorkingYears;
end;

end.
