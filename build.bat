@ECHO OFF
::******************************************************
:: File: build.bat
::
:: Description: This build script is used to generate
::      synergy configuration, execute a build, and 
::      run unit tests.  This can be used for command
::      line builds for developers or for continuous 
::      integration builds.
::
::******************************************************
:: Copyright 2019 - Third Pole Therapeutics
::******************************************************
REM Default Software Path Locations
set SSP_INSTALL_LOC=C:\Renesas\Synergy\ssc_v7.5.1_ssp_v1.7.0\eclipse
set IAR_INSTALL_LOC="C:\Program Files (x86)\IAR Systems\Embedded Workbench for Synergy 8.23.3\common\bin"
set PYTHON_LOC=C:\Python37
set RUBY_LOC=C:\Ruby25-x64
REM Default Parameters - Generate Configuration, Debug Build for MCB Hardware
set SYNERGY=1
set BUILD=1
set UNITTEST=0
set RANDOMUT=0
set COVERAGE=0
set COMPLEXITY=0
set PCLINT=0
set HARDWARE=mcb
set TYPE=Debug
set TYPEDIR=Debug
ECHO *** Dealing with Arguments: %* ***
:ARGUMENTLOOP
if not "%1"=="" (
    if /I "%1"=="all" (
        set SYNERGY=1
        set BUILD=1
        set UNITTEST=1
        set COVERAGE=1
        set COMPLEXITY=1
        set PCLINT=1
    )
    if /I "%1"=="config" (
        set SYNERGY=1
        set BUILD=0
        set UNITTEST=0
    )
    if /I "%1"=="buildonly" (
        set SYNERGY=0
        set BUILD=1
        set UNITTEST=0
    )
    if /I "%1"=="build" (
        set SYNERGY=1
        set BUILD=1
        set UNITTEST=0
    )
    if /I "%1"=="unittest" (
        set SYNERGY=1
        set BUILD=0
        set UNITTEST=1
    )
    if /I "%1"=="utonly" (
        set SYNERGY=0
        set BUILD=0
        set UNITTEST=1
    )
    if /I "%1"=="randomut" (
        set SYNERGY=1
        set BUILD=0
        set RANDOMUT=1
    )
    if /I "%1"=="coverage" (
        set COVERAGE=1
    )
    if /I "%1"=="pmccabe" (
        set SYNERGY=0
        set BUILD=0
        set UNITTEST=0
        set COMPLEXITY=1
    )
    if /I "%1"=="pclint" (
        set SYNERGY=0
        set BUILD=0
        set UNITTEST=0
        set COMPLEXITY=0
        set PCLINT=1
    )
    if /I "%1"=="hardware" (
        set HARDWARE=%2
        shift
    )
    if /I "%1"=="type" (
        if "%2"=="debug" (
                set TYPE=Debug
                set TYPEDIR=Debug
        )
        if "%2"=="release" (
                set TYPE=Release
                set TYPEDIR=Release
        )
        if "%2"=="fake" (
                set TYPE=FakePeripherals
                set TYPEDIR=FakePeripherals
        )
        shift
    )
    if /I "%1"=="help" (
        goto :PRINTARGSHELP	
    )
    shift
    GOTO :ARGUMENTLOOP
)
:DONEARGS
if "%HARDWARE%"=="pe-hmi1" (
    set TYPE=PE_FP
    set TYPEDIR=PE_FP
)

ECHO *** Setting Up Build Workspace ***
set CURRENTPATH=%CD%
IF NOT DEFINED WORKSPACE GOTO SetupLocalBuild
ECHO --- WORKSPACE DEFINED - JENKINS BUILD. ---
set JENKINS=1
set REPOLOC=%WORKSPACE%
IF NOT DEFINED BUILD_NUMBER GOTO EnvironmentError
IF NOT DEFINED SYSTEM_TOOLS_REPO GOTO EnvironmentError
GOTO BuildSetupComplete

:SetupLocalBuild
ECHO --- WORKSPACE NOT DEFINED - LOCAL BUILD. ---
set JENKINS=0
set REPOLOC=%CD%

:BuildSetupComplete
ECHO *** GitHub Repository Location: %REPOLOC% ***

:SetupHardware
ECHO *** Setting Up Hardware Configuration ***
IF NOT "%HARDWARE%"=="mcb" (
    IF NOT EXIST "%REPOLOC%\AcuteDevice\configuration-%HARDWARE%.xml" (
        GOTO HardwareSetupError
    )
    CD %REPOLOC%
    IF NOT EXIST "%REPOLOC%\AcuteDevice\configuration-mcb.xml" (
        ECHO *** Backing Up MCB Hardware Configuration for %HARDWARE% ***
        copy "%REPOLOC%\AcuteDevice\configuration.xml" "%REPOLOC%\AcuteDevice\configuration-mcb.xml"
    )
    ECHO *** Copying Hardware Configuration for %HARDWARE% ***
    copy "%REPOLOC%\AcuteDevice\configuration-%HARDWARE%.xml" "%REPOLOC%\AcuteDevice\configuration.xml"
) 
IF "%HARDWARE%"=="mcb" (
    IF EXIST "%REPOLOC%\AcuteDevice\configuration-%HARDWARE%.xml" (
        ECHO *** Restoring Hardware Configuration for %HARDWARE% ***
        copy "%REPOLOC%\AcuteDevice\configuration-%HARDWARE%.xml" "%REPOLOC%\AcuteDevice\configuration.xml"
    )
)

IF %SYNERGY% EQU 1 (
    ECHO *** Generating Synergy Configuration ***
    CD %SSP_INSTALL_LOC%
    synergy_standalone.exe --compiler IAR --generate "%REPOLOC%\AcuteDevice\configuration.xml"
    if %ERRORLEVEL% NEQ 0 GOTO ReportSSError
    CD %REPOLOC%
)

IF %BUILD% EQU 1 (
    ECHO *** Building UCM ***
    CD %REPOLOC%
    IF %JENKINS% EQU 1 (
        REM generate version headerfile.
        %PYTHON_LOC%\python.exe %SYSTEM_TOOLS_REPO%\generate_include.py Include\version.h
        if %ERRORLEVEL% NEQ 0 GOTO ReportGenVerError
    )
    REM Executing Build command
    %IAR_INSTALL_LOC%\IarBuild.exe "%REPOLOC%\AcuteDevice\3P-001_UCM_Software.ewp" -build "%TYPE%" -varfile renesas.custom_argvars -parallel 4
    if %ERRORLEVEL% NEQ 0 GOTO ReportIARError

    IF %JENKINS% EQU 1 (
        REM create SHA-256 hash for output file and store in same location as output file.
        %PYTHON_LOC%\python.exe %SYSTEM_TOOLS_REPO%\generate_sha2.py AcuteDevice\%TYPEDIR%\Exe\3P-001_UCM_Software.out 
        if %ERRORLEVEL% NEQ 0 GOTO ReportGenCRCError
        IF EXIST "%REPOLOC%\AcuteDevice\%TYPEDIR%\Exe\3P-001_UCM_Software.srec" (
            %PYTHON_LOC%\python.exe %SYSTEM_TOOLS_REPO%\generate_sha2.py AcuteDevice\%TYPEDIR%\Exe\3P-001_UCM_Software.srec 
            if %ERRORLEVEL% NEQ 0 GOTO ReportGenCRCError
        )
    )
)

IF %UNITTEST% EQU 1 (
    ECHO *** Executing UnitTests ***
    CD %REPOLOC%\UnityUnitTests
    %RUBY_LOC%\bin\ceedling.bat
    if %ERRORLEVEL% NEQ 0 GOTO ReportUTError
    if %COVERAGE% EQU 1 (
        ECHO *** Executing UnitTest HTML Coverage Report ***
        %RUBY_LOC%\bin\ceedling.bat gcov:all utils:gcov
        ECHO *** Executing UnitTest Cobertura Coverage Report ***
        %PYTHON_LOC%\python.exe C:\Python27\Scripts\gcovr -p -b -e "\||^vendor.*|^build.*|^test.|^lib." --xml -r . -o "build/artifacts/gcov/coverage.xml"
    )
    CD %REPOLOC%
)

IF %RANDOMUT% EQU 1 (
    ECHO *** Executing Random UnitTests ***
    CD %REPOLOC%\UnityUnitTests
    if %COVERAGE% EQU 1 (
        ECHO *** with coverage ***
        %PYTHON_LOC%\python.exe %SYSTEM_TOOLS_REPO%\ceedling_random_test_cases.py -c
        %PYTHON_LOC%\python.exe C:\Python27\Scripts\gcovr -p -b -e "\||^vendor.*|^build.*|^test.|^lib." --xml -r . -o "build/artifacts/gcov/coverage.xml"
    ) else (
        ECHO *** without coverage ***
        %PYTHON_LOC%\python.exe %SYSTEM_TOOLS_REPO%\ceedling_random_test_cases.py
    )
    if %ERRORLEVEL% NEQ 0 GOTO ReportRandUTError
    CD %REPOLOC%
)

IF %COMPLEXITY% EQU 1 (
    ECHO *** Executing pmccabe Complexity Algorithm ***
    CD %REPOLOC%
    %PYTHON_LOC%\python.exe %SYSTEM_TOOLS_REPO%\pmccabe.py
    if %ERRORLEVEL% NEQ 0 GOTO ReportMccabeError
)

IF %PCLINT% EQU 1 (
    ECHO *** Executing PC-Lint Analysis ***
    CD %REPOLOC%\lint
    pc-lint-jenkins.bat %REPOLOC%\AcuteDevice "C:\Program Files (x86)\IAR Systems\Embedded Workbench for Synergy 8.23.1" > pc-lint-ouput.log
    if %ERRORLEVEL% NEQ 0 GOTO ReportPcLintError
    CD %REPOLOC%
)

GOTO Done

:EnvironmentError
ECHO !!! Build Environment Error !!!
EXIT /B 1

:HardwareSetupError
ECHO !!! Invalid Hardware Configuration Parameter %HARDWARE%. !!!
exit /B 1

:ReportSSError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Failed to Gererate Synergy Configuration. Err:%EXITCODE% !!!
CD %CURRENTDIR%
exit /B %EXITCODE%

:ReportGenVerError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Failed to Generate Version Err:%EXITCODE% !!!
exit /B %EXITCODE%

:ReportIARError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Failed to Build UCM Software. Err:%EXITCODE% !!!
exit /B %EXITCODE%

:ReportGenCRCError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Error Generating CRC32. Err:%EXITCODE% !!!
exit /B %EXITCODE%

:ReportUTError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Failed to Execute Unit Tests. Err:%EXITCODE% !!!
exit /B %EXITCODE%

:ReportRandUTError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Error Executing Random Unit Tests. Err:%EXITCODE% !!!
ECHO !!! Random Unit Tests not deleted in workspace. !!!
exit /B %EXITCODE%

:ReportMccabeError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Failed to Execute pmccabe Complexity Analysis. Err:%EXITCODE% !!!
exit /B %EXITCODE%

:ReportPcLintError
set EXITCODE=%ERRORLEVEL%
ECHO !!! Failed to Execute PC-Lint Static Analysis. Err:%EXITCODE% !!!
exit /B %EXITCODE%

:PRINTARGSHELP
ECHO build.bat
ECHO     This script peforms build commands for this repository and branch.
ECHO     Default Options - generate synergy configuration and build
ECHO     Parameters:
ECHO         all - generate synergy configuration, build, and run unit tests.
ECHO         config - generate synergy configuration.
ECHO         build - generate synergy configuration and build.
ECHO         unittest - generate synergy configuration and execute unit tests.
ECHO         buildonly - Build UCM.
ECHO         utonly - execute unit tests.
ECHO         randomut - execute random unit tests.
ECHO         coverage - add gcov report to unit test ouput.
ECHO         pmccabe - execute complexity script.
ECHO         pclint - execute PC-Lint Static Analysis.
ECHO         hardware - hardware.  defaults to mcb. choices:mcb, pe-hmi1
ECHO         type - build type.  defaults to debug. choices:debug, release, fake
GOTO Done

:Done
ECHO *** Done Executing build.bat ***
