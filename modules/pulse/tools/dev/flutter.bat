@echo off
rem Runs flutter with the VS toolchain + China mirrors, from client\.
set "PATH=%PATH:"=%"
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat" >nul
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
set "PATH=D:\Tools\flutter\bin;%PATH%"
cd /d "%~dp0..\..\client"
call flutter %*
