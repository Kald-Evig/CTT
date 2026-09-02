/// formato_fecha.dart — Formateo de fechas para la UI.
///
/// Fuente única de los tres formatos que estaban duplicados en varias pantallas.
/// Los formatos no compartidos (tiempo relativo "hace X", mes en español) viven
/// en su pantalla porque tienen un único consumidor.
library;

/// `dd/MM/yyyy HH:mm` en hora local. Para timestamps (createdAt, ediciones).
String fechaHora(DateTime dt) {
  final l = dt.toLocal();
  return '${_dd(l.day)}/${_dd(l.month)}/${l.year} ${_dd(l.hour)}:${_dd(l.minute)}';
}

/// `dd/MM/yyyy` en hora local. Para fechas sin hora (fecha límite, comentarios).
String fecha(DateTime dt) {
  final l = dt.toLocal();
  return '${_dd(l.day)}/${_dd(l.month)}/${l.year}';
}

/// `yyyy-MM-dd` (sin conversión de zona). Formato de contrato para payloads API.
String fechaIso(DateTime d) => '${d.year}-${_dd(d.month)}-${_dd(d.day)}';

String _dd(int n) => n.toString().padLeft(2, '0');
