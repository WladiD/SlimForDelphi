// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Main;

interface

uses

  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Menus,
  Vcl.StdCtrls,

  Common.LogSlimMain,
  SlimVerify.Pathologies;

type

  /// <summary>
  ///   The simulation target. Without any switch this is a plain Slim host like
  ///   every other example; with the switches from SlimVerify.Pathologies it
  ///   simulates a slow start up, modal start up dialogs, an aborted start up, a
  ///   host death and an occupied port.
  /// </summary>
  TMainForm = class(TLogSlimMainForm)
  private
    FOptions     : TSlimVerifyOptions;
    FStartupTimer: TTimer;
    procedure BuildMainMenu;
    procedure RunStartupPathologies;
    procedure StartupTimerTick(ASender: TObject);
  protected
    function AutoStartSlimServer: Boolean; override;
  public
    procedure AfterConstruction; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.AfterConstruction;
begin
  FOptions := SlimVerifyOptions;

  // The main window carries a menu bar - that is how the proxy tells a main
  // window from a modal message window, because the title does not.
  BuildMainMenu;

  inherited;

  if FOptions.DieAfterMs > 0 then
  begin
    Log(Format('--DieAfter=%d: this process will terminate with exit code %d',
      [FOptions.DieAfterMs, FOptions.DieExitCode]));
    SlimVerifyDieAfter(FOptions.DieAfterMs, FOptions.DieExitCode);
  end;

  if FOptions.HoldPort > 0 then
  begin
    Log(Format('--HoldPort=%d: occupying the port WITHOUT serving Slim', [FOptions.HoldPort]));
    SlimVerifyHoldPort(FOptions.HoldPort);
  end;

  if FOptions.AbortWindowClass <> '' then
  begin
    Log(Format('--AbortWindow=%s: showing that window, Slim will never start',
      [FOptions.AbortWindowClass]));
    SlimVerifyShowStandingWindow(FOptions.AbortWindowClass, 'SlimVerify start up aborted');
  end;

  if not AutoStartSlimServer and not FOptions.SuppressesSlimServer then
  begin
    // The start up pathologies block the main thread, so they must not run
    // before the window is on screen.
    FStartupTimer := TTimer.Create(Self);
    FStartupTimer.Interval := 200;
    FStartupTimer.OnTimer := StartupTimerTick;
    FStartupTimer.Enabled := True;
  end;
end;

function TMainForm.AutoStartSlimServer: Boolean;
begin
  Result := (FOptions.StartupDelayMs = 0) and (FOptions.StartupDialogMs = 0) and
            not FOptions.SuppressesSlimServer;
end;

procedure TMainForm.BuildMainMenu;
var
  LItem: TMenuItem;
  LMenu: TMainMenu;
begin
  LMenu := TMainMenu.Create(Self);
  LItem := TMenuItem.Create(LMenu);
  LItem.Caption := 'SlimVerify';
  LMenu.Items.Add(LItem);
  Menu := LMenu;
end;

procedure TMainForm.StartupTimerTick(ASender: TObject);
begin
  FStartupTimer.Enabled := False;
  RunStartupPathologies;
end;

procedure TMainForm.RunStartupPathologies;
begin
  if FOptions.StartupDelayMs > 0 then
  begin
    Log(Format('--StartupDelay=%d: the Slim server stays down for that long',
      [FOptions.StartupDelayMs]));
    SlimVerifyPumpFor(FOptions.StartupDelayMs);
  end;

  if FOptions.StartupDialogMs > 0 then
  begin
    Log(Format('--StartupDialog=%d: modal window with a button on class "%s"',
      [FOptions.StartupDialogMs, SlimVerifyCustomControlClass]));
    var LClicked: String := SlimVerifyShowModalWindow(SlimVerifyDialogClass,
      SlimVerifyCustomControlClass, 'SlimVerify start up',
      'Please confirm to continue the start up.', ['OK'], FOptions.StartupDialogMs);
    if LClicked <> '' then
      Log(Format('start up dialog was dismissed with "%s"', [LClicked]))
    else
      Log('start up dialog closed itself - nobody dismissed it');
  end;

  StartSlimServer;
  Log('Slim server active');
end;

end.
