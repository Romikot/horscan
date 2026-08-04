unit controllers.scanner;

{$MODE DELPHI}
{$CODEPAGE UTF8}

interface

uses
  ActiveX,
  ComObj,
  Variants,
  SysUtils,
  Classes,
  fpjson,
  Horse,
  WIA_TLB,
  helpers,
  dataobjects,
  options,
  optvalues,
  services.wiascanner,
  services.storage;

procedure Register;

implementation

{ GET /devices - Возвращает список доступных сканеров }
procedure GetDevices(Req: THorseRequest; Res: THorseResponse);
var
  RootArray: TJSONArray;
  DeviceList: TDeviceInfoList;
  I: integer;
  Device: TDeviceInfo;
begin
  CoInitialize(nil);
  try
    RootArray := TJSONArray.Create;
    try
      DeviceList := TDeviceInfoList.Create(True);
      try
        GetAvailableWiaScanners(DeviceList);

        for I := 0 to DeviceList.Count-1 do
        begin
          Device := DeviceList[I];
          RootArray.Add(Device.ToJSONObject);
        end;
      finally
        DeviceList.Free;
      end;

      Res.ContentType('application/json; charset=utf-8');
      Res.Send(RootArray.AsJSON);
    finally
      RootArray.Free;
    end;
  finally
    CoUninitialize;
  end;
end;

procedure GetDeviceOptions(Req: THorseRequest; Res: THorseResponse);
var
  ScannerID: string;
  OptionsList: TBaseOptionList;
  RootArray: TJSONArray;
  I: Integer;
begin
  ScannerID := Req.Params['name'];

  CoInitialize(nil);
  OptionsList := TBaseOptionList.Create(True);
  try
    try
      // Заполняем список опций через сервис WIA
      GetScannerOptions(ScannerID, OptionsList);

      RootArray := TJSONArray.Create;
      try
        for I := 0 to OptionsList.Count-1 do
          RootArray.Add(OptionsList[I].ToJSONObject);

        Res.ContentType('application/json; charset=utf-8');
        Res.Send(RootArray.AsJSON);
      finally
        RootArray.Free;
      end;
    except
      on E: Exception do
        Res.Status(500).Send('Ошибка чтения параметров: ' + E.Message);
    end;
  finally
    OptionsList.Free;
    CoUninitialize;
  end;
end;

{ GET /devices/:name/scan - Запуск сканирования для конкретного сканера }
procedure DoScanDevice(Req: THorseRequest; Res: THorseResponse);
var
  name: string;
  ResponseStream: TMemoryStream;
  ValuesList: TWiaValueList;
  QueryKey: string;
begin
  name := Req.Params['name'];

  CoInitialize(nil);
  ResponseStream := TMemoryStream.Create;
  ValuesList := TWiaValueList.Create(True);
  try
    try
      // ПОЛНАЯ АВТОМАТИЗАЦИЯ: Обходим абсолютно ВСЕ query-параметры из строки URL
      for QueryKey in Req.Query.Dictionary.Keys do
      begin
        // Фабрика сама найдет константу, сделает текстовый маппинг и создаст нужный TWiaValue объект
        ValuesList.Add(TWiaValueFactory.CreateValue(QueryKey, Req.Query[QueryKey]));
      end;

      // Запуск сканирования
      ScanToJpegStream(name, ValuesList, ResponseStream);

      if ResponseStream.Size > 0 then
        Res.SendFile(ResponseStream, 'scanned_document.jpg', 'image/jpeg')
      else
        Res.Status(400).Send('Сканер вернул пустой массив данных.');

    except
      on E: Exception do
      begin
        Res.Status(400).ContentType('text/plain; charset=utf-8');
        Res.Send('Ошибка параметров сканирования: ' + E.Message);
      end;
    end;
  finally
    ValuesList.Free;
    ResponseStream.Free;
    CoUninitialize;
  end;
end;

{ GET /devices/:name/multiscan - Запуск сканирования для конкретного сканера }
procedure DoMultiScan(Req: THorseRequest; Res: THorseResponse);
var
  DeviceName: string;
  FileArray: TJSONArray;
  ScanStream: TMemoryStream;
  SavedName: string;
  HasMorePages: Boolean;
begin
  DeviceName := Req.Params['name'];
  FileArray := TJSONArray.Create;
  try
    try
      // Инициализируем ваш WIA-сканер (настройка на работу с автоподатчиком ADF)
      // TWiaScanner.InitDevice(DeviceName, True {UseADF});

      HasMorePages := True;

      while HasMorePages do
      begin
        ScanStream := TMemoryStream.Create;
        try
          // Вызываем ваш метод сканирования одной страницы в JPEG поток
          // HasMorePages := TWiaScanner.ScanNextPage(ScanStream);

          // --- ДЛЯ ТЕСТА (если страниц больше нет, убрать эмуляцию): ---
          // Эмулируем, что отсканировали одну страницу для теста
          // (Замените этот блок на реальный вызов WIA)
          HasMorePages := False;
          // -------------------------------------------------------------

          if ScanStream.Size > 0 then
          begin
            // Передаем поток в хранилище, оно вернет UUID-имя файла
            SavedName := Storage.Store(ScanStream);
            FileArray.Add(SavedName);
          end;

        finally
          ScanStream.Free;
        end;
      end;

      // Важно: Отправляем TJSONArray. Horse + Jhonson сами сериализуют его и очистят память
      Res.Send(FileArray.AsJSON);

    except
      on E: Exception do
      begin
        Res.Status(500).ContentType('text/plain; charset=utf-8');
        Res.Send('error: ' + E.Message);
      end;
    end;

  finally
    FileArray.Free;
  end;
end;

procedure Register;
begin
  THorse.Get('/devices', THorseCallback(@GetDevices));
  THorse.Get('/devices/:name/options', THorseCallback(@GetDeviceOptions));
  THorse.Get('/devices/:name/scan', THorseCallback(@DoScanDevice));
  THorse.Get('/devices/:name/multiscan', DoMultiScan);
end;

end.

