unit Helpers;

{$MODE DELPHI}{$H+}
{$CODEPAGE UTF8}

interface

uses
  Windows,
  SysUtils,
  Classes,
  Variants,
  ComObj,
  fpjson,        // Вместо System.Json используем нативный FPC JSON
  DataObjects,
  WIADefs,
  WIA_TLB;

function DevTypeName(type_: WiaDeviceType): String;
function StrToJsonValue(str: string): string;
function GetPropStrValue(DevInfo: IDeviceInfo; const name: string): string;


procedure EnumScanners(DevInfoList: TDeviceInfoList);
function Connect(const Name: string): IDevice;
procedure PropsToStrings(props: IProperties; lines: TStrings; extent: Integer=0);

type
  // Для FPC 3.2.2 мы сохраняем синтаксис, но помним, что при передаче
  // процедур их нужно будет явно кастить к этим типам
  TPropFunc = procedure(prop: IProperty);
  TImageFunc = procedure(img: TBytes);

procedure Scan(device: IDevice; propFunc: TPropFunc; imageFunc: TImageFunc);

implementation

function StrToJsonValue(str: string): string;
var
  val: TJSONString;
begin
  // Нативная реализация fpjson во Free Pascal
  val := TJSONString.Create(str);
  try
    Result := val.AsJSON;
  finally
    val.Free;
  end;
end;

function GetPropStrValue(DevInfo: IDeviceInfo; const name: string): string;
var
  prop: IProperty;
  val: OleVariant;
begin
  Result := '';
  prop := DevInfo.Properties.Get_Item(name);
  try
    if assigned(prop) then
    begin
      val := prop.Get_Value;
      if not VarIsNull(val) then
        Result := VarToStr(val);
    end;
  finally
    prop := nil;
  end;
end;

function PropValuesToString(prop: IProperty): string;
var
  vecStr: TStringBuilder;
  values: IVector;
  StrValue: string;
  i: Integer;
  IdxVar: OleVariant;
begin
  vecStr := TStringBuilder.Create;
  try
    values := prop.SubTypeValues;
    for i := 1 to values.Count do
    begin
      if i > 1 then
        vecStr.Append(', ');

      IdxVar := i;
      StrValue := VarToStr(values.Get_Item(IdxVar));
      if (prop.type_ = StringPropertyType) or
         (prop.type_ = ClassIDPropertyType) or
         (prop.type_ = DatePropertyType) then
        StrValue := StrToJsonValue(StrValue);
      vecStr.Append(StrValue);
    end;
    Result := vecStr.ToString;
  finally
    vecStr.Free;
  end;
end;

procedure PropsToStrings(props: IProperties; lines: TStrings; extent: Integer=0);
var
  offset: string;
  i: Integer;
  prop: IProperty;
  propStr: string;
  proptype: integer;
  typeName: string;
  subType: WiaSubType;
  ro: string;
begin
  offset := StringOfChar(' ', extent) + '- ';
  for i := 1 to props.Count do
  begin

    prop := props[i];
    ro := 'false';
    if prop.IsReadOnly then
      ro := 'true';
    propStr := offset + '{name: ' + prop.Name + ',  id: ' +
      IntToStr(prop.PropertyID) + ', ro: ' + ro;

    propType := prop.type_;
    if propType <> 0 then
    begin
      if (propType = StringPropertyType) or
         (propType = ClassIDPropertyType) or
         (propType = DatePropertyType) then
        propStr := propStr + ', value: '+ StrToJsonValue(VarToStr(prop.Get_Value))
      else
        propStr := propStr + ', value: '+ VarToStr(prop.Get_Value);
    end;

    case propType of
      UnsupportedPropertyType: typeName := 'unsupported';
      BooleanPropertyType: typeName := 'bool';
      BytePropertyType: typeName := 'byte';
      IntegerPropertyType: typeName := 'int';
      UnsignedIntegerPropertyType: typeName := 'uint';
      LongPropertyType: typeName := 'long';
      UnsignedLongPropertyType: typeName := 'ulong';
      ErrorCodePropertyType: typeName := 'errorCode';
      LargeIntegerPropertyType: typeName := 'largeint';
      UnsignedLargeIntegerPropertyType: typeName := 'ulargeint';
      SinglePropertyType: typeName := 'single';
      DoublePropertyType: typeName := 'double';
      CurrencyPropertyType: typeName := 'curr';
      DatePropertyType: typeName := 'date';
      FileTimePropertyType: typeName := 'filetime';
      ClassIDPropertyType: typeName := 'classid';
      StringPropertyType: typeName := 'string';
      ObjectPropertyType: typeName := 'object';
      HandlePropertyType: typeName := 'handle';
      VariantPropertyType: typeName := 'variant';
      else
        typeName := IntToHex(propType);
    end;
    propStr := propStr + ', type: ' + typeName;
    try
      subType := prop.SubType;
    except
      on EOleException do
        subType := 0;
    end;
    if subType = RangeSubType then
       propStr := propStr + Format(', range: {min: %d, max: %d, step: %d}',
         [prop.SubTypeMin, prop.SubTypeMax, prop.SubTypeStep]);

    if subType in [ListSubType, FlagSubType] then
    begin
      propStr := propStr + ', values: [' + PropValuesToString(prop) + ']';
    end;

    if subType = FlagSubType then
      propStr := propStr + ', flag: true';
    propStr := propStr + '}';
    lines.Add(propStr);
  end;
end;

procedure Scan(device: IDevice; propFunc: TPropFunc; imageFunc: TImageFunc);
var
  itm: IItem;
  props: IProperties;
  prop: IProperty;
  i: Integer;
  v: OleVariant;
  img: IImageFile;
begin
  props := device.Properties;
  for i := 1 to props.Count do
  begin
    prop := props[i];
    if prop.PropertyID = WIA_DPS_DOCUMENT_HANDLING_SELECT then
      prop.Set_Value(FEEDER);
    propFunc(prop);
  end;


  itm := device.Items[1];
  props := itm.Properties;
  for i := 1 to props.Count do
  begin
    prop := props[i];
    propFunc(prop);
  end;

  // Сканирование до упора
  while True do
  begin
    v := Unassigned;
    v := itm.Transfer(GUIDToString(WiaImgFmt_BMP));
    img := IDispatch(v) as IImageFile;
    // Логика обработки img...
  end;
end;

function DevTypeName(type_: WiaDeviceType): String;
begin
  case type_ of
    0: Result := 'Unspecified';
    1: Result := 'Scanner';
    2: Result := 'Camera';
    3: Result := 'Video';
  else
    Result := 'Unknown ' + IntToStr(type_);
  end;
end;

procedure EnumScanners(DevInfoList: TDeviceInfoList);
var
  DevMgr: IDeviceManager;
  cnt: Integer;
  i: Integer;
  DevInfo: IDeviceInfo;
  device: TDeviceInfo;
  AName, AVendor, AModel, AType: string;
  j: Integer;
  prop: IProperty;
begin
  DevInfoList.Clear;
  // Во Free Pascal надежнее использовать CoDeviceManager.Create из WIA_TLB,
  // но оставляем CreateComObject для совместимости, приведя к интерфейсу
  DevMgr := CreateComObject(CLASS_DeviceManager) as IDeviceManager;
  cnt := DevMgr.DeviceInfos.Count;

  for i := 1 to cnt do
  begin
    DevInfo := DevMgr.DeviceInfos[i];
    if DevInfo.type_ <> ScannerDeviceType then
      continue;

    AType := DevTypeName(DevInfo.type_);
    AName := DevInfo.DeviceID;

    AVendor := '';
    AModel := '';
    for j := 1 to DevInfo.Properties.Count do
    begin
      prop := DevInfo.Properties[j];
      case prop.PropertyID of
        WIA_DIP_DEV_NAME:
          AModel := VarToStr(prop.Get_Value);
        WIA_DIP_VEND_DESC:
          AVendor := VarToStr(prop.Get_Value);
      end;
    end;

    device := TDeviceInfo.Create(AName, AVendor, AModel, AType);
    DevInfoList.Add(device);
  end;
end;

function Connect(const Name: string): IDevice;
var
  DevMgr: IDeviceManager;
  i: Integer;
  DevInfo: IDeviceInfo;
begin
  DevMgr := CreateComObject(CLASS_DeviceManager) as IDeviceManager;
  for i := 1 to DevMgr.DeviceInfos.Count do
  begin
    DevInfo := DevMgr.DeviceInfos[i];
    if DevInfo.DeviceID = Name then
    begin
      Result := DevInfo.Connect;
      Exit;
    end;
  end;

  raise EConvertError.CreateFmt('Сканер %s не найден', [Name]);
end;

end.

