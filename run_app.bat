@echo off
chcp 65001 >nul
title Hesbet El Taqseet
cd /d "%~dp0"

rem ---- find Python (Anaconda first) ----
set "PY="
for %%P in ("%USERPROFILE%\anaconda3\python.exe" "%LOCALAPPDATA%\anaconda3\python.exe" "%ProgramData%\anaconda3\python.exe" "%USERPROFILE%\miniconda3\python.exe") do (
    if not defined PY if exist %%P set "PY=%%~P"
)
if not defined PY (
    where py >nul 2>nul && set "PY=py"
)
if not defined PY (
    where python >nul 2>nul && set "PY=python"
)
if not defined PY (
    echo Could not find Python or Anaconda on this computer.
    pause
    exit /b 1
)
echo Using Python: %PY%
echo.

rem ---- install libraries (only the first time) ----
"%PY%" -c "import streamlit, plotly, sqlalchemy, psycopg2" >nul 2>nul
if errorlevel 1 (
    echo Installing required libraries, this takes a few minutes the first time...
    "%PY%" -m pip install -r requirements.txt
    if errorlevel 1 (
        echo.
        echo Installing the libraries failed. Send a screenshot of this window.
        pause
        exit /b 1
    )
)

echo.
echo Starting the app... it will open in your browser.
echo Keep this window open while you use the app. Close it to stop the app.
echo.
"%PY%" -m streamlit run app.py
pause
