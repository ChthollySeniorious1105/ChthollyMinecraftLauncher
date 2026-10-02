@echo off
rem Stand-alone build of pulse_native.dll into _build\native (for native tests).
set "PATH=%PATH:"=%"
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat" >nul
set "CM=C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\IDE\CommonExtensions\Microsoft\CMake"
set "PATH=%CM%\CMake\bin;%CM%\Ninja;%PATH%"
set "ROOT=%~dp0..\.."
cmake -S "%ROOT%\client\native" -B "%ROOT%\_build\native" -G Ninja -DCMAKE_BUILD_TYPE=Release >nul || exit /b 1
cmake --build "%ROOT%\_build\native" || exit /b 1
copy /y "%ROOT%\client\native\bin\*.dll" "%ROOT%\_build\native\" >nul
if not exist "%ROOT%\_build\native\ai\models" mkdir "%ROOT%\_build\native\ai\models"
for %%f in ("%ROOT%\client\native\models\*.onnx") do if not exist "%ROOT%\_build\native\ai\models\%%~nxf" mklink /h "%ROOT%\_build\native\ai\models\%%~nxf" "%%f" >nul
