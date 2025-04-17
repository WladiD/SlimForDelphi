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

  TSlimExecutor = class
  private
    FInstances: TSlimFixtureDictionary;
  public
    constructor Create;
    destructor Destroy; override;

    function Execute(AStmts: TSlimList): TSlimList;
  end;

function StringToSlimInstruction(const AValue: String): TSlimInstruction;

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

function TSlimExecutor.Execute(AStmts: TSlimList): TSlimList;
begin

end;

end.
