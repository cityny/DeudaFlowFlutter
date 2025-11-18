import '../utils/currency_utils.dart';
import 'package:flutter/material.dart';
import '../widgets/budgeto_colors.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../models/transaction.dart';
import '../providers/client_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/currency_provider.dart';

import 'package:intl/intl.dart';

/// Formatter para mostrar el monto con puntos de miles y coma decimal en tiempo real.
/// Ejemplo: 1234567,89 -> 1.234.567,89
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Permitir borrar todo
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    // Permitir solo números y una coma
    final reg = RegExp(r'^[0-9]{1,}(,[0-9]{0,2})? 0');
    final raw = newValue.text.replaceAll('.', '');
    // Si el usuario está escribiendo, no formatear hasta que sea válido
    if (!RegExp(r'^[0-9]+(,[0-9]{0,2})?$').hasMatch(raw)) {
      return oldValue;
    }
    final parts = raw.split(',');
    final intPart = parts[0];
    String formattedInt = NumberFormat(
      '#,###',
      'es',
    ).format(int.parse(intPart)).replaceAll(',', '.');
    String formatted = formattedInt;
    if (parts.length > 1) {
      String decimal = parts[1];
      if (decimal.length > 2) decimal = decimal.substring(0, 2);
      formatted += ',' + decimal;
    }
    // No forzar la coma y ceros hasta que el usuario termine
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AddGlobalTransactionModal extends StatelessWidget {
  final String userId;
  final Widget? child;
  const AddGlobalTransactionModal({
    super.key,
    required this.userId,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.of(context).size.height * 0.95,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: child ?? _GlobalTransactionForm(userId: userId),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GlobalTransactionForm extends StatefulWidget {
  final String userId;
  const _GlobalTransactionForm({required this.userId});

  @override
  State<_GlobalTransactionForm> createState() => _GlobalTransactionFormState();
}

class _GlobalTransactionFormState extends State<_GlobalTransactionForm> {
  final _amountController = TextEditingController();
  final _amountFocusNode = FocusNode();
  final _descriptionController = TextEditingController();
  final _thousandsFormatter = ThousandsFormatter();
  String? _type;
  String? _currencyCode;
  // FIX: Normalizar la fecha inicial a medianoche para evitar que la hora interfiera con el ordenamiento.
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  Client? _selectedClient;
  String? _error;
  bool _loading = false;
  final _rateController = TextEditingController();
  bool _rateFieldVisible = false;

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(() {
      if (!_amountFocusNode.hasFocus) {
        // Al perder el foco, si no hay decimales, agregar ',00'
        String raw = _amountController.text.replaceAll('.', '');
        if (raw.isEmpty) return;
        final parts = raw.split(',');
        String intPart = parts[0];
        String formattedInt = NumberFormat(
          '#,###',
          'es',
        ).format(int.parse(intPart)).replaceAll(',', '.');
        String formatted = formattedInt;
        if (parts.length > 1) {
          String decimal = parts[1];
          if (decimal.length > 2) decimal = decimal.substring(0, 2);
          formatted += ',' + decimal;
          if (decimal.length == 0)
            formatted += '00';
          else if (decimal.length == 1)
            formatted += '0';
        } else {
          formatted += ',00';
        }
        _amountController.text = formatted;
        _amountController.selection = TextSelection.collapsed(
          offset: formatted.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _amountFocusNode.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    void logError(String message) {
      debugPrint('[GlobalTransactionForm ERROR] $message');
    }

    if (_selectedClient == null) {
      setState(() {
        _error = 'Debes seleccionar un cliente';
        _loading = false;
      });
      logError('Debes seleccionar un cliente');
      return;
    }
    if (_type == null) {
      setState(() {
        _error = 'Debes seleccionar Deuda o Abono';
        _loading = false;
      });
      logError('Debes seleccionar Deuda o Abono');
      return;
    }
    if (_currencyCode == null || _currencyCode!.isEmpty) {
      setState(() {
        _error = 'Debes seleccionar una moneda';
        _loading = false;
      });
      logError('Debes seleccionar una moneda');
      return;
    }
    // Validar monto como string formateado
    final amountStr = _amountController.text;
    if (amountStr.isEmpty ||
        !RegExp(r'^\d{1,3}(\.\d{3})*(,\d{1,2})?$').hasMatch(amountStr)) {
      setState(() {
        _error = 'Monto inválido';
        _loading = false;
      });
      logError('Monto inválido');
      return;
    }
    // Convertir el string formateado a double para guardar en Transaction.amount
    final amountDouble = double.tryParse(
      amountStr.replaceAll('.', '').replaceAll(',', '.'),
    );
    if (amountDouble == null || amountDouble <= 0) {
      setState(() {
        _error = 'Monto inválido';
        _loading = false;
      });
      logError('Monto inválido');
      return;
    }
    final descText = _descriptionController.text.trim();
    if (descText.isEmpty) {
      setState(() {
        _error = 'Descripción obligatoria';
        _loading = false;
      });
      logError('Descripción obligatoria');
      return;
    }
    if (descText.length > 30) {
      setState(() {
        _error = 'La descripción no puede tener más de 30 caracteres';
        _loading = false;
      });
      logError('Descripción muy larga');
      return;
    }
    // Validar y guardar tasa solo si el campo está visible
    if (_rateFieldVisible) {
      final rateText = _rateController.text.replaceAll(',', '.');
      final rateValue = double.tryParse(rateText);
      if (rateValue == null || rateValue <= 0) {
        setState(() {
          _error = 'Ingrese una tasa válida';
          _loading = false;
        });
        logError('Tasa inválida');
        return;
      } else {
        final currencyProvider = Provider.of<CurrencyProvider>(
          context,
          listen: false,
        );
        // Agregar la moneda manualmente si no existe
        if (_currencyCode != null) {
          final codeUC = _currencyCode!.toUpperCase();
          if (!currencyProvider.availableCurrencies.contains(codeUC)) {
            currencyProvider.addManualCurrency(codeUC);
          }
          currencyProvider.setRateForCurrency(codeUC, rateValue);
        }
      }
    }

    // Se eliminó la validación de límite de monedas no-USD. Ahora se pueden crear transacciones con cualquier cantidad de monedas diferentes a USD.

    // --- Iniciar Modal de Confirmación ---
    if (!mounted) {
      setState(() => _loading = false);
      return;
    }

    final confirmed = await _showConfirmationModal(
      context: context,
      type: _type!,
      amountStr: amountStr, // Usar el string formateado para el display
      currencyCode: _currencyCode!,
      clientName: _selectedClient!.name,
      description: descText, // Usar el texto recortado y validado
      date: _selectedDate,
    );

    if (confirmed != true) {
      // El usuario canceló la operación
      setState(() {
        _loading = false;
      });
      return;
    }
    // --- Fin Modal de Confirmación ---

    try {
      final now = DateTime.now();
      String randomLetters(int n) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        final rand = DateTime.now().microsecondsSinceEpoch;
        return List.generate(
          n,
          (i) => chars[(rand >> (i * 5)) % chars.length],
        ).join();
      }

      final localId =
          randomLetters(2) + DateTime.now().millisecondsSinceEpoch.toString();
      // --- Cálculo de anchorUsdValue ---
      double? anchorUsdValue;
      final currencyProvider = Provider.of<CurrencyProvider>(
        context,
        listen: false,
      );
      double? rate;
      double? amount = amountDouble;
      if (_currencyCode != null) {
        // Usar el método robusto del provider para obtener la tasa
        rate = currencyProvider.getRateFor(_currencyCode!);
        if (_currencyCode!.toUpperCase() == 'USD') {
          anchorUsdValue = CurrencyUtils.normalizeAnchorUsd(amount);
          debugPrint(
            '\u001b[41m[GLOBAL_FORM][CALC] amount=$amountStr, currency=USD, anchorUsdValue=$anchorUsdValue\u001b[0m',
          );
        } else if (rate != null && rate > 0) {
          anchorUsdValue = CurrencyUtils.normalizeAnchorUsd(amount / rate);
          debugPrint(
            '\u001b[41m[GLOBAL_FORM][CALC] amount=$amountStr, currency=$_currencyCode, rate=$rate, anchorUsdValue=$anchorUsdValue\u001b[0m',
          );
        } else {
          setState(() {
            _error = 'No existe una tasa válida para la moneda seleccionada.';
            _loading = false;
          });
          logError('No rate for currency=$_currencyCode');
          return;
        }
      } else {
        anchorUsdValue = null;
      }
      // FIX: Asegurar que la fecha de la transacción siempre se guarde sin la hora (a medianoche).
      // La hora real de creación se guarda en `createdAt`. Esto es crucial para la consistencia del ordenamiento.
      final normalizedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      /// Guardar el monto como string formateado en la transacción
      final transaction = Transaction(
        id: localId, // id local único
        clientId: _selectedClient!.id,
        userId: widget.userId,
        type: _type!,
        amount: amountDouble, // <--- double para cálculos y backend
        description: _descriptionController.text,
        date: normalizedDate,
        createdAt: now,
        localId: localId,
        currencyCode: _currencyCode!, // safe because already validated
        anchorUsdValue: anchorUsdValue,
      );
      debugPrint(
        '\u001b[41m[GLOBAL_FORM][SAVE] id=$localId, amount=$amount, currency=$_currencyCode, anchorUsdValue=$anchorUsdValue\u001b[0m',
      );
      // Guardar usando TransactionProvider
      final txProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );
      await txProvider.addTransaction(
        transaction,
        widget.userId,
        _selectedClient!.id,
      );
      // --- FIX: Recargar clientes Y transacciones para reconstruir la lista ---
      // Es crucial recargar ambas listas para que la UI refleje el nuevo
      // estado inmediatamente y con el orden correcto. La lista de transacciones
      // necesita ser reconstruida para mostrar el nuevo ítem.
      if (!mounted) return;
      final clientProvider = Provider.of<ClientProvider>(
        context,
        listen: false,
      );
      // Se recargan las transacciones para que la nueva aparezca inmediatamente.
      await txProvider.loadTransactions(widget.userId);
      // Se recargan los clientes para actualizar los saldos.
      await clientProvider.loadClients(widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transacción guardada correctamente')),
        );
        Future.delayed(const Duration(milliseconds: 350), () {
          // ignore: use_build_context_synchronously
          if (Navigator.of(context).canPop()) {
            // ignore: use_build_context_synchronously
            Navigator.of(context).pop();
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error inesperado: $e';
        _loading = false;
      });
      logError('Error inesperado: $e');
      return;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // Nuevo método para mostrar el modal de confirmación con estilos corregidos
  Future<bool?> _showConfirmationModal({
    required BuildContext context,
    required String type,
    required String amountStr,
    required String currencyCode,
    required String clientName,
    required String description,
    required DateTime date,
  }) async {
    final formattedDate =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmar Transacción'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Detalles de la transacción:',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                // 🚨 CAMBIO AQUÍ: Uso de Text.rich para negrita solo en la etiqueta
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Tipo: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: type == 'debt' ? 'Deuda' : 'Abono'),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Cliente: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: clientName),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Monto: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: '$amountStr $currencyCode'),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Fecha: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: formattedDate),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Descripción: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: description),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '¿Desea guardar esta transacción?',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  // ignore: use_build_context_synchronously
  // Se protege el uso de context tras el async gap con mounted
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ClientProvider>().clients;
    final colorScheme = Theme.of(context).colorScheme;
    final symbol = "";
    final currencyProvider = Provider.of<CurrencyProvider>(context);
    final availableCurrencies = currencyProvider.availableCurrencies;
    final rate = _currencyCode != null
        ? currencyProvider.getRateFor(_currencyCode!)
        : null;
    final rateMissing =
        _currencyCode != null &&
        _currencyCode!.toUpperCase() != 'USD' &&
        (rate == null || rate == 0);
    _rateFieldVisible = rateMissing;
    final rateValid =
        double.tryParse(_rateController.text.replaceAll(',', '.')) != null &&
        double.parse(_rateController.text.replaceAll(',', '.')) > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Título principal (antes subtítulo contextual)
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            'Agregar Transacción para',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
        // Campo Cliente (debajo del subtítulo contextual)
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Autocomplete<Client>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return clients;
              }
              return clients.where(
                (Client c) =>
                    c.name.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ) ||
                    (c.address?.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ) ??
                        false) ||
                    (c.phone?.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ) ??
                        false),
              );
            },
            displayStringForOption: (Client c) => c.name,
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  return SizedBox(
                    height: 40, // Igual que los ítems del menú
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(
                        fontSize: 16,
                      ), // Igual que los ítems
                      decoration: const InputDecoration(
                        labelText: 'Buscar o seleccionar cliente',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  );
                },
            onSelected: (Client c) {
              setState(() => _selectedClient = c);
              FocusScope.of(
                context,
              ).unfocus(); // Oculta el teclado al seleccionar un cliente
            },
            optionsViewBuilder: (context, onSelected, options) {
              // Se crea un ScrollController para vincularlo con el Scrollbar y el ListView
              final scrollController = ScrollController();
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (options.length * 44.0).clamp(44.0, 200.0),
                    ),
                    // Se añade un Scrollbar explícito con el controlador
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller:
                            scrollController, // Se asigna el controlador a la lista
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final Client c = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(c),
                            child: Container(
                              height:
                                  33, // Menos alto, menos espacio entre ítems
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              alignment: Alignment.centerLeft,
                              // Se reemplaza la Row por un único Text para mostrar solo el nombre
                              child: Text(
                                c.name,
                                style: const TextStyle(fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Icono + texto (estado/tipo) removido por solicitud
        const SizedBox(height: 10),
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: kSliderContainerBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.primary, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleTypeButton(
                  selected: _type == 'debt',
                  icon: Icons.trending_down,
                  label: 'Deuda',
                  color: Colors.red,
                  onTap: () => setState(() => _type = 'debt'),
                ),
                SizedBox(width: 45), // Espacio igual que en client_form
                _ToggleTypeButton(
                  selected: _type == 'payment',
                  icon: Icons.trending_up,
                  label: 'Abono',
                  color: Colors.green,
                  onTap: () => setState(() => _type = 'payment'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Campo monto
        TextField(
          controller: _amountController,
          decoration: InputDecoration(
            labelText: 'Monto',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Text(
                symbol,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            isDense: true,
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          focusNode: _amountFocusNode,
          inputFormatters: [_thousandsFormatter],
        ),
        const SizedBox(height: 7),
        // Fila de selector de moneda + botón agregar
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _currencyCode,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Moneda',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: availableCurrencies
                    .map(
                      (code) =>
                          DropdownMenuItem(value: code, child: Text(code)),
                    )
                    .toList(),
                onChanged: (code) {
                  setState(() {
                    _currencyCode = code;
                    _rateController.text = '';
                  });
                },
                dropdownColor: Colors.white,
                menuMaxHeight: 180,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 48,
              child: IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.indigo,
                  size: 24,
                ),
                tooltip: 'Agregar moneda',
                onPressed: () async {
                  String? newCode = await showDialog<String>(
                    context: context,
                    builder: (ctx) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        title: const Text('Agregar moneda'),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: 'Código (ej: EUR)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          maxLength: 11,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              String code = controller.text.trim();
                              if (code.isEmpty) {
                                Navigator.of(ctx).pop();
                                return;
                              }
                              // Solo primera letra mayúscula, resto minúscula
                              code =
                                  code.substring(0, 1).toUpperCase() +
                                  (code.length > 1
                                      ? code.substring(1).toLowerCase()
                                      : '');
                              if (code == 'USD' ||
                                  availableCurrencies.contains(code)) {
                                Navigator.of(ctx).pop();
                                return;
                              }
                              Navigator.of(ctx).pop(code);
                            },
                            child: const Text('Agregar'),
                          ),
                        ],
                      );
                    },
                  );
                  if (newCode != null &&
                      newCode.isNotEmpty &&
                      newCode != 'USD' &&
                      !availableCurrencies.contains(newCode)) {
                    // Agregar la moneda al provider
                    final currencyProvider = Provider.of<CurrencyProvider>(
                      context,
                      listen: false,
                    );
                    currencyProvider.addManualCurrency(newCode);

                    // Buscar la versión realmente insertada (puede cambiar el casing)
                    String selectedValue = newCode;
                    for (final c in currencyProvider.availableCurrencies) {
                      if (c.toLowerCase() == newCode.toLowerCase()) {
                        selectedValue = c;
                        break;
                      }
                    }
                    setState(() {
                      _currencyCode = selectedValue;
                      _rateController.text = '';
                    });
                  }
                },
              ),
            ),
          ],
        ),
        if (_rateFieldVisible)
          Padding(
            padding: const EdgeInsets.only(top: 10.0, bottom: 4.0),
            child: TextField(
              controller: _rateController,
              decoration: InputDecoration(
                labelText: 'Tasa ${_currencyCode?.toUpperCase() ?? ''} a USD',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.attach_money_rounded),
                errorText: _rateController.text.isNotEmpty && !rateValid
                    ? 'Ingrese una tasa válida (> 0)'
                    : null,
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickDate,
          child: AbsorbPointer(
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Fecha',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: Icon(Icons.event),
                isDense: true,
              ),
              controller: TextEditingController(
                text:
                    '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Campo descripción con contador visual igual a transaction_form
        Stack(
          children: [
            TextField(
              controller: _descriptionController,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: Icon(Icons.description),
                isDense: true,
                counterText: '', // Oculta el contador por defecto
              ),
              maxLines: 2,
              onChanged: (_) => setState(() {}),
            ),
            Positioned(
              right: 12,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                child: Builder(
                  builder: (context) {
                    final currentLength = _descriptionController.text.length;
                    final maxLength = 30;
                    final remaining = maxLength - currentLength;
                    Color color;
                    if (remaining <= 5) {
                      color = Colors.red;
                    } else if (remaining <= 10) {
                      color = Colors.orange;
                    } else {
                      color = Colors.grey;
                    }
                    return Text(
                      '$currentLength/$maxLength',
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: _error!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Error copiado al portapapeles'),
                  ),
                );
              },
              child: SelectableText(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(_type == 'debt' ? Icons.save : Icons.check_circle),
            label: Text(
              _loading
                  ? 'Guardando...'
                  : (_type == 'debt' ? 'Guardar Deuda' : 'Guardar Abono'),
            ),
            onPressed: _loading
                ? null
                : () async {
                    await _save();
                  },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              side: BorderSide(color: colorScheme.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: const Icon(Icons.close),
            label: const Text('Cerrar'),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ToggleTypeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ToggleTypeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final baseColor = color;
    // .withValues() espera double? para cada canal, así que convertimos a double
    // .withOpacity está deprecado, .withValues es la alternativa, pero para colores simples alpha puede usarse Color.fromARGB
    final selectedColor = Color.fromARGB(
      (0.13 * 255).round(),
      ((baseColor.red * 255.0).round() & 0xff),
      ((baseColor.green * 255.0).round() & 0xff),
      ((baseColor.blue * 255.0).round() & 0xff),
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? baseColor : Colors.transparent,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: baseColor, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: baseColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}