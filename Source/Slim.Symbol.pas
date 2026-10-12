// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Symbol;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  System.Rtti,
  System.SysUtils;

type

  TSlimSymbolDictionary = class;

  /// <summary>
  ///   Receives the free notifications of the components that symbols hold and forwards them to
  ///   the dictionary.
  /// </summary>
  TSlimSymbolNexus = class(TComponent)
  private
    FDictionary: TSlimSymbolDictionary;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  /// <summary>
  ///   Symbols of a Slim connection. A symbol that holds a TComponent is cleared as soon as the
  ///   component is destroyed: FitNesse pages keep form references in symbols long after a
  ///   modal form died with its click handler, and a later use of such a symbol must get nil
  ///   instead of a dangling pointer. Access is serialized through a monitor on the instance,
  ///   because the executor thread resolves symbols while the main thread destroys the
  ///   components behind them. The class check of SymbolObjectAs therefore runs under the lock:
  ///   the destructor of a tracked component blocks in ComponentFreed until the check is done.
  ///   Use SetSymbol instead of AddOrSetValue to store values, otherwise components are not
  ///   tracked. Registering and removing the free notification happens in the main thread.
  /// </summary>
  TSlimSymbolDictionary = class(TDictionary<String, TValue>)
  private
    FNexus: TSlimSymbolNexus;
    procedure ComponentFreed(AComponent: TComponent);
    function  EvalSymbolsMatch(const AMatch: TMatch): String;
    procedure Store(const AName: String; const AValue: TValue);
    function  SymbolObjectUnlocked(const AValue: String): TObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear; reintroduce;
    function  EvalSymbols(const AInput: String): String;
    procedure SetSymbol(const AName: String; const AValue: TValue);
    function  SymbolObject(const AValue: String): TObject;
    /// <summary>
    ///   Resolves a symbol to an object of the given class, nil if the symbol is unknown, holds
    ///   no object, holds a destroyed component or an object of another class.
    /// </summary>
    function  SymbolObjectAs(const AValue: String; AClass: TClass): TObject;
  end;

const

  SymbolRegExPattern = '\$(([A-Za-z\p{L}][\w\p{L}]*)|`([^`]+)`)';
  SymbolOnlyRegExPattern = '^\s*' + SymbolRegExPattern + '\s*$';

implementation

procedure RunInMainThread(const AProc: TThreadProcedure);
begin
  if TThread.CurrentThread.ThreadID = MainThreadID then
    AProc
  else
    TThread.Synchronize(nil, AProc);
end;

{ TSlimSymbolNexus }

procedure TSlimSymbolNexus.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and Assigned(FDictionary) then
    FDictionary.ComponentFreed(AComponent);
end;

{ TSlimSymbolDictionary }

constructor TSlimSymbolDictionary.Create;
begin
  inherited Create;
  FNexus := TSlimSymbolNexus.Create(nil);
  FNexus.FDictionary := Self;
end;

destructor TSlimSymbolDictionary.Destroy;
var
  Nexus: TSlimSymbolNexus;
begin
  Nexus := FNexus;
  FNexus := nil;
  if Assigned(Nexus) then
  begin
    Nexus.FDictionary := nil;
    // The nexus unregisters itself from every tracked component, so it dies in the main thread.
    // Queued, not synchronized: a connection ends in the executor thread while the main thread
    // may already be shutting down, and waiting for it there would hang the executor.
    if TThread.CurrentThread.ThreadID = MainThreadID then
      Nexus.Free
    else
      TThread.ForceQueue(nil,
        procedure
        begin
          Nexus.Free;
        end);
  end;
  inherited;
end;

procedure TSlimSymbolDictionary.Clear;
begin
  TMonitor.Enter(Self);
  try
    inherited Clear;
  finally
    TMonitor.Exit(Self);
  end;
end;

// Runs in the main thread, inside the destructor of the component, before its memory is
// released. Only pointers are compared, the component is never touched.
procedure TSlimSymbolDictionary.ComponentFreed(AComponent: TComponent);
var
  Names: TList<String>;
begin
  Names := nil;
  TMonitor.Enter(Self);
  try
    for var Pair: TPair<String, TValue> in Self do
    begin
      if Pair.Value.IsObject and (Pair.Value.AsObject = AComponent) then
      begin
        if not Assigned(Names) then
          Names := TList<String>.Create;
        Names.Add(Pair.Key);
      end;
    end;
    if Assigned(Names) then
      for var Name: String in Names do
        inherited AddOrSetValue(Name, TValue.Empty);
  finally
    TMonitor.Exit(Self);
    Names.Free;
  end;
end;

function TSlimSymbolDictionary.EvalSymbols(const AInput: String): String;
begin
  TMonitor.Enter(Self);
  try
    Result := TRegEx.Replace(AInput, SymbolRegExPattern, EvalSymbolsMatch);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TSlimSymbolDictionary.EvalSymbolsMatch(const AMatch: TMatch): String;
var
  Found      : Boolean;
  SymbolName : String;
  SymbolValue: TValue;
begin
  Found := AMatch.Groups.Count > 0;
  if Found then
  begin
    SymbolName := AMatch.Groups[1].Value;
    Found := TryGetValue(SymbolName, SymbolValue);
    if Found then
      Result := SymbolValue.ToString;
  end;
  if not Found then
    Result := AMatch.Value;
end;

procedure TSlimSymbolDictionary.SetSymbol(const AName: String; const AValue: TValue);
begin
  if AValue.IsObject and (AValue.AsObject is TComponent) then
    RunInMainThread(
      procedure
      begin
        TComponent(AValue.AsObject).FreeNotification(FNexus);
        Store(AName, AValue);
      end)
  else
    Store(AName, AValue);
end;

procedure TSlimSymbolDictionary.Store(const AName: String; const AValue: TValue);
begin
  TMonitor.Enter(Self);
  try
    inherited AddOrSetValue(AName, AValue);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TSlimSymbolDictionary.SymbolObject(const AValue: String): TObject;
begin
  TMonitor.Enter(Self);
  try
    Result := SymbolObjectUnlocked(AValue);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TSlimSymbolDictionary.SymbolObjectAs(const AValue: String; AClass: TClass): TObject;
begin
  TMonitor.Enter(Self);
  try
    Result := SymbolObjectUnlocked(AValue);
    if Assigned(Result) and Assigned(AClass) and not (Result is AClass) then
      Result := nil;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TSlimSymbolDictionary.SymbolObjectUnlocked(const AValue: String): TObject;
var
  Match      : TMatch;
  SymbolName : String;
  SymbolValue: TValue;
begin
  Result := nil;
  Match := TRegEx.Match(AValue, SymbolOnlyRegExPattern, []);
  if not (Match.Success and (Match.Groups.Count > 0)) then
    Exit;
  SymbolName := Match.Groups[1].Value;
  if TryGetValue(SymbolName, SymbolValue) and SymbolValue.IsObject then
    Result := SymbolValue.AsObject;
end;

end.
