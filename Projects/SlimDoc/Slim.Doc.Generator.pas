// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Generator;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils,

  mormot.core.base,
  mormot.core.data,
  mormot.core.mustache,
  mormot.core.variants,

  Slim.Doc.Model,
  Slim.Doc.Utils,
  Slim.Doc.UsageAnalyzer;

type

  TSlimDocGenerator = class
  private
    function  BuildLink(const APageName, AMemberName: String; AIsMethod: Boolean; AParamCount: Integer): String;
    function  FormatXmlComment(const AXml: String): String;
    function  GenerateMemberData(AFixture: TSlimDocFixture; AMember: TSlimDocMember; AUsageMap: TUsageMap): Variant;
    function  HasInheritedMembers(AFixture: TSlimDocFixture): Boolean;
    procedure SortFixtures(AFixtures: TList<TSlimDocFixture>);
    procedure SortMembers(AList: TList<TSlimDocMember>);
  public
    function Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const ATemplateContent, AOutputFilePath: String): String;
  end;

implementation

{ TSlimDocGenerator }

function TSlimDocGenerator.HasInheritedMembers(AFixture: TSlimDocFixture): Boolean;
begin
  for var M: TSlimDocMethod in AFixture.Methods do
    if M.IsInherited then
      Exit(True);

  for var P: TSlimDocProperty in AFixture.Properties do
    if P.IsInherited then
      Exit(True);

  Result := False;
end;

procedure TSlimDocGenerator.SortFixtures(AFixtures: TList<TSlimDocFixture>);
begin
  AFixtures.Sort(TComparer<TSlimDocFixture>.Construct(
    function(const L, R: TSlimDocFixture): Integer
    begin
      Result := CompareText(L.Namespace, R.Namespace);
      if Result = 0 then
        Result := CompareText(L.Name, R.Name);
    end));
end;

procedure TSlimDocGenerator.SortMembers(AList: TList<TSlimDocMember>);
begin
  AList.Sort(TComparer<TSlimDocMember>.Construct(
    function(const L, R: TSlimDocMember): Integer
    begin
      Result := CompareText(L.Name, R.Name);
    end));
end;

function TSlimDocGenerator.FormatXmlComment(const AXml: String): String;
begin
  if AXml = '' then
    Exit('');

  Result := AXml;
  // Summary
  Result := TRegEx.Replace(Result, '<summary>\s*(.*?)</summary>', '<div class="xml-summary">$1</div>', [roSingleLine, roIgnoreCase]);

  // Params
  Result := TRegEx.Replace(Result, '<param name="(.*?)">\s*', '<div class="xml-param"><span class="xml-param-name">$1</span>: ', [roIgnoreCase]);
  Result := Result.Replace('</param>', '</div>', [rfReplaceAll, rfIgnoreCase]);

  // Returns
  Result := Result.Replace('<returns>', '<div class="xml-returns"><span class="xml-param-name">Returns:</span> ', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('</returns>', '</div>', [rfReplaceAll, rfIgnoreCase]);
end;

function TSlimDocGenerator.BuildLink(const APageName, AMemberName: String; AIsMethod: Boolean; AParamCount: Integer): String;
var
  Fragment: String;
  Parts   : TArray<String>;
  Spaced  : String;
begin
  Fragment := 'text=' + AMemberName;
  Spaced := CamelCaseToSpaced(AMemberName);
  if Spaced <> AMemberName then
  begin
    Fragment := Fragment + '&text=' + Spaced.Replace(' ', '%20');
    // Range match for interleaved calls: WriteVarValue -> text=Write,Value
    // Only for methods with at least 2 parameters, as these cause gaps in the HTML cells
    if AIsMethod and (AParamCount >= 2) and Spaced.Contains(' ') then
    begin
      Parts := Spaced.Split([' ']);
      if Length(Parts) >= 2 then
        Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
    end;
  end;

  if AIsMethod and (AMemberName.Length > 3) and AMemberName.StartsWith('Set', True) then
  begin
    var PropName := AMemberName.Substring(3);
    Fragment := Fragment + '&text=' + PropName;

    var SpacedProp := CamelCaseToSpaced(PropName);
    if SpacedProp <> PropName then
    begin
      Fragment := Fragment + '&text=' + SpacedProp.Replace(' ', '%20');
      // Only for methods with at least 2 parameters, as these could potentially cause gaps
      if SpacedProp.Contains(' ') and (AParamCount >= 2) then
      begin
        Parts := SpacedProp.Split([' ']);
        if Length(Parts) >= 2 then
          Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
      end;
    end;
  end;

  Result := Format('../%s#:~:%s', [APageName, Fragment]);
end;

function TSlimDocGenerator.GenerateMemberData(AFixture: TSlimDocFixture; AMember: TSlimDocMember; AUsageMap: TUsageMap): Variant;
var
  Data          : TDocVariantData absolute Result;
  HasDescription: Boolean;
  HasUsage      : Boolean;
  LookupKey     : String;
  MemberMethod  : TSlimDocMethod absolute AMember;
  MemberProperty: TSlimDocProperty absolute AMember;
  ParamCount    : Integer;
  RowClass      : String;
  UsageLinks    : Variant;
  UsageList     : TStringList;
  UsageRowClass : String;
  UsageRowId    : String;
begin
  Result := _Obj(['Name', AMember.Name]);

  LookupKey := Format('%s.%s', [AFixture.Name, AMember.Name]).ToLower;
  HasUsage := Assigned(AUsageMap) and AUsageMap.TryGetValue(LookupKey, UsageList);
  HasDescription := AMember.Description <> '';
  UsageRowId := Format('usage-%s-%s', [AFixture.Id, AMember.Name]).Replace('.', '-');

  RowClass := '';
  if AMember.IsInherited then
    RowClass := 'inherited-member';

  if RowClass <> '' then
    Data.AddValue('RowClass', RowClass);

  ParamCount := 0;
  if AMember is TSlimDocMethod then
  begin
    ParamCount := MemberMethod.Parameters.Count;
    Data.AddValue('ParamsString', MemberMethod.GetParamsString);
    Data.AddValue('ReturnType', MemberMethod.ReturnType);
  end
  else if AMember is TSlimDocProperty then
  begin
    Data.AddValue('PropertyType', MemberProperty.PropertyType);
    Data.AddValue('Access', MemberProperty.Access);
    Data.AddValue('ReturnType', '');
  end;

  Data.AddValue('SyncMode', AMember.SyncMode);
  if SameText(AMember.SyncMode, 'smUnsynchronized') then
    Data.AddValue('SyncClass', 'unsynchronized-member');
  Data.AddValue('Origin', AMember.Origin);
  Data.AddValue('HasUsageOrDesc', HasUsage or HasDescription);
  Data.AddValue('UsageRowId', UsageRowId);

  UsageRowClass := '';
  if AMember.IsInherited then
    UsageRowClass := 'inherited-member usage-row'
  else
    UsageRowClass := 'usage-row';
  Data.AddValue('UsageRowClass', UsageRowClass);

  if HasDescription then
    Data.AddValue('DescriptionHtml', FormatXmlComment(AMember.Description))
  else
    Data.AddValue('DescriptionHtml', false);

  Data.AddValue('HasUsage', HasUsage);
  if HasUsage then
  begin
    UsageLinks := _Arr([]);
    for var U: String in UsageList do
      UsageLinks.Add(_Obj([
        'Link', BuildLink(U, AMember.Name, AMember is TSlimDocMethod, ParamCount),
        'PageName', U]));
    Data.AddValue('UsageLinks', UsageLinks);
  end;
end;

function TSlimDocGenerator.Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const ATemplateContent, AOutputFilePath: String): String;
var
  Doc        : Variant;
  Fixture    : Variant;
  FixtureData: TDocVariantData absolute Fixture;
  FixturesArr: Variant;
  Method     : TSlimDocMethod;
  MethodsArr : Variant;
  Prop       : TSlimDocProperty;
  PropsArr   : Variant;
begin
  SortFixtures(AFixtures);
  FixturesArr := _Arr([]);

  for var LoopFixture: TSlimDocFixture in AFixtures do
  begin
    Fixture := _Obj([
      'Id', LoopFixture.Id,
      'Name', LoopFixture.Name,
      'Namespace', LoopFixture.Namespace,
      'UnitName', LoopFixture.UnitName]);

    var ClassDecl := LoopFixture.DelphiClass;
    if (LoopFixture.InheritanceChain.Count > 0) then
    begin
      ClassDecl := ClassDecl + ' &lt; ' + LoopFixture.InheritanceChain[0];
      for var I := 1 to LoopFixture.InheritanceChain.Count - 1 do
        ClassDecl := ClassDecl + ' &lt; ' + LoopFixture.InheritanceChain[I];
    end;
    FixtureData.AddValue('DelphiClass', ClassDecl);

    if LoopFixture.Description <> '' then
      FixtureData.AddValue('DescriptionHtml', FormatXmlComment(LoopFixture.Description))
    else
      FixtureData.AddValue('DescriptionHtml', false);

    FixtureData.AddValue('HasInherited', HasInheritedMembers(LoopFixture));

    // Methods
    MethodsArr := _Arr([]);
    SortMembers(TList<TSlimDocMember>(LoopFixture.Methods));
    for Method in LoopFixture.Methods do
      MethodsArr.Add(GenerateMemberData(LoopFixture, Method, AUsageMap));
    FixtureData.AddValue('Methods', MethodsArr);

    // Properties
    if LoopFixture.Properties.Count > 0 then
    begin
      FixtureData.AddValue('HasProperties', True);
      PropsArr := _Arr([]);
      SortMembers(TList<TSlimDocMember>(LoopFixture.Properties));
      for Prop in LoopFixture.Properties do
        PropsArr.Add(GenerateMemberData(LoopFixture, Prop, AUsageMap));
      FixtureData.AddValue('Properties', PropsArr);
    end;

    FixturesArr.Add(Fixture);
  end;

  Doc := _Obj(['Fixtures', FixturesArr]);
  var Rendered: UTF8String := TSynMustache.Parse(RawUtf8(ATemplateContent)).Render(Doc);
  TFile.WriteAllText(AOutputFilePath, String(Rendered), TEncoding.UTF8);

  var LinkName: String := ExtractFileName(AOutputFilePath);
  Result := Format('<a href="files/%s" target="_blank">Open Documentation</a>', [LinkName]);
end;

end.
