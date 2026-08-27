program SlimVerify;

uses
  Vcl.Forms,
  Common.LogSlimMain in '..\..\Example\Common\Common.LogSlimMain.pas' {LogSlimMainForm},
  SlimVerify.Pathologies in 'SlimVerify.Pathologies.pas',
  SlimFixtures in 'SlimFixtures.pas',
  Main in 'Main.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
