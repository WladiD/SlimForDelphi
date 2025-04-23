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
  public
    destructor Destroy; override;
    procedure AfterConstruction; override;
    function GetSelEntry: TEntry;
    procedure SelectEntryById(const AId: Integer);
    property Entries: TEntries read FEntries;
  end;

var
  MainForm: TMainForm;

implementation

{$IFDEF DEBUG}
uses

  Main.Fixtures;
{$ENDIF}

{$R *.dfm}

{ TMainForm }

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

function TMainForm.GetSelEntry: TEntry;
begin
  var Index: Integer := MainGrid.Row - 1;
  if Index < FEntries.Count then
    Result := FEntries[Index]
  else
    Result := nil;
end;

procedure TMainForm.SelectEntryById(const AId: Integer);
begin
  for var Loop: Integer := 0 to FEntries.Count - 1 do
  begin
    if FEntries[Loop].Id = AId then
    begin
      MainGrid.Row := Loop + 1;
      Exit;
    end;
  end;
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

end.
