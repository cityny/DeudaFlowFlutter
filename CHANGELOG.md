# CHANGELOG

Todas las novedades, mejoras y correcciones planeadas y lanzadas para Deuda Flow.

## [1.0.8+8] - 2025-09-18

### Novedades (versión 1.0.8+8)
- Ahora los balances de los clientes se actualizan correctamente en la nube después de sincronizar los movimientos, incluso si los registraste sin conexión.
- El diálogo de "Conflicto de balances" ya no se sale de pantalla en móviles y tiene un único botón "Forzar sincronización" que muestra el progreso.
- Menos mensajes técnicos en la consola relacionados con los anuncios: la app muestra menos ruido en los logs.
- Pequeñas mejoras en la actualización de datos y estabilidad después de sincronizar.

## [1.0.7] - 2025-09-13

### Cambios destacados (para todos)
- Inicio de la app más rápido y mantiene tu sesión iniciada.
- Funciona mejor sin internet: puedes seguir usando tus datos y se sincronizan luego.
- Pantalla inicial (splash) más fluida y sin parpadeos.
- Formularios de clientes y transacciones más claros (descripción y saldo inicial mejor guiados).
- Recibos PDF con formato de montos más limpio.
- Varias correcciones menores de estabilidad y datos duplicados.



## [1.0.3] - 2025-08-25
- Selección automática de la última moneda nueva agregada en los chips de moneda.
- Contador visual de caracteres en el campo "descripción" de los formularios de transacción, con cambio de color según los caracteres restantes.
- Mejoras en validación y sincronización de monedas/tasas.
- Segundo diálogo de confirmación al intentar eliminar todas las transacciones o todos los clientes, para evitar eliminaciones accidentales.
-Agrega nombre y telefono del cliente al selecciona de forma automatica
- Campo de tasa ahora readOnly; edición por diálogo y persistencia inmediata.
- Corrección en cálculo/estadísticas y en la visualización de montos usando `anchorUsdValue`.
- `TransactionCard` muestra montos correctamente convertidos; etiqueta no engañosa.
- Se eliminó la fila icono+texto en el modal de añadir transacción.
- PDFs: mejor formato de montos y se quitaron los códigos de moneda en las celdas de tabla.
- Mensaje del snackBar al cerrar sesión cambiado a "Cierre de sesión exitoso".
- Test actualizado para evitar inicializar Hive en unit tests rápidos.


## [1.0.2] - 2025-08-24
- Versión inicial publicada en Google Play.
- Control de deudas y pagos sin conexión y con sincronización online.
- Soporte para múltiples monedas y tasas de cambio personalizables.
- Generación de recibos individuales y generales en PDF.
- Gestión de clientes y transacciones.


