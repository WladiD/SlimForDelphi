// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Fixture;

interface

uses

  System.Classes,
  System.Rtti,
  System.SysUtils,

  Slim.List;

type

  /// <summary>
  ///   Classes with this attribute are automatically considered by the TSlimFixtureResolver
  /// </summary>
  SlimFixtureAttribute = class(TCustomAttribute)
  private
    FName     : String;
    FNamespace: String;
  public
    constructor Create; overload;
    constructor Create(const AName: String; const ANamespace: String = ''); overload;
    property Name: String read FName;
    property Namespace: String read FNamespace;
  end;

  /// <summary>
  ///   Determines how method calls should be synchronized
  /// </summary>
  TFixtureSyncMode = (
    smUndefined,
    /// <summary>
    ///   Method calls are not synchronized, i.e., they are executed directly from the thread
    ///   where the executor is active.
    /// </summary>
    smUnsynchronized,
    /// <summary>
    ///   Each individual method call of the fixture is executed in a separate Synchronize call.
    /// </summary>
    smSynchronized,
    /// <summary>
    ///   The complete execution of a fixture is executed in a single Synchronize call.
    /// </summary>
    smBulkSynchronized);

  /// <summary>
  /// Base class for all fixtures
  /// </summary>
  {$RTTI EXPLICIT METHODS([vcPublic, vcPublished]) PROPERTIES([vcPublic, vcPublished]) FIELDS([]) }
  TSlimFixture = class
  /// <summary>
  /// The following public SlimMethods are called in this order:
  /// 1. Table
  /// 2. Next the beginTable method is called.
  ///    Use this for initializations if you want to.
  /// Then for each row in the table:
  ///   2.1. First the Reset method is called, just in case you want to prepare or clean up.
  ///   2.2. Then all the inputs are loaded by calling the appropriate Set-Methods
  ///        (must be implemented in the derived class).
  ///   2.3. Then the Execute method of the fixture is called.
  ///   2.4  Finally all the output functions are called
  /// 3. Finally the EndTable method is called.
  ///    Use this for closedown and cleanup if you want to.
  /// </summary>
  public
    procedure Table(AList: TSlimList); virtual;
    procedure BeginTable; virtual;
    procedure Reset; virtual;
    procedure Execute; virtual;
    procedure EndTable; virtual;
  end;

  TSlimFixtureClass = class of TSlimFixture;

  TSlimFixtureResolver = class
  private
    FContext: TRttiContext;
  public
    constructor Create;
    destructor Destroy; override;
    function GetRttiInstanceTypeFromInstance(Instance: TObject): TRttiInstanceType;
    function TryGetSlimFixture(const AFixtureName: String; out AClassType: TRttiInstanceType): Boolean;
    function TryGetSlimMethod(AFixtureClass: TRttiInstanceType; const AName: String; ARawStmt: TSlimList; AArgStartIndex: Integer; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;
  end;

procedure RegisterSlimFixture(AFixtureClass: TSlimFixtureClass);

implementation

/// <summary>
///   Call this procedure with your fixture class to avoid the code elimination for it by the compiler
/// </summary>
procedure RegisterSlimFixture(AFixtureClass: TSlimFixtureClass);
begin
  // Nothing to do
end;

{ SlimFixtureAttribute }

constructor SlimFixtureAttribute.Create;
begin
  inherited Create;
end;

constructor SlimFixtureAttribute.Create(const AName: String; const ANamespace: String);
begin
  inherited Create;
  FName := AName;
  FNamespace := ANamespace;
end;

{ TSlimFixture }

procedure TSlimFixture.BeginTable;
begin

end;

procedure TSlimFixture.EndTable;
begin

end;

procedure TSlimFixture.Execute;
begin

end;

procedure TSlimFixture.Reset;
begin

end;

procedure TSlimFixture.Table(AList: TSlimList);
begin

end;

{ TSlimFixtureResolver }

constructor TSlimFixtureResolver.Create;
begin
  FContext := TRttiContext.Create;
end;

destructor TSlimFixtureResolver.Destroy;
begin
  FContext.Free;
  inherited;
end;

function TSlimFixtureResolver.GetRttiInstanceTypeFromInstance(Instance: TObject): TRttiInstanceType;
var
  RttiType: TRttiType;
begin
  RttiType := FContext.GetType(Instance.ClassInfo);
  Result := RttiType as TRttiInstanceType;
end;

/// <summary>
///   Try to find a fixture class by name
/// </summary>
/// <remarks>
///   Example:
///   <code>
///     [SlimFixture('Division', 'eg')]
///     TSlimDivisionFixture = class(TSlimFixture)...
///   </code>
///   A fixture can be found by the following namings:
///   - By the name of the SlimFixtureAttribute
///     For the upper example: "Division"
///   - By the combined namespace with the name of the SlimFixtureAttribute separated by "."
///     For the upper example: "eg.Division"
///   - By the class name of the fixture class
///     For the upper example: "TSlimDivisionFixture"
/// </remarks>
function TSlimFixtureResolver.TryGetSlimFixture(const AFixtureName: String; out AClassType: TRttiInstanceType): Boolean;
var
  Attribute: TCustomAttribute;
  LType    : TRttiType;

  function SlimFixtureNameMatch: Boolean;
  begin
    var FixtureAttr: SlimFixtureAttribute := SlimFixtureAttribute(Attribute);
    Result :=
      SameText(FixtureAttr.Name, AFixtureName) or
      (
        (FixtureAttr.Namespace <> '') and
        SameText(FixtureAttr.Namespace + '.' + FixtureAttr.Name, AFixtureName)
      );
  end;

begin
  for LType in FContext.GetTypes do
  begin
    if LType.IsInstance then
    begin
      AClassType := LType.AsInstance;
      for Attribute in AClassType.GetAttributes do
      begin
        if
          (Attribute.ClassType = SlimFixtureAttribute) and
          AClassType.MetaclassType.InheritsFrom(TSlimFixture) and
          (
            SlimFixtureNameMatch or
            AClassType.MetaclassType.ClassNameIs(AFixtureName)
          ) then
          Exit(true);
      end;
    end;
  end;
  Result := false;
  AClassType := nil;
end;

/// <param name="AName">If empty, looks for a constructor</param>
function TSlimFixtureResolver.TryGetSlimMethod(AFixtureClass: TRttiInstanceType; const AName: String; ARawStmt: TSlimList; AArgStartIndex: Integer; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;
var
  ArgsCount        : Integer;
  CheckMethod      : TRttiMethod;
  CheckMethodParams: TArray<TRttiParameter>;
  HasArgs          : Boolean;
  NameIsEmpty      : Boolean;

  function CheckMethodNameMatch: Boolean;
  begin
    Result :=
      (NameIsEmpty and CheckMethod.IsConstructor) or
      (not NameIsEmpty and SameText(AName, CheckMethod.Name));
  end;

  function CheckMethodParamsMatch: Boolean;
  begin
    CheckMethodParams := CheckMethod.GetParameters;
    var ParametersCount: Integer := Length(CheckMethodParams);
    Result :=
      (HasArgs and (ArgsCount = ParametersCount)) or
      (not HasArgs and (ParametersCount = 0));
  end;

begin
  NameIsEmpty := AName = '';
  HasArgs := AArgStartIndex > 0;
  if HasArgs then
    ArgsCount := ARawStmt.Count - AArgStartIndex;

  for CheckMethod in AFixtureClass.GetMethods do
  begin
    if not (CheckMethodNameMatch and CheckMethodParamsMatch) then
      Continue;
    if HasArgs then
    begin
      SetLength(AInvokeArgs, ArgsCount);
      for var ArgLoop := 0 to ArgsCount - 1 do
      begin
        var ArgRawIndex: Integer := AArgStartIndex + ArgLoop;
        var ParamTypeKind: TTypeKind := CheckMethodParams[ArgLoop].ParamType.TypeKind;
        var CurArgRaw: TSlimEntry := ARawStmt[ArgRawIndex];
        var CurValue: TValue := nil;

        case ParamTypeKind of
          tkInteger: ;
          tkFloat:
            CurValue := StrToFloat(CurArgRaw.ToString, TFormatSettings.Invariant);
          tkClass:
          begin
            var ParamClass: TClass := CheckMethodParams[ArgLoop].ParamType.AsInstance.MetaclassType;
            if (CurArgRaw is TSlimList) and (ParamClass.InheritsFrom(TSlimList)) then
              CurValue := CurArgRaw;
          end;
          tkString,
          tkUString:
            CurValue := CurArgRaw.ToString;
        end;
        AInvokeArgs[ArgLoop] := CurValue;
      end;
   end
    else
      AInvokeArgs := nil;
    ASlimMethod := CheckMethod;
    Exit(true);
  end;

  Result := false;
end;

end.
