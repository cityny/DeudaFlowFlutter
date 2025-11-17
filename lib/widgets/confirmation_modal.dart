import 'package:flutter/material.dart';

// Estructura de datos simple para el resumen
class SummaryItem {
  final String label;
  final String value;
  final IconData? icon;

  SummaryItem({required this.label, required this.value, this.icon});
}

/// Muestra un modal de confirmación con un resumen de los datos.
///
/// El botón 'Confirmar' ejecuta la función [onConfirm] pasada.
/// El modal maneja su propio estado de carga para el botón de confirmación.
class ConfirmationModal extends StatefulWidget {
  final String title;
  final List<SummaryItem> summaryData;
  final Future<void> Function() onConfirm;

  const ConfirmationModal({
    super.key,
    required this.title,
    required this.summaryData,
    required this.onConfirm,
  });

  @override
  State<ConfirmationModal> createState() => _ConfirmationModalState();
}

class _ConfirmationModalState extends State<ConfirmationModal> {
  bool _isProcessing = false;

  Future<void> _handleConfirm() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. Ejecutar la lógica de guardado del formulario (delegada)
      await widget.onConfirm();
      // 2. Cerrar el modal indicando éxito
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Manejo básico de errores (la lógica interna de onConfirm debe manejar errores específicos)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen de Datos:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    ...widget.summaryData.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.icon != null)
                              Icon(item.icon,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary),
                            if (item.icon != null) const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '${item.label}:',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Text(item.value,
                                  textAlign: TextAlign.end),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 20),
                    const Text(
                      '¿Desea confirmar y guardar estos datos?',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Volver'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _handleConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Confirmar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}