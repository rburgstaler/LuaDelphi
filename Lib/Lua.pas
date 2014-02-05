{
/**
 * @package     Delphi Lua
 * @copyright   Copyright (c) 2009 Dennis D. Spreen (http://www.spreendigital.de/blog)
 * @license     http://opensource.org/licenses/gpl-license.php GNU Public License
 * @author      Dennis D. Spreen <dennis@spreendigital.de>
 * @version     1.3
 * @revision    $Id: Lua.pas 102 2009-09-30 11:39:41Z dennis.spreen $
 */

History
1.3     DS      Improved Callback, now uses pointer instead of object index
                Modified RegisterFunctions to allow methods from other class
                to be registered, moved object table into TLua class
1.2	DS	Added example on how to extend lua with a delphi dll
1.1     DS      Improved global object table, this optimizes the delphi
                function calls
1.0     DS      Initial Release

Copyright 2009  Dennis D. Spreen (email : dennis@spreendigital.de)

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
}

{

FPC Version of Lua.

+ implement Lua 5.2

About license from author,

@nikolai:
do whatever you want with it – no license required (even for commercial use). It would be nice to get a short note if used in a project. thanks!

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.


}

unit Lua;
{$ifdef FPS}
  {$MODE Delphi}
{$endif}
{$I luadefine.inc}

interface

uses
  Classes,
  {$IFNDEF LUA52}
  LuaLib
  {$ELSE}
  lua52
  {$ENDIF}
  ;

type
  TLuaState = {$IFNDEF LUA52} Lua_State {$ELSE} Plua_State {$ENDIF} ;

  TLua = class(TObject)
  private
    fAutoRegister: Boolean;
    CallbackList: TList;  // internal callback list
  public
    LuaInstance: TLuaState;  // Lua instance
    constructor Create(AutoRegister: Boolean = True); overload; virtual;
    destructor Destroy; override;
    function DoFile(Filename: String): Integer; virtual;// load file and execute
    procedure RegisterFunction(FuncName: AnsiString; MethodName: AnsiString = ''; Obj: TObject = NIL); virtual; //register function
    procedure AutoRegisterFunctions(Obj: TObject);  // register all published functions
    procedure UnregisterFunctions(Obj: TObject); // unregister all object functions
  end;

implementation

type
  TProc = function(L: TLuaState): Integer of object; // Lua Function

  TCallback = class
    Routine: TMethod;  // Code and Data for the method
    Exec: TProc;       // Resulting execution function
  end;

//
// This function is called by Lua, it extracts the object by
// pointer to the objects method by name, which is then called.
//
// @param       Lua_State   L   Pointer to Lua instance
// @return      Integer         Number of result arguments on stack
//
function LuaCallBack(L: {$IFNDEF LUA52} Lua_State {$ELSE} Plua_State {$ENDIF}): Integer; cdecl;
var
  CallBack: TCallBack;       // The Object stored in the Object Table
begin
  // Retrieve first Closure Value (=Object Pointer)
  CallBack := lua_topointer(L, lua_upvalueindex(1));

  // Execute only if Object is valid
  if (assigned(CallBack) and assigned(CallBack.Exec)) then
    Result := CallBack.Exec(L)
  else
    Result := 0;
end;

{ TLua }

//
// Create a new Lua instance and optionally create Lua functions
//
// @param       Boolean      AutoRegister       (optional)
// @return      TLua                            Lua Instance
//
constructor TLua.Create(AutoRegister: Boolean = True);
begin
  inherited Create;
  {$IFNDEF LUA52}
  // Load Lua Lib if not already done
  if (not LuaLibLoaded) then
    LoadLuaLib;
  // Open Library
  LuaInstance := Lua_Open();
  {$ELSE}
  LuaInstance := luaL_newstate;
  {$ENDIF}
  luaopen_base(LuaInstance);

  fAutoRegister := AutoRegister;

  // Create Object List on initialization
  CallBackList := TList.Create;

  // if set then register published functions
  if (AutoRegister) then
    AutoRegisterFunctions(self);
end;

//
// Dispose Lua instance
//
destructor TLua.Destroy;
begin
  // Unregister all functions if previously autoregistered
  if (fAutoRegister) then
    UnregisterFunctions(Self);

  // dispose Object List on finalization
  CallBackList.Free;

  // Close instance
  Lua_Close(LuaInstance);
  inherited;
end;

//
// Wrapper for Lua File load and Execution
//
// @param       String  Filename        Lua Script file name
// @return      Integer
//
function TLua.DoFile(Filename: String): Integer;
begin
  Result := lual_dofile(LuaInstance, PAnsiChar(AnsiString(Filename)));
end;

//
// Register a new Lua Function and map it to the Objects method name
//
// @param       AnsiString      FuncName        Lua Function Name
// @param       AnsiString      MethodName      (optional) Objects Method name
//
procedure TLua.RegisterFunction(FuncName: AnsiString; MethodName: AnsiString = ''; Obj: TObject = NIL);
var
  CallBack: TCallBack; // Callback Object
begin
  // if method name not specified use Lua function name
  if (MethodName = '') then
    MethodName := FuncName;

  // if not object specified use this object
  if (Obj = NIL) then
    Obj := Self;

  // Add Callback Object to the Object Index
  CallBack := TCallBack.Create;
  CallBack.Routine.Data := Obj;
  CallBack.Routine.Code := Obj.MethodAddress(String(MethodName));
  CallBack.Exec := TProc(CallBack.Routine);
  CallbackList.Add(CallBack);

  (* 5.1
  // prepare Closure value (Method Name)
  lua_pushstring(LuaInstance, PAnsiChar(FuncName));
  *)

  // prepare Closure value (CallBack Object Pointer)
  lua_pushlightuserdata(LuaInstance, CallBack);

  // set new Lua function with Closure value
  lua_pushcclosure(LuaInstance, LuaCallBack, 1);
  (* 5.1
  lua_settable(LuaInstance, LUA_GLOBALSINDEX);
  *)
  lua_setglobal(LuaInstance, PAnsiChar(FuncName));
end;

//
// UnRegister all new Lua Function
//
// @param       TObject     Object      Object with prev registered lua functions
//
procedure TLua.UnregisterFunctions(Obj: TObject);
var
  I: Integer;
  CallBack: TCallBack;
begin
  // remove obj from object list
  for I := CallBackList.Count downto 1 do
  begin
    CallBack := CallBackList[I-1];
    if (assigned(CallBack)) and (CallBack.Routine.Data = Obj) then
    begin
      CallBack.Free;
      CallBackList.Items[I-1] := NIL;
      CallBackList.Delete(I-1);
    end;
  end;
end;

//
// Register all published methods as Lua Functions
//
procedure TLua.AutoRegisterFunctions(Obj: TObject);
{$IFNDEF FPC}
type
  PPointer = ^Pointer;
  PMethodRec = ^TMethodRec;

  TMethodRec = packed record
    wSize: Word;
    pCode: Pointer;
    sName: ShortString;
  end;
var
  MethodTable: PAnsiChar;
  MethodRec: PMethodRec;
  wCount: Word;
  nMethod: Integer;
begin
  // Get a pointer to the class's published method table
  MethodTable := PAnsiChar(Pointer(PAnsiChar(Obj.ClassType) + vmtMethodTable)^);

  if (MethodTable <> Nil) then
  begin
    // Get the count of the methods in the table
    Move(MethodTable^, wCount, 2);

    // Position the MethodRec pointer at the first method in the table
    // (skip over the 2-byte method count)
    MethodRec := PMethodRec(MethodTable + 2);

    // Iterate through all the published methods of this class
    for nMethod := 0 to wCount - 1 do
    begin
      // Add the method name to the lua functions
      RegisterFunction(MethodRec.sName, MethodRec.sName, Obj);
      // Skip to the next method
      MethodRec := PMethodRec(PAnsiChar(MethodRec) + MethodRec.wSize);
    end;
  end;
end;
{$ELSE}
(* FPC version of getting Method Tables from Obj *)
type
  PMethodNameRec=^TMethodNameRec;
  TMethodNameRec=packed record
    Name:PShortString;
    Addr:Pointer;
  end;
  TMethodNameRecs=packed array[0..0] of TMethodNameRec;
  PMethodNameTable=^TMethodNameTable;
  TMethodNameTable=packed record
    Count:LongWord;
    Entries:TMethodNameRecs;
  end;

var
  MethodTable: PMethodNameTable;
  i:integer;
begin
  if Obj=nil then
     exit;
  MethodTable:=PMethodNameTable((Pointer(Obj.ClassType)+vmtMethodTable)^);
  if MethodTable=nil then
     exit;
  for i:=0 to MethodTable^.Count-1 do
    RegisterFunction(MethodTable^.Entries[i].Name^,MethodTable^.Entries[i].Name^,Obj);
end;
{$ENDIF}


end.
