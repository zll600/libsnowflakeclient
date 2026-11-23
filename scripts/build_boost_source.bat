::
:: Build boost
:: GitHub repo: https://github.com/boostorg/boost.git
::
@echo off
set boost_src_version=1.81.0
set boost_build_version=2
set boost_version=%boost_src_version%.%boost_build_version%
call %*
goto :EOF

:get_version
    set version=%boost_version%
    goto :EOF

:build
setlocal
set platform=%1
set build_type=%2
set vs_version=%3
set dynamic_runtime=%4

set scriptdir=%~dp0
call "%scriptdir%_init.bat" %platform% %build_type% %vs_version%
if %ERRORLEVEL% NEQ 0 goto :error
call "%scriptdir%utils.bat" :setup_visual_studio %vs_version%
if %ERRORLEVEL% NEQ 0 goto :error

set currdir=%cd%

if /I "%platform%"=="x64" (
    set engine_dir=Program Files
	set bitness=64
)
if /I "%platform%"=="x86" (
    set engine_dir=Program Files (x86^)
	set bitness=32
)

::@echo off
set DEPS_DIR=%scriptdir%..\deps
set BOOST_SOURCE_DIR=%DEPS_DIR%\boost-%boost_src_version%
set BOOST_INSTALL_DIR=%scriptdir%..\deps-build\%build_dir%\boost

rd /S /Q %BOOST_SOURCE_DIR%
git clone --single-branch --branch deps/boost-%BOOST_SRC_VERSION% https://github.com/snowflakedb/libsnowflakeclient.git %BOOST_SOURCE_DIR%

cd "%BOOST_SOURCE_DIR%"

rd /S /Q %BOOST_INSTALL_DIR%
md %BOOST_INSTALL_DIR%

if /I "%build_type%"=="debug" (
    set debugging=on
	set variant=debug
) else (
    set debugging=off
	set variant=release
)

if /I "%dynamic_runtime%"=="on" (
    set runtimelink=shared
) else (
    set runtimelink=static
)

:: Boost 1.81 does not know VS2026 (toolset v145):
:: - bootstrap fails with "Unknown toolset: vcunk", so pass its generic msvc
::   toolset, which builds b2 with the cl.exe set up by vcvarsall.
:: - b2 cannot detect the MSVC version and falls back to a broken "msvc-6.0",
::   so declare msvc-14.5 in a user-config: cl.exe comes from PATH and the
::   setup script is VS2026's vcvarsall.bat. Jam treats \ as an escape, so
::   the path uses forward slashes.
set boost_bootstrap_toolset=
set boost_toolset=msvc-14.3
set boost_user_config=
if /I "%vs_version%"=="VS18" (
    set boost_bootstrap_toolset=msvc
    set boost_toolset=msvc-14.5
    set "boost_user_config=--user-config=%BOOST_SOURCE_DIR%\user-config-vs18.jam"
    setlocal EnableDelayedExpansion
    for %%i in ("%VCINSTALLDIR%\Auxiliary\Build\vcvarsall.bat") do set "boost_vcvarsall=%%~fi"
    > "%BOOST_SOURCE_DIR%\user-config-vs18.jam" echo using msvc : 14.5 : : ^<setup^>"!boost_vcvarsall:\=/!" ;
    endlocal
    type "%BOOST_SOURCE_DIR%\user-config-vs18.jam"
)

call "%BOOST_SOURCE_DIR%\bootstrap.bat" %boost_bootstrap_toolset% --with-libraries=filesystem,regex,system,url
if %ERRORLEVEL% NEQ 0 goto :error
b2 ^
    %boost_user_config%^
    -a^
    --prefix=%BOOST_INSTALL_DIR%^
    --exec-prefix=%BOOST_INSTALL_DIR%^
    --layout=system^
    --with-system --with-filesystem --with-regex --with-url^
    link=static runtime-link=%runtimelink% toolset=%boost_toolset% threading=multi address-model=%bitness% variant=%variant% runtime-debugging=%debugging%^
    cflags="/Z7 /ZH:SHA_256 /guard:cf /Qspectre /sdl" cxxflags="/std:c++17 /Z7 /ZH:SHA_256 /guard:cf /Qspectre /sdl"^
    install


if %ERRORLEVEL% NEQ 0 goto :error
::remove cmake files including local build path information
rd /S /Q %BOOST_INSTALL_DIR%\lib\cmake

cd "%currdir%"

echo === archiving the library
call "%scriptdir%utils.bat" :zip_file boost %boost_version%
if %ERRORLEVEL% NEQ 0 goto :error

goto :success

:success
exit /b 0

:error
cd "%currdir%"
exit /b 1
