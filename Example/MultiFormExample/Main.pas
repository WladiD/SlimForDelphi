unit Main;

interface

uses

  Winapi.Windows,
  Winapi.Messages,

  System.Classes,
  System.SysUtils,
  System.Rtti,
  System.Variants,

  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Grids,
  Vcl.StdCtrls,

  WDDT.DelayedMethod,

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
  public
    function  SyncMode(AMethod: TRttiMethod): TFixtureSyncMode; override;
    procedure Reset; override;
    procedure SetName(const AValue: String);
    function  Add: Boolean;
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

procedure TSlimAddTableFixture.Reset;
begin
  InitDelayedEvent;
  TDelayedMethod.Execute(
    procedure
    begin
      TDelayedMethod.Execute(
        procedure
        begin
          DelayedEvent.SetEvent;
        end, MainForm);
      MainForm.AddButton.Click;
    end, MainForm);
end;

procedure TSlimAddTableFixture.SetName(const AValue: String);
begin
  var EntryForm: TEntryForm := Screen.FocusedForm as TEntryForm;
  EntryForm.NameEdit.Text := AValue;
end;

function TSlimAddTableFixture.SyncMode(AMethod: TRttiMethod): TFixtureSyncMode;
begin
  Result := smSynchronized;
end;

end.
