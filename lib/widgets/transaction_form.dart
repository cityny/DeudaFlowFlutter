import '../utils/currency_utils.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../widgets/budgeto_colors.dart';
import 'package:flutter/services.dart';
import '../models/transaction.dart';
import '../models/client.dart';
import '../providers/currency_provider.dart';
import 'package:provider/provider.dart';
// import '../utils/currency_utils.dart';
// 🚨 NUEVA IMPORTACIÓN DEL MODAL DE CONFIRMACIÓN
import 'confirmation_modal.dart';

// --- Formateador y función de miles a nivel superior ---
final NumberFormat _numberFormat = NumberFormat.currency(
  locale: 'es',
  symbol: '',
  decimalDigits: 2,
);
// Formato solo para agrupación de miles sin forzar decimales
final NumberFormat _groupFormat = NumberFormat.decimalPattern('es');

String formatThousands(String value) {
  value = value.replaceAll('.', '').replaceAll(',', '.');
  final number = double.tryParse(value);
  if (number == null) return '';
  return _numberFormat.format(number).replaceAll('\u0000A0', '');
}

class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Permitir vacío
    String raw = newValue.text;
    if (raw.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Conservar solo dígitos y una coma decimal
    // Normalizamos removiendo puntos de miles existentes
    raw = raw.replaceAll('.', '');
    // Si hay más de una coma, conservar la primera
    final firstComma = raw.indexOf(',');
    String intPart;
    String decPart = '';
    if (firstComma >= 0) {
      intPart = raw.substring(0, firstComma).replaceAll(RegExp(r'[^0-9]'), '');
      decPart = raw.substring(firstComma + 1).replaceAll(RegExp(r'[^0-9]'), '');
      if (decPart.length > 2) decPart = decPart.substring(0, 2);
    } else {
      intPart = raw.replaceAll(RegExp(r'[^0-9]'), '');
    }

    // Evitar que se quede vacío el entero (permitimos '0' temporalmente)
    if (intPart.isEmpty) intPart = '0';

    // Formatear miles solo para la parte entera
    String groupedInt;
    try {
      groupedInt = _groupFormat.format(int.parse(intPart));
    } catch (_) {
      groupedInt = intPart; // fallback
    }

    String formatted = groupedInt;
    if (firstComma >= 0) {
      // El usuario escribió coma, mantenerla y decimales sin padding
      formatted = '$groupedInt,' + decPart;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class TransactionForm extends StatefulWidget {
  final void Function(Transaction)? onSave;
  final String userId;
  final VoidCallback? onClose;
  final Client? initialClient;
  const TransactionForm({
    super.key,
    required this.userId,
    this.onSave,
    this.onClose,
    this.initialClient,
  });

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  final _descriptionController = TextEditingController();
  static const int _descriptionMaxLength = 32;
  String? _type; // No seleccionado por defecto
  String? _currencyCode;
  DateTime _selectedDate = DateTime.now();
  Client? _selectedClient;
  String? _error;
  bool _loading = false;

  final _rateController = TextEditingController(); // NUEVO
  bool _rateFieldVisible = false; // NUEVO

  // Reemplaza esto por la obtención real de clientes desde Provider o base de datos
  final List<Client> clients = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialClient != null) {
      _selectedClient = widget.initialClient;
    }
    _amountFocusNode.addListener(_onAmountFocusChange);
  }

  @override
  void dispose() {
    _amountFocusNode.removeListener(_onAmountFocusChange);
    _amountFocusNode.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _onAmountFocusChange() {
    if (!_amountFocusNode.hasFocus) {
      String text = _amountController.text;
      if (text.isNotEmpty && !text.contains(',')) {
        _amountController.text = text + ',00';
      } else if (text.isNotEmpty) {
        final parts = text.split(',');
        if (parts.length == 2 && parts[1].length < 2) {
          _amountController.text = parts[0] + ',' + parts[1].padRight(2, '0');
        } else if (parts.length == 2 && parts[1].length > 2) {
          _amountController.text = parts[0] + ',' + parts[1].substring(0, 2);
        }
      }
    }
  }

  // 🚨 CORRECCIÓN: Agregado parámetro `onlyValidate` para separar validación del guardado
  Future<void> _performSave({
    bool popOnSuccess = true,
    bool onlyValidate = false,
  }) async {
    setState(() {
      _error = null;
      _loading = true;
    });
    void logError(String message) {
      debugPrint('[TransactionForm ERROR] $message');
    }

    // --- LÓGICA DE VALIDACIÓN (MANTENIDA) ---
    // Validaciones
    if (_selectedClient == null) {
      setState(() {
        _error = 'Debes seleccionar un cliente';
        _loading = false;
      });
      logError('Debes seleccionar un cliente');
      return Future.error('Validation failed: Missing client.');
    }
    if (_type == null) {
      setState(() {
        _error = 'Debes seleccionar Deuda o Abono';
        _loading = false;
      });
      logError('Debes seleccionar Deuda o Abono');
      return Future.error('Validation failed: Missing type.');
    }
    if (_currencyCode == null || _currencyCode!.isEmpty) {
      setState(() {
        _error = 'Debes seleccionar una moneda';
        _loading = false;
      });
      logError('Debes seleccionar una moneda');
      return Future.error('Validation failed: Missing currency.');
    }
    final amountText = _amountController.text
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() {
        _error = 'Monto inválido';
        _loading = false;
      });
      logError('Monto inválido');
      return Future.error('Validation failed: Invalid amount.');
    }
    final descriptionText = _descriptionController.text.trim();
    if (descriptionText.isEmpty) {
      setState(() {
        _error = 'Descripción obligatoria';
        _loading = false;
      });
      logError('Descripción obligatoria');
      return Future.error('Validation failed: Missing description.');
    }
    if (descriptionText.length > _descriptionMaxLength) {
      setState(() {
        _error =
            'La descripción no puede superar los $_descriptionMaxLength caracteres';
        _loading = false;
      });
      logError('Descripción demasiado larga');
      return Future.error('Validation failed: Description too long.');
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
        return Future.error('Validation failed: Invalid rate.');
      } else if (_currencyCode != null) {
        // Nota: Si estamos en modo validación, no deberíamos modificar el provider todavía
        // pero para mantener consistencia visual, lo dejamos, o se podría mover al bloque de save.
        // Por ahora lo mantenemos aquí para asegurar que el valor sea válido.
        final currencyProvider = Provider.of<CurrencyProvider>(
          context,
          listen: false,
        );
        final codeUC = _currencyCode!.toUpperCase();
        if (!currencyProvider.availableCurrencies.contains(codeUC)) {
          currencyProvider.addManualCurrency(codeUC);
        }
        currencyProvider.setRateForCurrency(codeUC, rateValue);
      }
    }

    // --- LÓGICA DE GUARDADO (MANTENIDA) ---
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

      // Si es guardado real, simula espera. Si es validación, es rápido.
      if (!onlyValidate) {
        await Future.delayed(const Duration(milliseconds: 350));
      }

      // --- Cálculo de anchorUsdValue usando CurrencyProvider si está disponible ---
      double? anchorUsdValue;
      double? rate;
      try {
        final currencyProvider = Provider.of<CurrencyProvider>(
          // ignore: use_build_context_synchronously
          context,
          listen: false,
        );
        rate = currencyProvider.getRateFor(_currencyCode ?? '');
        if ((_currencyCode ?? '').toUpperCase() == 'USD') {
          anchorUsdValue = CurrencyUtils.normalizeAnchorUsd(amount);
          rate = 1.0;
        } else if (rate != null && rate > 0) {
          anchorUsdValue = CurrencyUtils.normalizeAnchorUsd(amount / rate);
        } else {
          anchorUsdValue = null;
        }
      } catch (e) {
        // Fallback si no hay provider en el árbol
        final codeUC = _currencyCode!.toUpperCase();
        if (codeUC == 'USD') {
          anchorUsdValue = amount;
          rate = 1.0;
        } else {
          anchorUsdValue = null;
        }
      }

      // 🚨 CORRECCIÓN CLAVE: Si solo estamos validando, nos detenemos aquí antes de guardar
      if (onlyValidate) {
        // Retornamos éxito sin ejecutar el callback onSave
        return;
      }

      if (widget.onSave != null) {
        widget.onSave!(
          Transaction(
            id: localId, // id local único
            clientId: _selectedClient!.id,
            userId: widget.userId,
            type: _type!,
            amount: amount,
            description: _descriptionController.text,
            date: _selectedDate,
            createdAt: now,
            localId: localId,
            currencyCode: _currencyCode!, // safe, ya validado
            anchorUsdValue: anchorUsdValue,
          ),
        );
      }

      // Si el guardado fue exitoso y NO estamos usando el modal, hacemos el cierre
      if (popOnSuccess) {
        // ignore: use_build_context_synchronously
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Transacción guardada correctamente')),
        );
        // Cierra el modal automáticamente al guardar
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          if (widget.onClose != null) {
            widget.onClose!();
          } else {
            Navigator.of(context, rootNavigator: true).pop();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Error inesperado: $e';
        _loading = false;
      });
      logError('Error inesperado: $e');
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // 🚨 FUNCIÓN ACTUALIZADA: Prepara el resumen y muestra el modal
  void _showConfirmationModal() async {
    // 1. **Validación Previa: Llamamos a _performSave con onlyValidate: true**
    try {
      // 🚨 CORRECCIÓN: Activamos onlyValidate: true para que NO guarde todavía
      await _performSave(popOnSuccess: false, onlyValidate: true);
    } catch (e) {
      // La validación falló, _performSave ya actualizó _error, salimos.
      return;
    }

    // Si llegamos aquí, los datos son válidos y podemos generar el resumen

    // 2. **RECOLECCIÓN DE DATOS PARA RESUMEN**
    final amountText = _amountController.text.trim();
    final description = _descriptionController.text.trim();
    final currency = _currencyCode ?? 'N/A';
    final rateText = _rateController.text.trim();
    final formattedDate = DateFormat('dd/MM/yyyy').format(_selectedDate);

    // Asumo que SummaryItem está definido en confirmation_modal.dart o es global.
    final List<SummaryItem> summary = [
      SummaryItem(
        label: 'Cliente',
        value: _selectedClient!.name,
        icon: Icons.person,
      ),
      SummaryItem(
        label: 'Tipo',
        value: _type == 'debt' ? 'Deuda' : 'Abono',
        icon: _type == 'debt' ? Icons.trending_down : Icons.trending_up,
      ),
      SummaryItem(
        label: 'Monto',
        value: '$amountText $currency',
        icon: Icons.attach_money,
      ),
      SummaryItem(
        label: 'Fecha',
        value: formattedDate,
        icon: Icons.calendar_today,
      ),
    ];

    // Incluir tasa manual si fue visible y tiene valor
    if (_rateFieldVisible &&
        currency.toUpperCase() != 'USD' &&
        rateText.isNotEmpty) {
      summary.add(
        SummaryItem(
          label: 'Tasa Manual',
          value: '1 USD = $rateText ${currency.toUpperCase()}',
          icon: Icons.currency_exchange,
        ),
      );
    }

    // Incluir descripción si existe
    if (description.isNotEmpty) {
      summary.add(
        SummaryItem(
          label: 'Descripción',
          value: description,
          icon: Icons.description_outlined,
        ),
      );
    }

    // 3. **MOSTRAR EL MODAL**
    // ignore: use_build_context_synchronously
    final confirmed = await showDialog<bool?>(
      context: context,
      builder: (ctx) => ConfirmationModal(
        title: 'Confirmar Transacción',
        summaryData: summary,
        // Pasar la función de guardado real (ahora sí guardamos)
        onConfirm: () => _performSave(popOnSuccess: false, onlyValidate: false),
      ),
    );

    // 4. **MANEJO DE RESULTADO**
    // Si la confirmación fue exitosa, cerramos la pantalla principal.
    if (confirmed == true && mounted) {
      // Lógica de éxito: Mostrar SnackBar y cerrar el modal principal
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Transacción guardada correctamente')),
      );
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        if (widget.onClose != null) {
          widget.onClose!();
        } else {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Título
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Agregar Transacción para',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    // Selector o Display de Cliente
                    (_selectedClient != null)
                        ? Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colorScheme.primary,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person,
                                  color: Colors.grey,
                                  size: 28,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _selectedClient!.name,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              value: _selectedClient?.id,
                              decoration: InputDecoration(
                                labelText: 'Buscar o seleccionar cliente',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                isDense: true,
                              ),
                              items: clients.map((client) {
                                return DropdownMenuItem<String>(
                                  value: client.id,
                                  child: Container(
                                    height: 48,
                                    alignment: Alignment.centerLeft,
                                    width: double.infinity,
                                    child: Text(
                                      client.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 20),
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (id) {
                                setState(() {
                                  _selectedClient = clients.firstWhere(
                                    (c) => c.id == id,
                                  );
                                });
                              },
                              isExpanded: true,
                              menuMaxHeight: 250,
                            ),
                          ),
                    const SizedBox(height: 5),
                    // Selector de Tipo (Toggle)
                    Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: kSliderContainerBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
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
                            SizedBox(width: 45),
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
                    // Monto
                    TextField(
                      controller: _amountController,
                      focusNode: _amountFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Monto',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ThousandsFormatter(),
                      ],
                    ),
                    const SizedBox(height: 7),
                    // Moneda
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
                                  (code) => DropdownMenuItem(
                                    value: code,
                                    child: Text(code),
                                  ),
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
                            tooltip: 'Agregar Moneda',
                            onPressed: () async {
                              String? newCode = await showDialog<String>(
                                context: context,
                                builder: (ctx) {
                                  final controller = TextEditingController();
                                  return AlertDialog(
                                    title: const Text('Agregar Moneda'),
                                    content: TextField(
                                      controller: controller,
                                      decoration: const InputDecoration(
                                        labelText:
                                            '(ej: Pesos, Bolivares, Libras)',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      maxLength: 11,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
                                        child: const Text('Cancelar'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          String code = controller.text.trim();
                                          if (code.isEmpty) {
                                            Navigator.of(ctx).pop();
                                            return;
                                          }
                                          code =
                                              code
                                                  .substring(0, 1)
                                                  .toUpperCase() +
                                              (code.length > 1
                                                  ? code
                                                        .substring(1)
                                                        .toLowerCase()
                                                  : '');
                                          if (code == 'USD' ||
                                              availableCurrencies.contains(
                                                code,
                                              )) {
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
                              if (newCode != null && newCode.isNotEmpty) {
                                final normalizedCode =
                                    newCode.substring(0, 1).toUpperCase() +
                                    (newCode.length > 1
                                        ? newCode.substring(1).toLowerCase()
                                        : '');
                                final exists = availableCurrencies.any(
                                  (c) =>
                                      c.toLowerCase() ==
                                      normalizedCode.toLowerCase(),
                                );
                                if (normalizedCode == 'USD' || exists) {
                                  return;
                                }
                                try {
                                  currencyProvider.addManualCurrency(
                                    normalizedCode,
                                  );
                                } catch (e) {
                                  debugPrint(
                                    '[TX_FORM] Error al Agregar Moneda manual: $e',
                                  );
                                }
                                String selectedValue = normalizedCode;
                                for (final c
                                    in currencyProvider.availableCurrencies) {
                                  if (c.toLowerCase() ==
                                      normalizedCode.toLowerCase()) {
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
                    // Campo Tasa Manual
                    if (_rateFieldVisible)
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0, bottom: 4.0),
                        child: TextField(
                          controller: _rateController,
                          decoration: InputDecoration(
                            labelText:
                                'Tasa ${_currencyCode?.toUpperCase() ?? ''} a USD',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.attach_money_rounded),
                            errorText:
                                _rateController.text.isNotEmpty && !rateValid
                                    ? 'Ingrese una tasa válida (> 0)'
                                    : null,
                          ),
                          keyboardType: TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Selector Fecha
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
                    // Descripción con contador
                    Stack(
                      children: [
                        TextField(
                          controller: _descriptionController,
                          maxLines: 2,
                          maxLength: _descriptionMaxLength,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Descripción',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.description),
                            isDense: true,
                            counterText: '',
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              12,
                              52,
                              20,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 6,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                '${_descriptionController.text.length}/$_descriptionMaxLength',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _descriptionController.text.length >=
                                              _descriptionMaxLength
                                          ? Colors.red
                                          : (_descriptionController
                                                          .text.length >=
                                                      _descriptionMaxLength - 5
                                                  ? Colors.orange
                                                  : Colors.grey.shade700),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Mensaje de Error
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: GestureDetector(
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: _error!));
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
                    // Botón Principal (Guardar / Abrir Modal)
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
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Icon(
                                _type == 'debt'
                                    ? Icons.save
                                    : Icons.check_circle,
                              ),
                        label: Text(
                          _loading
                              ? 'Guardando...'
                              : (_type == 'debt'
                                  ? 'Guardar Deuda'
                                  : 'Guardar Abono'),
                        ),
                        // Llama a _showConfirmationModal, que ahora valida pero NO guarda hasta confirmar
                        onPressed: _loading ? null : _showConfirmationModal,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Botón Cerrar
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(
                            color: colorScheme.primary,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        icon: const Icon(Icons.close),
                        label: const Text('Cerrar'),
                        onPressed: () {
                          if (widget.onClose != null) {
                            widget.onClose!();
                          } else {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
    final selectedColor = baseColor.withValues(
      red: ((baseColor.red * 255.0).round() & 0xff).toDouble(),
      green: ((baseColor.green * 255.0).round() & 0xff).toDouble(),
      blue: ((baseColor.blue * 255.0).round() & 0xff).toDouble(),
      alpha: 0.13 * 255,
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