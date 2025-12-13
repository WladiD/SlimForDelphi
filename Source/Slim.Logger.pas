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
    ['{8A4B6C2D-1E3F-4058-9201-C1C2C3C4C5C6}']
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
  // Log the instruction immediately before execution
  // We use the serializer to get a clean string representation of the instruction
  WriteLine(Format('  >> Executing: %s', [SlimListSerialize(AInstruction)]));
end;

end.
