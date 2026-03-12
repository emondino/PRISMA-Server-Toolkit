# PRISMA Server Toolkit

PRISMA (Panel de Recolección Inteligente de Sistemas y Monitoreo Automatizado) es una herramienta de administración y diagnóstico de servidores Windows desarrollada en PowerShell.

El objetivo de PRISMA es ofrecer a los administradores de sistemas una consola centralizada que permita realizar rápidamente tareas comunes de diagnóstico y operación sobre servidores remotos.

El toolkit está diseñado para entornos de producción donde es necesario obtener información rápidamente sin navegar múltiples consolas administrativas.

# Versión

PRISMA Server Toolkit v0.3

Esta versión incluye módulos para diagnóstico de sistema, administración de servicios, inspección de IIS, análisis de eventos y revisión de almacenamiento.

---

# Características

PRISMA permite consultar y administrar remotamente servidores Windows mediante PowerShell Remoting.

Actualmente incluye los siguientes módulos:

### Servicios
- Listar servicios
- Consultar estado
- Iniciar / detener / reiniciar servicios
- Manejo de dependencias

### Información del servidor
- Sistema operativo
- CPU
- Memoria
- Información básica del host

### Discos
- Espacio total
- Espacio libre
- Estado de discos

### Health Check
Chequeo rápido del estado de servicios críticos.

### Procesos
- Top procesos por CPU
- Top procesos por memoria
- Búsqueda de procesos
- Procesos con usuario asociado

### Red
- Configuración IP
- Puertos en escucha
- Asociación puerto → proceso
- Búsqueda de puerto específico

### Eventos
Consulta de logs de Windows:
- Errores de Application
- Errores de System
- Fallos de logon (EventID 4625)
- Búsqueda de eventos por texto

### IIS
Administración básica de App Pools:
- Listado de App Pools
- Consulta de estado
- Identidad del pool
- Iniciar App Pool
- Detener App Pool
- Reciclar App Pool

Sitios IIS

- Listar sitios
- Consultar sitio
- Iniciar sitio
- Detener sitio

IIS SSL Inspector
Permite inspeccionar los certificados HTTPS utilizados por IIS.
Muestra:

- Sitio
- Estado
- Binding
- CN del certificado
- Fecha de vencimiento
- Días restantes

Esto permite detectar rápidamente certificados próximos a expirar.

### Certificados
Consulta de certificados del store LocalMachine\My

Funciones disponibles:

- Listar certificados
- Buscar certificados por texto
- Detectar certificados próximos a vencer

### Storage
Análisis de uso de almacenamiento:

- Top carpetas por tamaño
- Top archivos por tamaño

Esto es útil para detectar:
- crecimiento de logs
- dumps
- archivos temporales
- consumo inesperado de disco

# Requisitos

- Windows Server
- PowerShell 5.1 o superior
- Permisos administrativos en el servidor objetivo
- Acceso remoto habilitado (WinRM) para consultas remotas

Para funcionalidades IIS se requiere:

- Módulo `WebAdministration`
- Servidor con IIS instalado
- PowerShell Remoting habilitado

Para habilitar remoting:

Enable-PSRemoting -Force

---

# Ejecución

Ejecutar el script principal en powershell

.\PRISMA-Server-Toolkit.ps1 SERVIDOR



---

# FILOSOFIA DEL PROYECTO

PRISMA fue creado con el objetivo de:

- simplificar diagnósticos en servidores de producción

- reducir tiempo de análisis de incidentes

- unificar herramientas administrativas comunes

- facilitar la operación diaria de los administradores de sistemas

La herramienta está pensada para evolucionar con nuevos módulos según las necesidades operativas
---

# Licencia

Proyecto experimental desarrollado con fines de automatización y administración de sistemas.

# Autor ERNESTO MONDINO

Proyecto en desarrollo.

