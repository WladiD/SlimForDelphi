unit Main.Fixtures;

interface

uses

  System.DateUtils,
  System.Rtti,
  System.SysUtils,

  Vcl.Forms,

  Slim.Fixture,

  Data,
  Entry,
  Main;

type

  [SlimFixture('AddEntry', 'mfe')]
  TSlimAddEntryFixture = class(TSlimDecisionTableFixture)
  private
    function TryGetEntryForm(out AForm: TEntryForm): Boolean;
  public
    function  Add: Boolean;
    function  HasDelayedInfo(AMember: TRttiMember; var AInfo: TDelayedInfo): Boolean; override;
    function  Id: Integer;
    [SlimMemberSyncMode(smSynchronizedAndDelayed)]
    procedure Reset; override;
    procedure SetEntryDate(const AValue: String);
    procedure SetName(const AValue: String);
    function  WorkingYearsForTAIFUN: Double;
    function  SyncMode(AMember: TRttiMember): TSyncMode; override;
  end;

  [SlimFixture('SelectEntry', 'mfe')]
  TSlimSelectEntryFixture = class(TSlimDecisionTableFixture)
  public
    function  CurName: String;
    procedure SetSelId(AId: Integer);
  end;

implementation

{ TSlimAddEntryFixture }

function TSlimAddEntryFixture.Add: Boolean;
begin
  var EntryForm: TEntryForm := Screen.FocusedForm as TEntryForm;
  Result := EntryForm.OkButton.Enabled;
  EntryForm.OkButton.Click;
end;

function TSlimAddEntryFixture.Id: Integer;
begin
  Result := MainForm.Entries.Last.Id;
end;

function TSlimAddEntryFixture.HasDelayedInfo(AMember: TRttiMember; var AInfo: TDelayedInfo): Boolean;
begin
  Result := true;
  if SameText(AMember.Name, 'Reset') then
    AInfo.Owner := MainForm
  else
    Result := false;
end;

procedure TSlimAddEntryFixture.Reset;
begin
  MainForm.AddButton.Click;
end;

procedure TSlimAddEntryFixture.SetEntryDate(const AValue: String);
var
  EntryForm: TEntryForm;
  EntryDate: TDateTime;
begin
  if TryGetEntryForm(EntryForm) and TryISO8601ToDate(AValue, EntryDate) then
    EntryForm.EntryDatePicker.Date := EntryDate;
end;

procedure TSlimAddEntryFixture.SetName(const AValue: String);
var
  EntryForm: TEntryForm;
begin
  if TryGetEntryForm(EntryForm) then
    EntryForm.NameEdit.Text := AValue;
end;

function TSlimAddEntryFixture.SyncMode(AMember: TRttiMember): TSyncMode;
begin
  Result := smSynchronized;
end;

function TSlimAddEntryFixture.TryGetEntryForm(out AForm: TEntryForm): Boolean;
begin
  Result := Assigned(Screen.FocusedForm) and (Screen.FocusedForm is TEntryForm);
  if Result then
    AForm := Screen.FocusedForm as TEntryForm;
end;

function TSlimAddEntryFixture.WorkingYearsForTAIFUN: Double;
begin
  Result := MainForm.Entries.Last.WorkingYears;
end;

{ TSlimSelectEntryFixture }

function TSlimSelectEntryFixture.CurName: String;
begin
  var SelEntry := MainForm.GetSelEntry;
  if Assigned(SelEntry) then
    Result := SelEntry.Name
  else
    Result := '';
end;

procedure TSlimSelectEntryFixture.SetSelId(AId: Integer);
begin
  MainForm.SelectEntryById(AId);
end;

initialization

  RegisterSlimFixture(TSlimAddEntryFixture);
  RegisterSlimFixture(TSlimSelectEntryFixture);

end.
