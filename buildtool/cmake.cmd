@echo off
setlocal

:: Search all arguments for the string "--build"
echo %* | findstr /i /c:"--build" >nul

if %errorlevel% equ 0 (
    :: "--build" was found, pass arguments as-is
    "%DEVECO_SDK_HOME%\default\openharmony\native\build-tools\cmake\bin\cmake.exe" %*
) else (
    :: "--build" was NOT found, add your custom arguments (e.g., -G Ninja)
    "%DEVECO_SDK_HOME%\default\openharmony\native\build-tools\cmake\bin\cmake.exe" ^
-DOHOS_ARCH=arm64-v8a ^
-DCMAKE_OHOS_ARCH_ABI=arm64-v8a ^
-DCMAKE_BUILD_TYPE=Release ^
-DOHOS_SDK_NATIVE="%DEVECO_SDK_HOME%/default/openharmony/native" ^
-DCMAKE_TOOLCHAIN_FILE="%DEVECO_SDK_HOME%/default/hms/native/build/cmake/hmos.toolchain.cmake" ^
-GNinja ^
-DCMAKE_COMMAND="%~f0" ^
-DCMAKE_CROSSCOMPILING="TRUE" ^
-DCMAKE_MAKE_PROGRAM="%DEVECO_SDK_HOME%/default/openharmony/native/build-tools/cmake/bin/ninja.exe" ^
-DHMOS_SDK_NATIVE="%DEVECO_SDK_HOME%/default/hms/native" %*
)