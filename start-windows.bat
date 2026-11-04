@echo off
rem Phone Detox: double-click to start the app in your browser.
rem Phone Detox: doppio clic per avviare l app nel browser.
cd /d "%~dp0"
where py >nul 2>nul && (py -3 ui\phone_detox_ui.py & goto end)
python --version >nul 2>nul && (python ui\phone_detox_ui.py & goto end)
echo.
echo Python 3 is missing. / Manca Python 3.
echo Install it from https://www.python.org/downloads/ and tick "Add python.exe to PATH".
echo Installalo da https://www.python.org/downloads/ e spunta "Add python.exe to PATH".
start https://www.python.org/downloads/
:end
pause
