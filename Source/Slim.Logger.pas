// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Logger;

interface

uses

  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.SysUtils,

  Slim.List;

type

  ISlimLogger = interface
    ['{E4633017-B8DB-46D7-9C5D-0B8A5BCC3CCE}']
    procedure EnterList(const AList: TSlimList);
    procedure ExitList(const AList: TSlimList);
    procedure LogInstruction(const AInstruction: TSlimList);
    /// <summary>
    ///   The result of the instruction that was logged last. Without it a log
    ///   only shows what was asked, never what came back - and the cause of a
    ///   failure is then in no log at all.
    /// </summary>
    procedure LogResult(const AResult: TSlimList);
    /// <summary>A failure together with the source that produced it.</summary>
    procedure LogError(const ASource, AMessage: String);
    /// <summary>
    ///   An event worth a timestamp: target switch, host start and exit,
    ///   watchdog finding.
    /// </summary>
    procedure LogEvent(const ACategory, AMessage: String);
  end;

  TSlimFileLogger = class(TInterfacedObject, ISlimLogger)
  private
    FFileName: String;
    FLock    : TCriticalSection;
    FStream  : TFileStream;
    FWriter  : TStreamWriter;
    procedure WriteLine(const AText: String);
  public
    constructor Create(const AFileName: String);
    destructor Destroy; override;
    procedure EnterList(const AList: TSlimList);
    procedure ExitList(const AList: TSlimList);
    procedure LogInstruction(const AInstruction: TSlimList);
    procedure LogResult(const AResult: TSlimList);
    procedure LogError(const ASource, AMessage: String);
    procedure LogEvent(const ACategory, AMessage: String);
  end;

implementation

{ TSlimFileLogger }

constructor TSlimFileLogger.Create(const AFileName: String);
begin
  inherited Create;
  FFileName := AFileName;
  FLock := TCriticalSection.Create;
  TDirectory.CreateDirectory(TPath.GetDirectoryName(FFileName));

  if FileExists(FFileName) then
    FStream := TFileStream.Create(FFileName, fmOpenWrite or fmShareDenyNone)
  else
    FStream := TFileStream.Create(FFileName, fmCreate or fmShareDenyNone);

  FStream.Seek(0, soEnd);
  FWriter := TStreamWriter.Create(FStream, TEncoding.UTF8);
  FWriter.AutoFlush := True;

  WriteLine(Format('Logger started at %s', [DateTimeToStr(Now)]));
end;

destructor TSlimFileLogger.Destroy;
begin
  FWriter.Free;
  FStream.Free;
  FLock.Free;
  inherited;
end;

procedure TSlimFileLogger.WriteLine(const AText: String);
begin
  FLock.Enter;
  try
    FWriter.WriteLine(AText);
  finally
    FLock.Leave;
  end;
end;

procedure TSlimFileLogger.EnterList(const AList: TSlimList);
begin
  WriteLine('======================================================================' + sLineBreak +
    Format('Timestamp: %s', [DateTimeToStr(Now)]) + sLineBreak +
    Format('ENTER Slim List (Count: %d)', [AList.Count]) + sLineBreak +
    '----------------------------------------------------------------------');
end;

procedure TSlimFileLogger.ExitList(const AList: TSlimList);
begin
  WriteLine('EXIT Slim List' + sLineBreak +
    '======================================================================' + sLineBreak);
end;

procedure TSlimFileLogger.LogInstruction(const AInstruction: TSlimList);
begin
  WriteLine(Format('  >> Executing: %s', [SlimListSerialize(AInstruction)]));
end;

procedure TSlimFileLogger.LogResult(const AResult: TSlimList);
begin
  WriteLine(Format('  << Result   : %s', [SlimListSerialize(AResult)]));
end;

procedure TSlimFileLogger.LogError(const ASource, AMessage: String);
begin
  WriteLine(Format('  !! %s [%s]: %s', [FormatDateTime('hh:nn:ss.zzz', Now), ASource, AMessage]));
end;

procedure TSlimFileLogger.LogEvent(const ACategory, AMessage: String);
begin
  WriteLine(Format('  -- %s [%s]: %s', [FormatDateTime('hh:nn:ss.zzz', Now), ACategory, AMessage]));
end;

end.
