// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
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
  mormot.core.mustache,
  mormot.core.variants,

  Slim.Doc.Model,
  Slim.Doc.Utils,
  Slim.Doc.UsageAnalyzer;

type

  TSlimDocGenerator = class
  private
    function  BuildLink(const PageName, MemberName: String; IsMethod: Boolean): String;
    function  FormatXmlComment(const AXml: String): String;
    function  GenerateMemberData(Fixture: TSlimDocFixture; Member: TSlimDocMember; AUsageMap: TUsageMap): TDocVariantData;
    procedure SortFixtures(AFixtures: TList<TSlimDocFixture>);
    procedure SortMembers(AList: TList<TSlimDocMember>);
  public
    function Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const ATemplateContent, AOutputFilePath: String): String;
  end;

implementation

{ TSlimDocGenerator }

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

function TSlimDocGenerator.BuildLink(const PageName, MemberName: String; IsMethod: Boolean): String;
var
  Fragment: String;
  Parts   : TArray<String>;
  Spaced  : String;
begin
  Fragment := 'text=' + MemberName;
  Spaced := CamelCaseToSpaced(MemberName);
  if Spaced <> MemberName then
  begin
    Fragment := Fragment + '&text=' + Spaced.Replace(' ', '%20');
    // Range match for interleaved calls: WriteVarValue -> text=Write,Value
    // Only for methods, to match reference HTML
    if IsMethod and Spaced.Contains(' ') then
    begin
      Parts := Spaced.Split([' ']);
      if Length(Parts) >= 2 then
        Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
    end;
  end;

  if IsMethod and (MemberName.Length > 3) and MemberName.StartsWith('Set', True) then
  begin
    var PropName := MemberName.Substring(3);
    Fragment := Fragment + '&text=' + PropName;

    var SpacedProp := CamelCaseToSpaced(PropName);
    if SpacedProp <> PropName then
    begin
      Fragment := Fragment + '&text=' + SpacedProp.Replace(' ', '%20');
      if SpacedProp.Contains(' ') then
      begin
        Parts := SpacedProp.Split([' ']);
        if Length(Parts) >= 2 then
          Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
      end;
    end;
  end;

  Result := Format('../%s#:~:%s', [PageName, Fragment]);
end;

function TSlimDocGenerator.GenerateMemberData(Fixture: TSlimDocFixture; Member: TSlimDocMember; AUsageMap: TUsageMap): TDocVariantData;
var
  HasDescription: Boolean;
  HasUsage      : Boolean;
  LinkObj       : TDocVariantData;
  LookupKey     : String;
  RowClass      : String;
  SyncStyle     : String;
  U             : String;
  UsageLinksArr : TDocVariantData;
  UsageList     : TStringList;
  UsageRowClass : String;
  UsageRowId    : String;
begin
  Result.InitJson('{}', []);

  LookupKey := Format('%s.%s', [Fixture.Name, Member.Name]).ToLower;
  HasUsage := Assigned(AUsageMap) and AUsageMap.TryGetValue(LookupKey, UsageList);
  HasDescription := Member.Description <> '';
  UsageRowId := Format('usage-%s-%s', [Fixture.Id, Member.Name]).Replace('.', '-');

  RowClass := '';
  if Member.IsInherited then RowClass := 'inherited-member';

  SyncStyle := '';
  if SameText(Member.SyncMode, 'smUnsynchronized') then
    SyncStyle := 'color:#888'; // Added to style attribute in template

  Result.AddValue('Name', Member.Name);
  if RowClass <> '' then Result.AddValue('RowClass', RowClass);

  if Member is TSlimDocMethod then
     Result.AddValue('ReturnType', TSlimDocMethod(Member).ReturnType)
  else
     Result.AddValue('ReturnType', ''); // Empty for properties

  if Member is TSlimDocMethod then
     Result.AddValue('ParamsString', TSlimDocMethod(Member).GetParamsString)
  else if Member is TSlimDocProperty then
     Result.AddValue('PropertyType', TSlimDocProperty(Member).PropertyType);

  if Member is TSlimDocProperty then
     Result.AddValue('Access', TSlimDocProperty(Member).Access);

  Result.AddValue('SyncMode', Member.SyncMode);
  if SyncStyle <> '' then Result.AddValue('SyncStyle', SyncStyle);
  Result.AddValue('Origin', Member.Origin);
  Result.AddValue('HasUsageOrDesc', HasUsage or HasDescription);
  Result.AddValue('UsageRowId', UsageRowId);

  UsageRowClass := '';
  if Member.IsInherited then UsageRowClass := 'inherited-member usage-row'
  else UsageRowClass := 'usage-row';
  Result.AddValue('UsageRowClass', UsageRowClass);

  if HasDescription then
    Result.AddValue('DescriptionHtml', FormatXmlComment(Member.Description))
  else
    Result.AddValue('DescriptionHtml', '');

  Result.AddValue('HasUsage', HasUsage);

  if HasUsage then
  begin
    UsageLinksArr.InitJson('[]', []);
    for U in UsageList do
    begin
      LinkObj.InitJson('{}', []);
      LinkObj.AddValue('Link', BuildLink(U, Member.Name, Member is TSlimDocMethod));
      LinkObj.AddValue('PageName', U);
      UsageLinksArr.AddItem(Variant(LinkObj));
    end;
    Result.AddValue('UsageLinks', Variant(UsageLinksArr));
  end;
end;

function TSlimDocGenerator.Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const ATemplateContent, AOutputFilePath: String): String;
var
  Doc            : TDocVariantData;
  Fixture        : TSlimDocFixture;
  FixtureObj     : TDocVariantData;
  FixturesArr    : TDocVariantData;
  Method         : TSlimDocMethod;
  MethodsArr     : TDocVariantData;
  Prop           : TSlimDocProperty;
  PropsArr       : TDocVariantData;
begin
  SortFixtures(AFixtures);

  Doc.InitJson('{}', []);
  FixturesArr.InitJson('[]', []);

  for Fixture in AFixtures do
  begin
    FixtureObj.InitJson('{}', []);
    FixtureObj.AddValue('Id', Fixture.Id);
    FixtureObj.AddValue('Name', Fixture.Name);
    FixtureObj.AddValue('Namespace', Fixture.Namespace);
    FixtureObj.AddValue('UnitName', Fixture.UnitName);

    var ClassDecl := Fixture.DelphiClass;
    if (Fixture.InheritanceChain.Count > 0) then
    begin
      ClassDecl := ClassDecl + ' &lt; ' + Fixture.InheritanceChain[0];
      for var I := 1 to Fixture.InheritanceChain.Count - 1 do
        ClassDecl := ClassDecl + ' &lt; ' + Fixture.InheritanceChain[I];
    end;
    FixtureObj.AddValue('DelphiClass', ClassDecl);

    if Fixture.Description <> '' then
      FixtureObj.AddValue('DescriptionHtml', FormatXmlComment(Fixture.Description));

    var HasInherited := False;
    for Method in Fixture.Methods do
      if Method.IsInherited then begin HasInherited := True; Break; end;
    if not HasInherited then
      for Prop in Fixture.Properties do
        if Prop.IsInherited then begin HasInherited := True; Break; end;
    FixtureObj.AddValue('HasInherited', HasInherited);

    // Methods
    MethodsArr.InitJson('[]', []);
    SortMembers(TList<TSlimDocMember>(Fixture.Methods));
    for Method in Fixture.Methods do
      MethodsArr.AddItem(Variant(GenerateMemberData(Fixture, Method, AUsageMap)));
    FixtureObj.AddValue('Methods', Variant(MethodsArr));

    // Properties
    if Fixture.Properties.Count > 0 then
    begin
      FixtureObj.AddValue('HasProperties', True);
      PropsArr.InitJson('[]', []);
      SortMembers(TList<TSlimDocMember>(Fixture.Properties));
      for Prop in Fixture.Properties do
        PropsArr.AddItem(Variant(GenerateMemberData(Fixture, Prop, AUsageMap)));
      FixtureObj.AddValue('Properties', Variant(PropsArr));
    end;

    FixturesArr.AddItem(Variant(FixtureObj));
  end;

  Doc.AddValue('Fixtures', Variant(FixturesArr));

  var Rendered := TSynMustache.Parse(RawUtf8(ATemplateContent)).Render(Variant(Doc));
  TFile.WriteAllText(AOutputFilePath, string(Rendered), TEncoding.UTF8);

  var LinkName := ExtractFileName(AOutputFilePath);
  Result := Format('<a href="files/%s" target="_blank">Open Documentation</a>', [LinkName]);
end;

end.
