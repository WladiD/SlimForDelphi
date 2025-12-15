// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Logger;

interface

uses

  System.Classes,
  System.IOUtils,
  System.SysUtils,

  Slim.List;

type

  ISlimLogger = interface
    ['{E4633017-B8DB-46D7-9C5D-0B8A5BCC3CCE}']
    procedure EnterList(const AList: TSlimList);
    procedure ExitList(const AList: TSlimList);
    procedure LogInstruction(const AInstruction: TSlimList);
  end;

  TSlimFileLogger = class(TInterfacedObject, ISlimLogger)
  private
    FFileName: String;
    procedure WriteLine(const AText: String);
  public
    constructor Create(const AFileName: String);
    procedure EnterList(const AList: TSlimList);
    procedure ExitList(const AList: TSlimList);
    procedure LogInstruction(const AInstruction: TSlimList);
  end;

implementation

{ TSlimFileLogger }

constructor TSlimFileLogger.Create(const AFileName: String);
begin
  inherited Create;
  FFileName := AFileName;
  TDirectory.CreateDirectory(TPath.GetDirectoryName(FFileName));
  WriteLine(Format('Logger started at %s', [DateTimeToStr(Now)]));
end;

procedure TSlimFileLogger.WriteLine(const AText: String);
begin
  TFile.AppendAllText(FFileName, AText + sLineBreak, TEncoding.UTF8);
end;

procedure TSlimFileLogger.EnterList(const AList: TSlimList);
begin
  WriteLine('======================================================================');
  WriteLine(Format('Timestamp: %s', [DateTimeToStr(Now)]));
  WriteLine(Format('ENTER Slim List (Count: %d)', [AList.Count]));
  WriteLine('----------------------------------------------------------------------');
end;

procedure TSlimFileLogger.ExitList(const AList: TSlimList);
begin
  WriteLine('EXIT Slim List');
  WriteLine('======================================================================');
  WriteLine(''); 
end;

procedure TSlimFileLogger.LogInstruction(const AInstruction: TSlimList);
begin
  WriteLine(Format('  >> Executing: %s', [SlimListSerialize(AInstruction)]));
end;

end.
