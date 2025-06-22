program SlimVerify;

uses
  Vcl.Forms,
  Main in 'Main.pas' {MainForm},
  SlimFixtures in 'SlimFixtures.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
