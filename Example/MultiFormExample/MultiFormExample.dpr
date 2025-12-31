program MultiFormExample;

uses
  Vcl.Forms,
  Main in 'Main.pas' {MainForm},
  Entry in 'Entry.pas' {EntryForm},
  Data in 'Data.pas';

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
