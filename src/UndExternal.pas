unit UndExternal;

{
  UnderScript External Importer
  Imports Lua variables to the script
  Copyright (c) 2013-2020 Felipe Daragon
  License: MIT (http://opensource.org/licenses/mit-license.php)
}

interface

uses
  Classes, Lua, pLua, Variants, SysUtils, CatStrings, CatCSCommand, CatFiles,
  CatStringLoop, UndConst;

type
  TUndExternal = class
  private
    fLanguage: TUndLanguageExternal;
    fEnableDebug: boolean;
    fEnableImport: boolean;
    fLuaState: Plua_State;
    procedure Debug(s: string);
    procedure HandleOutput(L: Plua_State; const s: string);
    function ImportVariables(L: Plua_State; FormatStr: string): string;
    function GetFormatedImport(const s: string;v:TUndLuaVariable): string;
    function GetLocalsImport(L: Plua_State; LocalFormatStr: string;
      sl: TStringList): string;
  public
    constructor Create(L: Plua_State; Lang:TUndLanguageExternal);
    destructor Destroy; override;
    function GetScript(L: Plua_State; script: string): string;
    procedure RunScript(L: Plua_State; script: string);
  end;

implementation

function CanAddKey(lt: integer; n: string): boolean;
begin
  result := false;
  case lt of
    LUA_TSTRING:
      result := true;
    LUA_TBOOLEAN:
      result := true;
    LUA_TNUMBER:
      result := true;
    LUA_TNIL:
      result := true;
  end;
  // Do not import variables starting with underscore
  if beginswith(n, '_') then
    result := false;
  // if n='_VERSION' then result:=false;
  // if n='AST_COMPILE_ERROR_NUMBER' then result:=false;
end;

function TUndExternal.GetFormatedImport(const s: string;v:TUndLuaVariable): string;
var
 getter:string;
begin
  getter := fLanguage.VarReadFormat;
  getter := replacestr(getter, '%k', v.name);
  result := s;
  result := replacestr(result, '%p', cUnderSetPrefix);
  result := replacestr(result, '%k', v.name);
  result := replacestr(result, '%t', v.LuaTypeStr);
  if v.luatype = LUA_TSTRING then begin
   v.value := replacestr(fLanguage.StringFormat,'%s',base64encode(v.value));
   getter := replacestr(fLanguage.B64Encoder, '%s', getter);
   v.value := replacestr(fLanguage.B64Decoder, '%s', v.value);
  end;
  result := replacestr(result, '%g', getter);
  result := replacestr(result, '%v', v.value);
end;

function TUndExternal.GetLocalsImport(L: Plua_State; LocalFormatStr: string;
  sl: TStringList): string;
var
  v: TUndLuaVariable;
  vname:PAnsiChar;
  ar: plua_Debug;
  i: integer;
  found: boolean;
  procedure getloc(id:integer);
  begin
    debug('get loc...'+inttostr(id));
    lua_pop(L, 1);
    vname := lua_getlocal(L, @ar, i);
    v.name := vname;
    v.LuaType := lua_type(L, -1);
    v.LuaTypeStr := plua_luatypetokeyword(v.LuaType);
    // VarValue:=plua_tovariant(L, -1);
    if vname <> nil then
    begin
      Debug('found local var:' + v.name);
      if sl.IndexOf(v.name) = -1 then
      begin
        if CanAddKey(v.LuaType, v.name) then
        begin
          v.value := plua_AnyToString(L, -1);
          result := result + GetFormatedImport(LocalFormatStr, v);
          // result:=result+replacestr(localformatstr,'%k',VarName);
        end;
        sl.Add(v.name);
      end;
    end;
    inc(i);
  end;

begin
  found := false;
  // dbg('getting locals for'+localformatstr);
  if lua_getstack(L, 1, @ar) <> 1 then
    Exit;
  // dbg('getting... '+LocalFormatStr);
  i := 1;
  getloc(1);
  // if v.name = nil then dbg('first var is nil');
  while (vname <> nil) and (found = false) do
    getloc(2);
   //debug('getlocimp result:'+result);
end;

function TUndExternal.ImportVariables(L: Plua_State; FormatStr: string): string;
var
  sl: TStringList;
  v: TUndLuaVariable;// global-related
  ar: plua_Debug; // local-related
  Index, MaxTable, SubTableMax: integer;
  r: string;
begin
  index := -1;
  MaxTable := 0;
  SubTableMax := 1; // -1, 0, 1, works with these params. do not change!
  sl := TStringList.Create;
  // global variables...
  if RudImportGlobals = true then
  begin
    Debug('importing globals...');
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    Index := plua_absindex(L, Index);
    //Index := LuaAbsIndex(L, index);
    lua_pushnil(L);
    while (lua_next(L, Index) <> 0) do
    begin
      v.LuaType := lua_type(L, -1);
      v.LuaTypeStr := plua_luatypetokeyword(v.LuaType);
      v.name := plua_dequote(plua_LuaStackToStr(L, -2, MaxTable, SubTableMax));
      // Value := Dequote(LuaStackToStr(L, -1, MaxTable, SubTableMax));
      if sl.IndexOf(v.name) = -1 then
      begin
        if CanAddKey(v.LuaType, v.name) then
        begin
          // dbg('added:'+key);
          //v.value := plua_AnyToString(L, -1);
          v.value := plua_dequote(plua_LuaStackToStr(L, -1, MaxTable, SubTableMax));
          result := result + GetFormatedImport(FormatStr, v);
          // result:=result+replacestr(formatstr,'%k',key);
        end;
        sl.Add(v.name);
      end;
      //debug('found global var:'+v.name);
      lua_pop(L, 1);
    end;
    lua_pop(L, 1);
  end;

  // local variables... is localformatstr is empty, only globals are imported
  if RudImportLocals = true then
  begin
    if (lua_getstack(L, -2, @ar) = 1) then
    begin
      Debug('importing locals...');
      r := GetLocalsImport(L, FormatStr, sl);
      if r <> emptystr then
      begin
        if RudImportGlobals then
          result := result + r
        else
          result := r;
      end;
    end;
  end;
  sl.free;

end;

procedure TUndExternal.Debug(s: string);
begin
  if fEnableDebug then
    writeln('[dbg] ' + s);
end;

function TUndExternal.GetScript(L: Plua_State; script: string): string;
var
  InitScript,  EndScript: string;
begin
  result := script;
  if fEnableImport = false then
    Exit;
  if RudImportVariables = false then
    Exit;
  Debug('Getting script...');
  InitScript := ImportVariables(L, fLanguage.FuncReadFormat);
  Debug('Init:' + InitScript);
  EndScript := ImportVariables(L, fLanguage.FuncWriteFormat);
  Debug('End:' + EndScript);
  result := InitScript + script + EndScript;
  Debug('Done getting script.');
end;

procedure TUndExternal.HandleOutput(L: Plua_State; const s: string);
var
  slp:TStringLoop;
  sl:TStringList;
  ltype:integer;
  vvalue,vname:string;
begin
  sl := TStringList.Create;
  slp := TStringLoop.Create;
  slp.LoadFromString(s);
  while slp.Found do begin
    if beginswith(slp.Current, cUnderSetPrefix) then begin
      sl.CommaText := after(slp.Current, cUnderSetPrefix);
      ltype := plua_keywordtoluatype(sl.Values['t']);
      vname := sl.Values['n'];
      vvalue := sl.Values['v'];
      case ltype of
        LUA_TBOOLEAN:
          pLua_SetLocal(fLuaState,vname,StrToBool(vvalue));
        LUA_TNUMBER:
          pLua_SetLocal(fLuaState,vname,StrToIntDef(vvalue,0));
        LUA_TNIL:
          pLua_SetLocal(fLuaState,vname,varNull);
        LUA_TSTRING: begin
          vvalue := base64decode(vvalue);
          //writeln('setting:'+vname+'='+vvalue);
          pLua_SetLocal(fLuaState,vname,vvalue);
        end;
      end;
    end else begin
      if rudCustomFunc_WriteLn <> emptystr then
      Und_CustomWriteLn(L,slp.Current,rudCustomFunc_WriteLn);
      //writeln(slp.Current);
    end;
  end;
  slp.Free;
  sl.Free;
end;

procedure TUndExternal.RunScript(L: Plua_State; script: string);
var
  cmd: TCatCSCommand;
  fn, underpath, command: string;
  sl: TStringList;
begin
  //path := 'R:\Win64\Extensions\underscript\';
  underpath := extractfilepath(paramstr(0))+'Extensions\underscript';
  command := replacestr(fLanguage.Command, '%u', underpath);
  script:=(GetScript(L, script));

  if pos('%',fLanguage.FormatScript) <> 0 then
  script := format(fLanguage.FormatScript,[script]);
  //writeln(script);

  fn := GetTempFile(fLanguage.FileExt);
  sl := TStringList.Create;
  sl.Text := script;
  sl.SaveToFile(fn);
  cmd := TCatCSCommand.Create;
  //cmd.OnOutput := HandleOutput;
  RunCmdWithCallBack(command, fn,
    procedure(const Line: PAnsiChar)
    begin
      HandleOutput(L, String(Line));
    end
  );
  cmd.free;
  sl.free;
  deletefile(fn);
end;

constructor TUndExternal.Create(L: Plua_State; Lang:TUndLanguageExternal);
begin
  inherited Create;
  fEnableImport := true;
  fEnableDebug := false;
  fLuaState := L;
  fLanguage := Lang;
end;

destructor TUndExternal.Destroy;
begin
  inherited;
end;

end.
