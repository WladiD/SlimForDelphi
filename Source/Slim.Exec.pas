// ======================================================================
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
    function GetRawStmtString(AIndex: Integer): String;
  public
    constructor Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext); virtual;
    function Execute: TSlimList; virtual;
    property IdParam: String index 0 read GetRawStmtString;
  end;

  TSlimStatementClass = class of TSlimStatement;

  TSlimStmtImport = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property PathParam: String index 2 read GetRawStmtString;
  end;

  TSlimStmtMake = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property InstanceParam: String index 2 read GetRawStmtString;
    property ClassParam: String index 3 read GetRawStmtString;
  end;

  TSlimStmtCall = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property InstanceParam: String index 2 read GetRawStmtString;
    property FunctionParam: String index 3 read GetRawStmtString;
  end;

  TSlimStmtCallAndAssign = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property SymbolParam: String index 2 read GetRawStmtString;
    property InstanceParam: String index 3 read GetRawStmtString;
    property FunctionParam: String index 4 read GetRawStmtString;
  end;

  TSlimStmtAssign = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property SymbolParam: String index 2 read GetRawStmtString;
    property ValueParam: String index 3 read GetRawStmtString;
  end;

  TSlimExecutor = class
  private
    FInstances: TSlimFixtureDictionary;
    function ExecuteStmt(ARawStmt: TSlimList; const AContext: TSlimStatementContext): TSlimList;
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

function TSlimStatement.GetRawStmtString(AIndex: Integer): String;
begin
  if (AIndex < FRawStmt.Count) and (FRawStmt[AIndex] is TSlimString) then
    Result := FRawStmt[AIndex].ToString
  else
    Result := '';
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

function TSlimExecutor.ExecuteStmt(ARawStmt: TSlimList; const AContext: TSlimStatementContext): TSlimList;
var
  Stmt     : TSlimStatement;
  StmtClass: TSlimStatementClass;
  Instr    : TSlimInstruction;
  InstrStr : String;
begin
  InstrStr := ARawStmt[1].ToString;
  Instr := StringToSlimInstruction(InstrStr);
  StmtClass := SlimInstructionToStatementClass(Instr);
  Stmt := StmtClass.Create(ARawStmt, AContext);
  try
    Result := Stmt.Execute;
  finally
    Stmt.Free;
  end;
end;

function TSlimExecutor.Execute(ARawStmts: TSlimList): TSlimList;
var
  Context : TSlimStatementContext;
  Resolver: TSlimFixtureResolver;
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
          var LStmtResult: TSlimList := ExecuteStmt(TSlimList(LRawStmt), Context);
          if Assigned(LStmtResult) then
            Result.Add(LStmtResult);
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
