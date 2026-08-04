unit Services.WiaScanner;

{$MODE DELPHI}
{$CODEPAGE UTF8}

interface

uses
  SysUtils,
  Variants,
  ActiveX,
  Classes,
  WIA_TLB,
  WIAdefs,
  DataObjects,
  Helpers,
  options,
  optvalues,
  Horse, // Подключаем Horse для типа THorseRequest
  // Нативные графические модули Free Pascal (работают в консоли без LCL/VCL)
  FPImage,
  FPReadBMP,
  FPWriteJPEG;



{ Заполняет переданный список доступными сканерами в системе }
procedure GetAvailableWiaScanners(AList: TDeviceInfoList);

{ Заполняет переданный список опций (DPI, Яркость, Цвет) для конкретного сканера }
procedure GetScannerOptions(const AScannerID: string; AOptionsList: TBaseOptionList);


procedure ConnectDevice(const AScannerID: string; AValues: TWiaValueList): IDevice;

{ Выполняет «тихое» сканирование и записывает JPEG-файл в переданный поток }
procedure ScanToJpegStream(const AScannerID: string; AValues: TWiaValueList; ATargetStream: TStream);

{ Вспомогательная изолированная процедура трансформации WIA-вектора в JPEG поток }
procedure WiaVectorToJpegStream(AVector: IVector; ATargetStream: TStream);

implementation

{ ПОЛУЧЕНИЕ СПИСКА СКАНЕРОВ }
procedure GetAvailableWiaScanners(AList: TDeviceInfoList);
var
  DevMgr: IDeviceManager;
  DevInfo: IDeviceInfo;
  I: Integer;
  val: string;
  dID, dVendor, dModel, dType: string;
begin
  if AList = nil then Exit;
  AList.Clear;

  try
    DevMgr := CoDeviceManager.Create;

    // Бежим по коллекции устройств. В FPC 3.2.2 надежнее использовать явный Get_Item с OleVariant
    for I := 1 to DevMgr.DeviceInfos.Count do
    begin
      DevInfo := DevMgr.DeviceInfos.Get_Item(OleVariant(I));

      if DevInfo.Type_ = ScannerDeviceType then
      begin
        dID     := DevInfo.DeviceID;
        dVendor := 'Unknown Vendor';
        dModel  := 'WIA Scanner';
        dType   := 'Scanner';

        val := GetPropStrValue(DevInfo, WIA_DIP_VEND_DESC_STR);
        if val <> '' then dVendor := val;

        val := GetPropStrValue(DevInfo, WIA_DIP_DEV_DESC_STR);
        if val <> '' then dModel := val;

        AList.Add(TDeviceInfo.Create(dID, dVendor, dModel, dType));
      end;
    end;
  finally
    DevInfo := nil;
    DevMgr := nil;
  end;
end;

{ ПОЛУЧЕНИЕ ПАРАМЕТРОВ СКАНЕРА }
procedure GetScannerOptions(const AScannerID: string; AOptionsList: TBaseOptionList);
var
  Device: IDevice;
  Items: IItems;
  Item: IItem;
  Props: IProperties;
  Prop: IProperty;
  I: Integer;
  pTypeStr: string;
  pUnit: TUnit;
  sType: WiaSubType;
begin
  if AOptionsList = nil then Exit;
  AOptionsList.Clear;

  // Подключаемся (внутри Helpers.Connect автоматически раскодируется URL-имя)
  Device := Helpers.Connect(AScannerID);
  Items := Device.Get_Items;
  Item := Items[1]; // Матрица сканера
  Props := Item.Properties;

  for I := 1 to Props.Count do
  begin
    Prop := Props[I];

    // Фильтруем только важные свойства, определяя их логический тип и единицы измерения
    case Prop.PropertyID of
      WIA_IPS_XRES, WIA_IPS_YRES:
        begin pUnit := UnitDpi; pTypeStr := 'int'; end;
      WIA_IPS_CUR_INTENT:
        begin pUnit := UnitNone; pTypeStr := 'list'; end;
      WIA_IPS_BRIGHTNESS, WIA_IPS_CONTRAST:
        begin pUnit := UnitPercent; pTypeStr := 'int'; end;
      else
        Continue; // Пропускаем весь остальной сервисный шум драйвера
    end;

    // Безопасно вытаскиваем субтип WIA
    try
      sType := Prop.SubType;
    except
      sType := UnspecifiedSubType;
    end;

    // Форсируем ListSubType для режима цвета (ID 6146), если сетевой WSD драйвер вернул Unspecified
    if (Prop.PropertyID = WIA_IPS_CUR_INTENT) and (sType = UnspecifiedSubType) then
      sType := ListSubType;

    // Полиморфное добавление в список. Классы из options.pas сами заполнят себя через CreateFromWia
    case sType of
      RangeSubType:
        AOptionsList.Add(TRangeOption.CreateFromWia(Prop, pUnit, pTypeStr));

      ListSubType:
        AOptionsList.Add(TListOption.CreateFromWia(Prop, pUnit, pTypeStr));

      else
        AOptionsList.Add(TBaseOption.CreateFromWia(Prop, pUnit, pTypeStr));
    end;
  end;

  Prop := nil;
  Props := nil;
  Item := nil;
  Items := nil;
  Device := nil;
end;

{НИЗКОУРОВНЕВЫЙ ПЕРЕНОС ИЗ SAFEARRAY В TSTREAM }
procedure VectorToStream(AVector: IVector; Stream: TStream);
var
  DataVariant: OleVariant;
  DataArray: PSafeArray;
  pData: Pointer;
  ElementCount: DWord;
begin
  if (AVector = nil) or (Stream = nil) then Exit;

  DataVariant := AVector.Get_BinaryData;
  if not (TVarData(DataVariant).VType and varArray = varArray) then
    raise Exception.Create('Вектор WIA не содержит массив данных (SafeArray).');

  try
    DataArray := PSafeArray(TVarData(DataVariant).VArray);
    if DataArray = nil then
      raise Exception.Create('Указатель на SafeArray равен nil.');

    // В FPC к структуре rgsabound обращаемся по нулевому индексу [0]
    ElementCount := DataArray^.rgsabound[0].cElements;

    // Блокируем память Windows API и копируем байты в поток Pascal
    SafeArrayAccessData(DataArray, pData);
    try
      Stream.WriteBuffer(pData^, ElementCount);
      Stream.Position := 0;
    finally
      SafeArrayUnaccessData(DataArray);
    end;

  finally
    VarClear(DataVariant);
  end;
end;

{ КОНВЕРТАЦИЯ В JPEG С ИСПОЛЬЗОВАНИЕМ FPIMAGE }
procedure WiaVectorToJpegStream(AVector: IVector; ATargetStream: TStream);
var
  BmpMemoryStream: TMemoryStream;
  FPCImage: TFPMemoryImage;
  Reader: TFPReaderBMP;
  Writer: TFPWriterJPEG;
begin
  if (AVector = nil) or (ATargetStream = nil) then Exit;

  FPCImage := TFPMemoryImage.Create(0, 0);
  try
    BmpMemoryStream := TMemoryStream.Create;
    try
      // Копируем сырые байты BMP во временный поток в памяти
      VectorToStream(AVector, BmpMemoryStream);

      Reader := TFPReaderBMP.Create;
      try
        // Графический движок FPC парсит BMP структуру из памяти
        FPCImage.LoadFromStream(BmpMemoryStream, Reader);
      finally
        Reader.Free;
      end;
    finally
      BmpMemoryStream.Free;
    end;

    Writer := TFPWriterJPEG.Create;
    try
      // Задаем качество сжатия (0..100)
      Writer.CompressionQuality := 90;
      // Сжимаем и сохраняем JPEG напрямую в поток Horse-ответа
      FPCImage.SaveToStream(ATargetStream, Writer);
    finally
      Writer.Free;
    end;
  finally
    FPCImage.Free;
  end;
end;

procedure ConnectDevice(const AScannerID: string; AValues: TWiaValueList): IDevice;
Device: IDevice;
Items: IItems;
Item: IItem;
begin
  Result := Helpers.Connect(AScannerID);

  if (AValues <> nil) and (AValues.Count > 0) then
  begin
    for I := 0 to AValues.Count - 1 do
    begin
      // Объект значения сам разберется, куда лезть: в Device или в дочерний Item
      AValues[I].Apply(Device);
    end;
  end;

end;

procedure ScanToJpegStream(const AScannerID: string; AValues: TWiaValueList; ATargetStream: TStream);
var
  Device: IDevice;
  Items: IItems;
  Item: IItem;
  TransferResult: OleVariant;
  ImgFile: IImageFile;
  Vector: IVector;
  I: Integer;
begin
  Device := ConnectDevice(AScannerID, AValues);
  // Получаем дочернюю матрицу для совершения самого трансфера картинки
  Items := Device.Get_Items;
  Item := Items.Get_Item(1);

  // Запуск физического сканирования
  TransferResult := Item.Transfer(GUIDToString(WiaImgFmt_BMP));
  ImgFile := IDispatch(TransferResult) as IImageFile;
  if ImgFile = nil then
    raise Exception.Create('Не удалось получить объект IImageFile.');

  Vector := ImgFile.Get_FileData;
  WiaVectorToJpegStream(Vector, ATargetStream);

  Vector := nil; ImgFile := nil; Item := nil; Items := nil; Device := nil;
end;



end.

