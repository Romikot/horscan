unit services.storage;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, fpjson, jsonparser;

type
  TFileStorage = class
  private
    FBaseDir: string;
    function GenerateUUIDName: string;
  public
    constructor Create(const ABaseDir: string);

    function List: TJSONArray;
    procedure Get(const AFileName: string; AOutStream: TStream);
    procedure Delete(const AFileName: string);
    function Store(AInStream: TStream): string;
  end;

var
  Storage: TFileStorage;

implementation

{ TFileStorage }

constructor TFileStorage.Create(const ABaseDir: string);
begin
  inherited Create;
  // Гарантируем наличие слэша в конце пути и создаем директорию, если её нет
  FBaseDir := IncludeTrailingPathDelimiter(ABaseDir);
  if not DirectoryExists(FBaseDir) then
    ForceDirectories(FBaseDir);
end;

function TFileStorage.GenerateUUIDName: string;
var
  UID: TGUID;
begin
  CreateGUID(UID);
  // Возвращаем UUID без лишних скобок в нижнем регистре + расширение
  Result := LowerCase(GUIDToString(UID));
  Result := StringReplace(Result, '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]) + '.jpg';
end;

function TFileStorage.List: TJSONArray;
var
  SR: TSearchRec;
begin
  Result := TJSONArray.Create;
  try
    if FindFirst(FBaseDir + '*.jpg', faAnyFile, SR) = 0 then
    begin
      repeat
        // Добавляем только имена файлов в массив
        Result.Add(SR.Name);
      until FindNext(SR) <> 0;
    end;
  finally
    FindClose(SR);
  end;
end;

procedure TFileStorage.Get(const AFileName: string; AOutStream: TStream);
var
  FileStream: TFileStream;
  FullPath: string;
begin
  FullPath := FBaseDir + AFileName;
  if not FileExists(FullPath) then
    raise Exception.CreateFmt('Файл %s не найден в хранилище', [AFileName]);

  FileStream := TFileStream.Create(FullPath, fmOpenRead or fmShareDenyWrite);
  try
    AOutStream.CopyFrom(FileStream, 0);
  finally
    FileStream.Free;
  end;
end;

procedure TFileStorage.Delete(const AFileName: string);
var
  FullPath: string;
begin
  FullPath := FBaseDir + AFileName;
  if FileExists(FullPath) then
  begin
    if not DeleteFile(FullPath) then
      raise Exception.CreateFmt('Не удалось удалить файл %s', [AFileName]);
  end
  else
    raise Exception.CreateFmt('Файл %s для удаления не найден', [AFileName]);
end;

function TFileStorage.Store(AInStream: TStream): string;
var
  FileStream: TFileStream;
  NewName: string;
begin
  NewName := GenerateUUIDName;
  AInStream.Position := 0;

  FileStream := TFileStream.Create(FBaseDir + NewName, fmCreate);
  try
    FileStream.CopyFrom(AInStream, 0);
    Result := NewName;
  finally
    FileStream.Free;
  end;
end;

initialization
  Storage := TFileStorage.Create(GetTempDir);
finalization
  Storage.Free;

end.

