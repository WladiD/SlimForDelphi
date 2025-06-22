program TwoMinuteExample;

uses
  Vcl.Forms,
  Common.LogSlimMain in '..\Common\Common.LogSlimMain.pas' {LogSlimMainForm},
  Main in 'Main.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
