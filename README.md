# LiveTV

```
livetv/
├── supabase/schema.sql            # tablas + RLS + funciones (pegar en SQL Editor)
├── admin-panel/                   # panel web (index.html + config.js)
├── app/                           # app cliente Flutter (Android)
├── scripts/check_channels.py      # revisión de canales caídos
└── .github/workflows/
    ├── check-channels.yml         # revisión nocturna (cron)
    └── deploy-admin.yml           # publica /admin-panel en GitHub Pages
```

## 1. Supabase
1. Crea el proyecto. **Authentication → Providers → Google**: actívalo con tus credenciales de Google Cloud.
2. **Authentication → URL Configuration → Redirect URLs**: añade `io.supabase.livetv://login-callback/`
3. **Authentication → Users → Add user**: tu correo + contraseña (será el admin).
4. **SQL Editor**: pega y ejecuta `supabase/schema.sql`, y después:
   `insert into public.admins (email) values ('tu-correo@gmail.com');`
5. **Project Settings → API**: copia *URL*, *anon key* y *service_role key*.

## 2. Panel admin
- Edita `admin-panel/config.js` con la URL y la **anon key**.
- Sube el repo a GitHub → **Settings → Pages → Source: GitHub Actions**.
- Queda en `https://USUARIO.github.io/REPO/admin-panel/`.
- Flujo: el usuario entra con Google → aparece en *Usuarios* → *Generar código* → se lo envías → lo introduce en la app.

## 3. Revisión nocturna
**Settings → Secrets and variables → Actions**: `SUPABASE_URL` y `SUPABASE_SERVICE_KEY` (service_role).
Prueba manual: **Actions → Revisar canales → Run workflow**.
Un canal se desactiva tras 2 fallos seguidos y se reactiva solo si vuelve a responder. Si caen >60 % a la vez, no cambia nada (fallo de red del runner).

## 4. App (Flutter ≥ 3.22)
```bash
cd app
flutter create --platforms=android --org com.livetv .
rm -rf test
python3 tools/patch_android.py          # INTERNET, http, deep link
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu_anon_key
# release:
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Notas
- **Cifrado**: las URLs se guardan como `base64(nonce || AES-256-GCM)`. La clave está en `app_config.aes_key` y solo la leen usuarios activados y admin; se descifra en memoria. Protege ante filtraciones de la base de datos o accesos sin activar; no impide que un usuario activo con herramientas de depuración vea las URLs.
- **Calidad**: el motor de vídeo (mpv) no cambia de calidad automáticamente; por defecto reproduce la máxima y el usuario puede fijar otra desde el icono HD.
- Cambiar `aes_key` con canales ya cargados los deja ilegibles.
- La `service_role` solo va en los Secrets de GitHub, nunca en el panel ni en la app.
