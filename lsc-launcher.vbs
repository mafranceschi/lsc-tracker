Dim WshShell, bat
Set WshShell = CreateObject("WScript.Shell")
bat = Replace(WScript.ScriptFullName, "lsc-launcher.vbs", "lsc-start.bat")
WshShell.Run "cmd /c """ & bat & """", 0, False
