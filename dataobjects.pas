unit DataObjects;

{$MODE DELPHI}
{$CODEPAGE UTF8}

interface

uses
  SysUtils,
  Generics.Collections, // Во Free Pascal этот модуль доступен в режиме {$MODE DELPHI}
  httpDefs,
  fpjson;               // Нужен для генерации JSON-объектов

type

  { TDeviceInfo }

  TDeviceInfo = class(TObject)
  private
    FName: string;    // Unique Device ID
    FVendor: string;  // Manufacturer
    FModel: string;   // Name
    FType: string;    // Type
    function GetUrlEncodedID: string;
  public
    constructor Create(const AName, AVendor, AModel, AType: string);

    function Equals(Obj: TObject): Boolean; override;
    function ToString: string; override;


    function ToJSONObject: TJSONObject;

    property Name: string read FName;
    property Vendor: string read FVendor;
    property Model: string read FModel;
    property AType: string read FType;
    property DeviceID: string read GetUrlEncodedID;
  end;

  TDeviceInfoList = TObjectList<TDeviceInfo>;

  TUnit = (UnitNone=0, UnitPixel, UnitBit, UnitMm, UnitDpi, UnitPercent, UnitUsec);

const
    UnitNames: array [TUnit] of String = (
      'UNIT_NONE',
      'UNIT_PIXEL',
      'UNIT_BIT',
      'UNIT_MM',
      'UNIT_DPI',
      'UNIT_PERCENT',
      'UNIT_MICROSECOND');

type
  TIntArray = array of Integer;

implementation

{ TDeviceInfo }

function TDeviceInfo.GetUrlEncodedID: string;
begin
  Result := HTTPEncode(FName);
end;

constructor TDeviceInfo.Create(const AName, AVendor, AModel, AType: string);
begin
  inherited Create;
  FName := AName;
  FVendor := AVendor;
  FModel := AModel;
  FType := AType;
end;

function TDeviceInfo.Equals(Obj: TObject): Boolean;
var
  Other: TDeviceInfo;
begin
  if not(Obj is TDeviceInfo) then
    Exit(False);

  Other := TDeviceInfo(Obj);
  Result := (FName = Other.FName);
end;

function TDeviceInfo.ToString: string;
begin
  Result := Format('%s: %s @ %s', [ClassName, FModel, FName]);
end;

{ Превращает объект сканера в TJSONObject.
  При добавлении в TJSONArray памятью будет управлять массив. }
function TDeviceInfo.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', FName);
  Result.Add('vendor', Vendor);
  Result.Add('model', Model);
  Result.Add('type', AType);
  Result.Add('deviceID', DeviceID);
end;


end.

