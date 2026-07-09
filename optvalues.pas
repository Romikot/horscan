unit optvalues;

{$mode Delphi}

interface

uses
  Classes,
  SysUtils,
  Variants,
  ActiveX,
  Generics.Collections,
  fpjson,
  WIA_TLB,
  WIAdefs,
  DataObjects;

type
  TWiaValue = class(TObject)
  private
    FPropID: Integer;
    FValue: OleVariant;
  public
    constructor Create(APropID: Integer; const AValue: OleVariant);

    procedure Apply(ADevice: IDevice); virtual;

    property PropID: Integer read FPropID;
    property Value: OleVariant read FValue;
  end;

  TWiaValueClass = class of TWiaValue;

  TWiaValueList = TObjectList<TWiaValue>;

  { TWiaValueFactory — Выделенная фабрика для маппинга имен URL Query в ID констант WIA }
  TWiaValueFactory = class
  private
    class var FRegistry: TDictionary<Integer, TWiaValueClass>;
    class var FNameToIDRegistry: TDictionary<string, Integer>; // Словарь для маппинга имен
  public
    class constructor CreateFactory;
    class destructor DestroyFactory;

    // Фабричный метод: принимает имя свойства из URL ('Brightness') и строковое значение ('0')
    class function CreateValue(const APropName: string; const AValue: string): TWiaValue;
  end;

  { TSourceVirtualValue — Специализированный наследник для виртуального лотка }
  TSourceVirtualValue = class(TWiaValue)
  public
    procedure Apply(ADevice: IDevice); override;
  end;

implementation

{ TWiaValue }

constructor TWiaValue.Create(APropID: Integer; const AValue: OleVariant);
begin
  inherited Create;
  FPropID := APropID;
  FValue := AValue;
end;

procedure TWiaValue.Apply(ADevice: IDevice);
var
  Items: IItems;
  Item: IItem;
  Props: IProperties;
  Prop: IProperty;
  I: Integer;
  Found: Boolean;
begin
  if ADevice = nil then
    raise Exception.Create('Интерфейс IDevice не инициализирован.');

  // Получаем дочернюю матрицу сканирования (Item 1) прямо из устройства
  Items := ADevice.Get_Items;
  Item := Items.Get_Item(1);
  if Item = nil then
    raise Exception.Create('Не удалось получить дочерний элемент матрицы сканера.');

  Props := Item.Properties;
  Found := False;

  for I := 1 to Props.Count do
  begin
    Prop := Props[I];
    if Prop.PropertyID = FPropID then
    begin
      Found := True;
      if Prop.IsReadOnly then
        raise Exception.CreateFmt('Свойство "%s" (ID: %d) доступно только для чтения.', [Prop.Name, FPropID]);

      try
        // Обратная трансляция красивых строковых имён режима цвета в системные OLE константы из WIAdefs
        if FPropID = WIA_IPS_CUR_INTENT then
        begin
          if FValue = 'color' then Prop.Set_Value(OleVariant(WIA_DATA_COLOR))
          else if FValue = 'grayscale' then Prop.Set_Value(OleVariant(WIA_DATA_GRAYSCALE))
          else if FValue = 'monochrome' then Prop.Set_Value(OleVariant(WIA_DATA_THRESHOLD))
          else if FValue = 'auto' then Prop.Set_Value(OleVariant(4))
          else Prop.Set_Value(OleVariant(StrToIntDef(VarToStr(FValue), WIA_DATA_COLOR)));
        end
        else
        begin
          // Все остальные числовые свойства (DPI, Яркость, Контраст) переводим в Integer
          if VarIsNumeric(FValue) then
            Prop.Set_Value(FValue)
          else
            Prop.Set_Value(OleVariant(StrToInt(VarToStr(FValue))));
        end;
      except
        on E: Exception do
          raise Exception.CreateFmt('Драйвер сканера отклонил значение для свойства "%s": %s', [Prop.Name, E.Message]);
      end;
      Break;
    end;
  end;

  // Очищаем локальные COM-интерфейсы
  Prop := nil; Props := nil; Item := nil; Items := nil;

  if not Found then
    raise Exception.CreateFmt('Свойство с ID %d не поддерживается этим элементом сканера.', [FPropID]);
end;

{ TWiaValueFactory }

class constructor TWiaValueFactory.CreateFactory;
begin
  TWiaValueFactory.FRegistry := TDictionary<Integer, TWiaValueClass>.Create;
  // Создаем регистр имен без учета регистра символов (OrdinalIgnoreCase)
  TWiaValueFactory.FNameToIDRegistry := TDictionary<string, Integer>.Create;

  // ИСПОЛЬЗУЕМ СТРОКОВЫЕ КОНСТАНТЫ ИЗ WIADEFS ДЛЯ МАППИНГА ИМЕН URL
  TWiaValueFactory.FNameToIDRegistry.Add(WIA_IPS_XRES_STR, WIA_IPS_XRES);                 // 'Horizontal Resolution'
  TWiaValueFactory.FNameToIDRegistry.Add(WIA_IPS_YRES_STR, WIA_IPS_YRES);                 // 'Vertical Resolution'
  TWiaValueFactory.FNameToIDRegistry.Add(WIA_IPS_CUR_INTENT_STR, WIA_IPS_CUR_INTENT);     // 'Current Intent'
  TWiaValueFactory.FNameToIDRegistry.Add(WIA_IPS_BRIGHTNESS_STR, WIA_IPS_BRIGHTNESS);     // 'Brightness'
  TWiaValueFactory.FNameToIDRegistry.Add(WIA_IPS_CONTRAST_STR, WIA_IPS_CONTRAST);         // 'Contrast'

  // Добавляем виртуальную опцию 'source', сопоставляя её с константой лотка
  TWiaValueFactory.FNameToIDRegistry.Add('source', WIA_DPS_DOCUMENT_HANDLING_SELECT);

  // Регистрируем кастомные классы-команды по их системным ID.
  TWiaValueFactory.FRegistry.Add(WIA_DPS_DOCUMENT_HANDLING_SELECT, TSourceVirtualValue);
end;

class destructor TWiaValueFactory.DestroyFactory;
begin
  TWiaValueFactory.FRegistry.Free;
  TWiaValueFactory.FNameToIDRegistry.Free;
end;

class function TWiaValueFactory.CreateValue(const APropName: string; const AValue: string): TWiaValue;
var
  TargetPropID: Integer;
  MetaClass: TWiaValueClass;
begin
  // Ищем числовой ID свойства WIA по его текстовому имени из Query-строки URL
  if not TWiaValueFactory.FNameToIDRegistry.TryGetValue(APropName, TargetPropID) then
    raise Exception.CreateFmt('Параметр "%s" не поддерживается сканером.', [APropName]);

  // Проверяем, зарегистрирован ли особый класс-команда под этот ID (например, TSourceVirtualValue)
  if TWiaValueFactory.FRegistry.TryGetValue(TargetPropID, MetaClass) then
  begin
    Result := MetaClass.Create(TargetPropID, OleVariant(AValue));
  end
  else
  begin
    Result := TWiaValue.Create(TargetPropID, OleVariant(AValue));
  end;
end;

{ TSourceVirtualValue }

procedure TSourceVirtualValue.Apply(ADevice: IDevice);
var
  Props: IProperties;
  Prop: IProperty;
  I: Integer;
  Found: Boolean;
  StrVal: string;
  NumericValue: Integer;
begin
  if ADevice = nil then
    raise Exception.Create('Интерфейс IDevice не инициализирован.');

  // ИСПРАВЛЕНО: Виртуальная опция работает со свойствами КОРНЕВОГО устройства (ADevice), а не матрицы!
  Props := ADevice.Properties;
  Found := False;

  // Переводим строковые команды фронтенда в системные константы WIAdefs (FEEDER, FLATBED, DUPLEX)
  StrVal := LowerCase(Trim(VarToStr(FValue)));
  if StrVal = 'feeder' then NumericValue := FEEDER
  else if StrVal = 'flatbed' then NumericValue := FLATBED
  else if StrVal = 'duplex' then NumericValue := DUPLEX
  else NumericValue := StrToIntDef(StrVal, FLATBED);

  for I := 1 to Props.Count do
  begin
    Prop := Props[I];
    if Prop.PropertyID = FPropID then
    begin
      Found := True;
      if Prop.IsReadOnly then
        raise Exception.CreateFmt('Свойство устройства "%s" доступно только для чтения.', [Prop.Name]);

      try
        Prop.Set_Value(OleVariant(NumericValue));
      except
        on E: Exception do
          raise Exception.CreateFmt('Драйвер сканера отклонил выбор лотка "%s": %s', [StrVal, E.Message]);
      end;
      Break;
    end;
  end;

  // Очищаем локальные COM-интерфейсы
  Prop := nil; Props := nil;

  if not Found then
    raise Exception.Create('Выбор источника бумаги (автоподатчик) не поддерживается этим устройством.');
end;

end.

