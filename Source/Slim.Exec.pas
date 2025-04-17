﻿// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Exec;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.SysUtils,

  Slim.Fixture,
  Slim.List;

type

  TSlimInstruction = (
    siUndefined,
    siImport,        // [<id>, import, <path>]
    siMake,          // [<id>, make, <instance>, <class>, <arg>...]
    siCall,          // [<id>, call, <instance>, <function>, <arg>...]
    siCallAndAssign, // [<id>, callAndAssign, <symbol>, <instance>, <function>, <arg>...]
    siAssign);       // [<id>, assign, <symbol>, <value>]

  TSlimFixtureDictionary = TObjectDictionary<String, TSlimFixture>;

  TSlimStatementContext = record
  public
    Resolver : TSlimFixtureResolver;
    Instances: TSlimFixtureDictionary;
  end;

  TSlimStatement = class
  protected
    FContext: TSlimStatementContext;
    FRawStmt: TSlimList;
  public
    constructor Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext); virtual;
    function Execute: TSlimList; virtual;
  end;

  TSlimStatementClass = class of TSlimStatement;

  TSlimStmtImport = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
  end;

  TSlimStmtMake = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
  end;

  TSlimStmtCall = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
  end;

  TSlimStmtCallAndAssign = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
  end;

  TSlimStmtAssign = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
  end;

  TSlimExecutor = class
  private
    FInstances: TSlimFixtureDictionary;
  public
    constructor Create;
    destructor Destroy; override;

    function Execute(ARawStmts: TSlimList): TSlimList;
  end;

function StringToSlimInstruction(const AValue: String): TSlimInstruction;
function SlimInstructionToStatementClass(AInstruction: TSlimInstruction): TSlimStatementClass;

implementation

function StringToSlimInstruction(const AValue: String): TSlimInstruction;
begin
  if SameText(AValue, 'import') then
    Result := siImport
  else if SameText(AValue, 'make') then
    Result := siMake
  else if SameText(AValue, 'call') then
    Result := siCall
  else if SameText(AValue, 'callAndAssign') then
    Result := siCallAndAssign
  else if SameText(AValue, 'assign') then
    Result := siAssign
  else
    Result := siUndefined;
end;

function SlimInstructionToStatementClass(AInstruction: TSlimInstruction): TSlimStatementClass;
const
  InstructionClassMap: Array [TSlimInstruction] of TSlimStatementClass = (
    { siUndefined     } TSlimStatement,
    { siImport        } TSlimStmtImport,
    { siMake          } TSlimStmtMake,
    { siCall          } TSlimStmtCall,
    { siCallAndAssign } TSlimStmtCallAndAssign,
    { siAssign        } TSlimStmtAssign);
begin
  Result := InstructionClassMap[AInstruction];
end;

{ TSlimStatement }

constructor TSlimStatement.Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext);
begin
  FRawStmt := ARawStmt;
  FContext := AContext;
end;

function TSlimStatement.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtImport }

function TSlimStmtImport.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtMake }

function TSlimStmtMake.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtCall }

function TSlimStmtCall.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtCallAndAssign }

function TSlimStmtCallAndAssign.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtAssign }

function TSlimStmtAssign.Execute: TSlimList;
begin
  Result := nil;
end;


{ TSlimExecutor }

constructor TSlimExecutor.Create;
begin
  FInstances := TSlimFixtureDictionary.Create([doOwnsValues]);
end;

destructor TSlimExecutor.Destroy;
begin
  FInstances.Free;
  inherited;
end;

function TSlimExecutor.Execute(ARawStmts: TSlimList): TSlimList;
var
  Context  : TSlimStatementContext;
  Instr    : TSlimInstruction;
  InstrStr : String;
  Resolver : TSlimFixtureResolver;
  Stmt     : TSlimStatement;
  StmtClass: TSlimStatementClass;
begin
  Resolver := nil;
  Result := TSlimList.Create;
  try
    try
      Resolver := TSlimFixtureResolver.Create;

      Context := Default(TSlimStatementContext);
      Context.Resolver := Resolver;
      Context.Instances := FInstances;

      for var Loop := 0 to ARawStmts.Count - 1 do
      begin
        var LRawStmt: TSlimEntry := ARawStmts[Loop];
        if LRawStmt is TSlimList then
        begin
          var LRawStmtList: TSlimList := TSlimList(LRawStmt);
          InstrStr := LRawStmtList[1].ToString;
          Instr := StringToSlimInstruction(InstrStr);
          StmtClass := SlimInstructionToStatementClass(Instr);
          Stmt := StmtClass.Create(LRawStmtList, Context);
          try
            var LStmtResult: TSlimList := Stmt.Execute;
            if Assigned(LStmtResult) then
              Result.Add(LStmtResult);
          finally
            Stmt.Free;
          end;
        end;
      end;
    finally
      Resolver.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
