unit options;

{$MODE DELPHI}
{$CODEPAGE UTF8}

interface

uses
  SysUtils,
  Variants,
  ActiveX,
  Generics.Collections,
  fpjson,
  WIA_TLB,
  WIAdefs,
  DataObjects;

type
  { Базовый класс для любой опции WIA }
  TBaseOption = class(TObject)
  private
    FName: string;
    FPropID: Integer;
    FTitle: string;
    FDesc: string;
    FType: string;
    FUnit: string;
    FIsReadOnly: Boolean;
    FCurrentValue: OleVariant; // Изменено на OleVariant
  public
    constructor Create(const AName: string; APropID: Integer; const ATitle, ADesc, AType: string; AUnit: TUnit; AReadOnly: Boolean; const ACurrent: OleVariant);
    constructor CreateFromWia(AProp: IProperty; AUnit: TUnit; const ATypeStr: string); virtual;
    function ToJSONObject: TJSONObject; virtual;

    property Name: string read FName;
    property PropID: Integer read FPropID;
    property Value: OleVariant read FCurrentValue;
  end;

  { Опция-Диапазон (например: DPI, Яркость) }
  TRangeOption = class(TBaseOption)
  private
    FMin: Integer;
    FMax: Integer;
    FStep: Integer;
  public
    constructor CreateFromWia(AProp: IProperty; AUnit: TUnit; const ATypeStr: string); override;
    function ToJSONObject: TJSONObject; override;
  end;

  { Опция-Список (например: Режимы цвета) }
  TListOption = class(TBaseOption)
  private
    FValues: TJSONArray;
  public
    constructor Create(const AName: string; APropID: Integer; const ATitle, ADesc: string; AUnit: TUnit; AReadOnly: Boolean; const ACurrent: OleVariant);
    destructor Destroy; override;
    constructor CreateFromWia(AProp: IProperty; AUnit: TUnit; const ATypeStr: string); override;
    procedure AddValue(const AValue: string);
    function ToJSONObject: TJSONObject; override;
  end;

  TBaseOptionList = TObjectList<TBaseOption>;

implementation


{ TBaseOption }

constructor TBaseOption.Create(const AName: string; APropID: Integer; const ATitle, ADesc, AType: string; AUnit: TUnit; AReadOnly: Boolean; const ACurrent: OleVariant);
begin
  inherited Create;
  FName := AName;
  FPropID := APropID;
  FTitle := ATitle;
  FDesc := ADesc;
  FType := AType;
  FUnit := UnitNames[AUnit];
  FIsReadOnly := AReadOnly;
  FCurrentValue := ACurrent; // Прямое присвоение
end;

constructor TBaseOption.CreateFromWia(AProp: IProperty; AUnit: TUnit; const ATypeStr: string);
begin
  Create(AProp.Name, AProp.PropertyID, AProp.Name, AProp.Name, ATypeStr, AUnit, AProp.IsReadOnly, AProp.Get_Value);
end;

function TBaseOption.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', FName);
  Result.Add('id', FPropID);
  Result.Add('title', FTitle);
  Result.Add('desc', FDesc);
  Result.Add('type', FType);
  Result.Add('unit', FUnit);
  Result.Add('readonly', FIsReadOnly);

  // Явный разбор типа OleVariant для устранения конфликта перегрузок Add()
    case TVarData(FCurrentValue).VType of
      varEmpty, varNull:
        Result.Add('value', '');

      varSmallint, varInteger, varShortInt, varByte:
        Result.Add('value', Integer(FCurrentValue));

      varInt64:
        Result.Add('value', Int64(FCurrentValue));

      varSingle, varDouble, varCurrency:
        Result.Add('value', Double(FCurrentValue));

      varBoolean:
        Result.Add('value', Boolean(FCurrentValue));
    else
      // Для строк (varOleStr, varString) и всех остальных типов
      Result.Add('value', VarToStr(FCurrentValue));
    end;
  Result.Add('kind', 'basic');
end;

{ TRangeOption }

constructor TRangeOption.CreateFromWia(AProp: IProperty; AUnit: TUnit; const ATypeStr: string);
begin
  inherited CreateFromWia(AProp, AUnit, ATypeStr);
  FMin := AProp.SubTypeMin;
  FMax := AProp.SubTypeMax;
  FStep := AProp.SubTypeStep;
end;

function TRangeOption.ToJSONObject: TJSONObject;
begin
  Result := inherited ToJSONObject;
  Result.Strings['kind'] := 'range';
  Result.Add('min', FMin);
  Result.Add('max', FMax);
  Result.Add('step', FStep);
end;

{ TListOption }

constructor TListOption.Create(const AName: string; APropID: Integer; const ATitle, ADesc: string; AUnit: TUnit; AReadOnly: Boolean; const ACurrent: OleVariant);
begin
  inherited Create(AName, APropID, ATitle, ADesc, 'list', AUnit, AReadOnly, ACurrent);
  FValues := TJSONArray.Create;
end;

destructor TListOption.Destroy;
begin
  FValues.Free;
  inherited;
end;

constructor TListOption.CreateFromWia(AProp: IProperty; AUnit: TUnit; const ATypeStr: string);
var
  WiaVector: IVector;
  J: Integer;
  IdxVar: OleVariant;
  RawVal: string;
begin
  inherited CreateFromWia(AProp, AUnit, 'list');
  FValues := TJSONArray.Create;

  try
    WiaVector := AProp.SubTypeValues;
    if (WiaVector <> nil) and (WiaVector.Count > 0) then
    begin
      for J := 1 to WiaVector.Count do
      begin
        IdxVar := J;
        RawVal := VarToStr(WiaVector.Get_Item(IdxVar));

        // Мапим числа вектора в красивые имена
        if AProp.PropertyID = WIA_IPS_CUR_INTENT then
        begin
          if RawVal = '0' then FValues.Add('color')
          else if RawVal = '1' then FValues.Add('grayscale')
          else if RawVal = '2' then FValues.Add('monochrome')
          else if RawVal = '4' then FValues.Add('auto')
          else FValues.Add(RawVal);
        end
        else
          FValues.Add(RawVal);
      end;
    end;
  except
    WiaVector := nil;
  end;

  if (FValues.Count = 0) and (AProp.PropertyID = WIA_IPS_CUR_INTENT) then
  begin
    FValues.Add('color');
    FValues.Add('grayscale');
    FValues.Add('monochrome');
    FValues.Add('auto');
  end;

  WiaVector := nil;
end;

procedure TListOption.AddValue(const AValue: string);
begin
  FValues.Add(AValue);
end;

function TListOption.ToJSONObject: TJSONObject;
begin
  Result := inherited ToJSONObject;
  Result.Strings['kind'] := 'list';

  // Перебиваем "value" на человекочитаемую строку, если это режим цвета
  if FPropID = WIA_IPS_CUR_INTENT then
  begin
    Result.Delete('value'); // Удаляем числовой Variant
    if FCurrentValue = 0 then Result.Add('value', 'color')
    else if FCurrentValue = 1 then Result.Add('value', 'grayscale')
    else if FCurrentValue = 2 then Result.Add('value', 'monochrome')
    else if FCurrentValue = 4 then Result.Add('value', 'auto')
    else Result.Add('value', VarToStr(FCurrentValue));
  end;

  Result.Add('values', FValues.Clone);
end;

end.

