# Sets Eden qt-config.ini keys (and clears their "use default" flag): setcfg.py key=value ...
import os, re, sys

path = os.path.expandvars(r"%APPDATA%\eden\config\qt-config.ini")
text = open(path, encoding="utf-8").read()
for assignment in sys.argv[1:]:
    key, value = assignment.split("=", 1)
    text = re.sub(rf"^{re.escape(key)}\\default=.*$", f"{key}\\\\default=false", text, flags=re.M)
    text = re.sub(rf"^{re.escape(key)}=.*$", lambda _: f"{key}={value}", text, flags=re.M)
open(path, "w", encoding="utf-8").write(text)
for line in text.splitlines():
    if any(line.startswith(a.split("=", 1)[0]) for a in sys.argv[1:]):
        print(line)
