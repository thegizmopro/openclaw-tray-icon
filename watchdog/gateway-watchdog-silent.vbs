Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\kenzo\.openclaw\workspace\ops\watchdogs\gateway-watchdog.ps1""", 0, False
