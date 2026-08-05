unit controllers.images;

{$MODE DELPHI}
{$CODEPAGE UTF8}

interface

uses
  Classes, SysUtils, Horse, fpjson, services.Storage;

// Процедура для регистрации всех эндпоинтов работы с картинками
procedure Register;

implementation

{ GET /images - Получение списка имен файлов }
procedure GetImagesList(Req: THorseRequest; Res: THorseResponse);
var
  FileList: TJSONArray;
begin
    // Запрашиваем список файлов у TFileStorage
    FileList := Storage.List;

    Res.Send(FileList.AsJSON);
end;

{ GET /images/:name - Скачивание/отдача конкретного файла изображения }
procedure GetImageFile(Req: THorseRequest; Res: THorseResponse);
var
  FileName: string;
  FullFilePath: string;
  stream: TStream;
begin
  // Извлекаем имя файла из параметров пути (:name)
  FileName := Req.Params['name'];

  if FileName = '' then
  begin
    Res.Status(400).Send('Имя файла не указано');
    Exit;
  end;

  stream := TMemoryStream.Create;
  try
    Storage.Get(FileName, stream);
    if stream.Size > 0 then
    begin
      Res.ContentType('image/jpeg');
      Res.SendFile(stream, FileName, 'image/jpeg')
    end
    else
      Res.Status(400).Send('Сканер вернул пустой массив данных.');
  finally
    stream.Free;
  end;
end;

{ DELETE /images/:name - Удаление файла изображения }
procedure DeleteImageFile(Req: THorseRequest; Res: THorseResponse);
var
  FileName: string;
  FullFilePath: string;
begin
  FileName := Req.Params['name'];

  if FileName = '' then
  begin
    Res.Status(400).Send('Имя файла не указано');
    Exit;
  end;

  try
    Storage.Delete(FileName);

  except
    on ENotFound do
    begin
      Res.Status(404).Send('Файл не найден');
      Exit;
    end;
    on e: Exception do
    begin
      Res.Status(500).Send(e.Message);
      Exit;
    end;
  end;
  Res.Status(200).Send('Файл успешно удален')
end;

procedure Register;
begin
  // Привязываем методы к путям Horse
  THorse.Get('/images', THorseCallback(@GetImagesList));
  THorse.Get('/images/:name', THorseCallback(@GetImageFile));
  THorse.Delete('/images/:name', THorseCallback(@DeleteImageFile));
end;

end.

