#!/usr/bin/env python3
"""Ajusta AndroidManifest.xml: permiso INTERNET, tráfico http y deep link del login. Idempotente."""
import pathlib
import re
import sys

p = pathlib.Path(__file__).resolve().parents[1] / "android/app/src/main/AndroidManifest.xml"
if not p.exists():
    sys.exit("Ejecuta antes: flutter create --platforms=android --org com.livetv .")

x = p.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in x:
    x = re.sub(r"(<manifest[^>]*>)", r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>', x, count=1)

if "usesCleartextTraffic" not in x:
    x = x.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)

if "login-callback" not in x:
    intent = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="io.supabase.livetv" android:host="login-callback"/>
            </intent-filter>
        """
    x = x.replace("</activity>", intent + "</activity>", 1)

p.write_text(x, encoding="utf-8")
print("AndroidManifest.xml listo")
