# 🏍️ Intercom by CowTeam

> Comunicación de voz en tiempo real para grupos de motociclistas — sin internet, sin router, sin límites.

[![Download APK](https://img.shields.io/badge/⬇️%20Descargar%20APK-última%20versión-00E5FF?style=for-the-badge)](https://github.com/NesperouDelmonico/Intercom_CowTeam/releases/latest)

---

## 📦 Descargas

### Última versión
| Versión | Descargas |
|---------|-------|
| Latest | Ver [Releases](https://github.com/NesperouDelmonico/Intercom_CowTeam/releases/latest) | 

### Historial de versiones
Todas las versiones anteriores están disponibles en la sección de [Releases](https://github.com/NesperouDelmonico/Intercom_CowTeam/releases) del repositorio, cada una con su APK correspondiente.

---

## 📐 Arquitectura

```
intercom_app/
├── android/
│   └── app/src/main/kotlin/com/example/intercom_app/
│       ├── AudioEngine.kt          # Captura y reproducción PCM16 a 16kHz
│       ├── CallForegroundService.kt # Servicio en segundo plano — orquesta todo
│       ├── EventBus.kt             # Singleton Kotlin → Flutter via EventChannel
│       ├── MainActivity.kt         # UI principal — bridge MethodChannel
│       ├── RoomEngine.kt           # Lógica de sala mesh ANNOUNCE
│       ├── SoundEngine.kt          # Sonidos de entrada/salida generados en código
│       ├── UdpEngine.kt            # Sockets UDP puertos 5560/5561/5562
│       └── WifiDirectService.kt    # Conexión WiFi Direct entre dispositivos
│
└── lib/
    ├── main.dart
    ├── models/
    │   ├── room_info.dart          # Modelo para buscador de salas
    │   └── room_state.dart         # Estado de sala — RoomStatus, RoomMember
    ├── providers/
    │   ├── room_provider.dart      # Notifier principal — lógica de sala en Dart
    │   └── settings_provider.dart  # Preferencias de usuario
    ├── screens/
    │   ├── group_screen.dart       # Pantalla de sala grupal
    │   ├── home_screen.dart        # Pantalla principal — conexión WiFi Direct
    │   └── settings_screen.dart    # Configuración de perfil y audio
    └── services/
        ├── native_bridge.dart      # MethodChannel + EventChannel → Kotlin
        ├── settings_service.dart   # Persistencia de configuración
        └── wifi_direct_service.dart # API WiFi Direct desde Flutter
```

### Puertos UDP
| Puerto | Uso |
|--------|-----|
| 5560 | Audio PCM16 |
| 5561 | Señalización (WHO, LEAVE, MUTED) |
| 5562 | Announce mesh (ANNOUNCE broadcast) |

### Protocolo ANNOUNCE
Cada dispositivo anuncia su presencia cada ~350ms:
```
ANNOUNCE:roomCode:myIp:myName:avatar:ip1,ip2,ip3
```
Sin coordinador fijo. Sin servidor central. Completamente descentralizado.

---

## 📱 Compatibilidad

### Android
| Versión | API | Soporte |
|---------|-----|---------|
| Android 8.0 Oreo | API 26 | ✅ Mínimo recomendado |
| Android 9.0 Pie | API 28 | ✅ Compatible |
| Android 10 | API 29 | ✅ Óptimo |
| Android 11+ | API 30+ | ✅ Óptimo |

> **Nota:** La funcionalidad completa (foreground service con micrófono) requiere Android 10+. En Android 8-9 puede haber limitaciones en segundo plano según el fabricante.

### iOS
| Versión | Soporte |
|---------|---------|
| iOS 16+ | 🔜 Próximamente |
| iOS 15 y anteriores | ❌ No compatible |

> **¿Por qué iOS no está disponible aún?** WiFi Direct (Wi-Fi P2P) no es accesible para apps de terceros en iOS. La versión iOS usará **Multipeer Connectivity** — la alternativa nativa de Apple para comunicación peer-to-peer sin internet.

---

## 🔧 Requisitos técnicos

- **WiFi Direct** habilitado en el dispositivo
- **Permiso de micrófono** concedido
- **Permiso de ubicación** (requerido por Android para WiFi Direct)
- Todos los dispositivos en el mismo grupo WiFi Direct

---

## 🚀 Próximas actualizaciones

### v2.0 — Soporte iOS
- [ ] Reescritura de capa de red usando **Multipeer Connectivity**
- [ ] AudioEngine nativo en Swift
- [ ] UI adaptada para iOS con SwiftUI bridge
- [ ] Compatibilidad cruzada Android ↔ iOS en la misma sala

### Mejoras generales planificadas
- [ ] PTT (Push to Talk) con botón de volumen físico
- [ ] Ícono de app definitivo
- [ ] Onboarding para nuevos usuarios
- [ ] Publicación en Google Play Store

---

## 🛠️ Stack tecnológico

- **Flutter 3.44+** — UI multiplataforma
- **Kotlin** — capa nativa Android (audio, red, servicio)
- **UDP** — transporte de audio en tiempo real
- **WiFi Direct (Wi-Fi P2P)** — red mesh sin router
- **Riverpod** — gestión de estado en Flutter

---

## 👥 Equipo

**CowTeam** — Desarrollado para motociclistas, por motociclistas. 🏍️