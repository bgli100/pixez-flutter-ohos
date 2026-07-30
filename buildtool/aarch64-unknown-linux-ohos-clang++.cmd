@echo off
setlocal enabledelayedexpansion
set "ARGS="
:parse
if "%~1"=="" goto :done
set "arg=%~1"
if "!arg:~0,9!"=="--target=" goto :next
if "!arg!"=="-target" (
    shift
    goto :next
)
if defined ARGS (
    set "ARGS=!ARGS! %~1"
) else (
    set "ARGS=%~1"
)
:next
shift
goto :parse
:done
"%DEVECO_SDK_HOME%\default\openharmony\native\llvm\bin\clang++.exe" ^
-target aarch64-linux-ohos ^
--sysroot="%DEVECO_SDK_HOME%\default\openharmony\native\sysroot" ^
-D__MUSL__ !ARGS!