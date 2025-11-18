import '../utils/currency_utils.dart';
// --- INICIO: Código restaurado del último commit y ajustado para layout independiente ---

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
// import '../providers/transaction_filter_provider.dart';
import '../providers/client_provider.dart';
import 'package:hive/hive.dart';
import '../models/client_hive.dart';
import '../widgets/client_form.dart';
import '../models/transaction.dart';
import '../models/client.dart';
import '../widgets/client_card.dart';
import '../widgets/general_receipt_modal.dart';
import '../widgets/transaction_form.dart';
// import 'transactions_screen.dart';
import '../utils/no_scrollbar_behavior.dart';
import '../providers/tab_provider.dart';
import '../widgets/add_global_transaction_modal.dart';
import '../widgets/sync_message_state.dart';

import '../widgets/scale_on_tap.dart';

class ClientsScreen extends StatefulWidget {
  final String userId;
  final void Function(String clientId)? onViewMovements;
  const ClientsScreen({super.key, required this.userId, this.onViewMovements});

  @override
  State<ClientsScreen> createState() => ClientsScreenState();
}

class ClientsScreenState extends State<ClientsScreen>
    with SingleTickerProviderStateMixin {
  // Botón reutilizable compacto con fondo y marco traslúcido (estilo ClientDetailsModal)
  Widget _mainActionBtn({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 40,
    double iconSize = 22,
    bool enabled = true,
    String? heroTag,
    Widget? child,
    bool wrapWithScaleOnTap = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: color.withValues(alpha: 0.5), width: 1),
    );
    Widget button = Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.09),
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: enabled && !wrapWithScaleOnTap ? onPressed : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child:
                  child ??
                  Icon(
                    icon,
                    color: enabled ? color : Colors.grey,
                    size: iconSize,
                  ),
            ),
          ),
        ),
      ),
    );
    if (wrapWithScaleOnTap && enabled) {
      button = ScaleOnTap(onTap: onPressed, child: button);
    }
    return button;
  }

  // Permite cerrar la expansión del cliente desde fuera (por ejemplo, MainScaffold)
  void closeExpansion() {
    if (_expandedClientId != null) {
      setState(() {
        _expandedClientId = null;
      });
    }
  }

  @override
  void deactivate() {
    _expandedClientId = null;
    super.deactivate();
  }

  // Permite limpiar el buscador desde fuera usando GlobalKey
  void resetSearchState() {
    if (_showSearch || _searchText.isNotEmpty) {
      setState(() {
        _showSearch = false;
        _searchText = '';
        _searchController.clear();
        _searchFocusNode.unfocus();
      });
    }
  }

  int? _lastTabIndex;

  // Limpia el buscador si la pestaña de clientes se vuelve visible y cierra expansión si no es la pestaña de clientes
  void _handleTabChange() {
    final tabProvider = Provider.of<TabProvider>(context, listen: false);
    final currentTab = tabProvider.currentIndex;
    const int clientsTabIndex =
        1; // Cambia este valor si tu pestaña de clientes tiene otro índice

    // Si NO estamos en la pestaña de clientes, cerrar expansión siempre
    if (currentTab != clientsTabIndex && _expandedClientId != null) {
      setState(() {
        _expandedClientId = null;
      });
    }
    // Si volvemos a la pestaña de clientes, limpiar buscador si estaba abierto
    if (_lastTabIndex != null &&
        _lastTabIndex != clientsTabIndex &&
        currentTab == clientsTabIndex) {
      if (_showSearch || _searchText.isNotEmpty) {
        setState(() {
          _showSearch = false;
          _searchText = '';
          _searchController.clear();
          _searchFocusNode.unfocus();
        });
      }
    }
    _lastTabIndex = currentTab;
  }

  bool _isSyncing = false;
  StreamSubscription? _connectivitySubscription;
  late final AnimationController _syncController;

  final FocusScopeNode _screenFocusScopeNode = FocusScopeNode();
  bool _showSearch = false;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // final bool _didLoadClients = false;

  // Estado de mensajes de sincronización por cliente
  final Map<String, SyncMessageState> _clientSyncStates = {};
  // Control de expansión único por id de cliente
  String? _expandedClientId;

  // Método para mostrar el formulario de transacción
  void _showTransactionForm(ClientHive client) async {
    final isMobile =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    Future<void> handleTransactionSave(Transaction tx) async {
      final txProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );
      // Mostrar mensaje de sincronización inmediato
      setState(() {
        _clientSyncStates[client.id] = SyncMessageState.syncing();
      });
      await txProvider.addTransaction(tx, widget.userId, client.id);
      // Sincroniza en segundo plano tras agregar movimiento para refrescar statscards
      Future.delayed(const Duration(seconds: 2), () async {
        if (mounted) {
          await _syncAll();
          // Mostrar mensaje de sincronizado por 3 segundos y luego ocultar
          setState(() {
            _clientSyncStates[client.id] = SyncMessageState.synced();
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _clientSyncStates.remove(client.id);
              });
            }
          });
        }
      });
      // El cierre del modal lo gestiona TransactionForm vía onClose.
      if (!mounted) return;
    }

    if (isMobile) {
      // --- IMPLEMENTACIÓN SIMPLIFICADA Y MÁS ESTABLE ---
      await showModalBottomSheet(
        context: context,
        isScrollControlled:
            true, // Permite que el bottom sheet se ajuste al teclado
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return Padding(
            // Este padding asegura que el contenido se mueva hacia arriba cuando aparece el teclado
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: TransactionForm(
                userId: widget.userId,
                onSave: handleTransactionSave,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          );
        },
      );
      return;
    }
    // Desktop/tablet: mostrar como modal dialog
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 350,
                maxWidth: 480,
                maxHeight: 600,
              ),
              child: Material(
                color: Colors.transparent,
                child: TransactionForm(
                  userId: widget.userId,
                  onSave: handleTransactionSave,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _syncController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    // Escucha cambios de conectividad y dispara sincronización automática
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      if (!result.contains(ConnectivityResult.none) && !_isSyncing) {
        await _syncAll();
      }
    });
    // Inicializa el índice de pestaña
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tabProvider = Provider.of<TabProvider>(context, listen: false);
      _lastTabIndex = tabProvider.currentIndex;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _screenFocusScopeNode.dispose();
    _connectivitySubscription?.cancel();
    _syncController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Escucha cambios de pestaña en cada build
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTabChange());
  }

  Future<void> _syncAll() async {
    if (_isSyncing) return;
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final provider = Provider.of<ClientProvider>(context, listen: false);
    bool isOnline = true;
    try {
      isOnline = await txProvider.isOnline();
    } catch (_) {
      isOnline = false;
    }
    if (!isOnline) {
      // Si no hay internet, limpiar todos los estados temporales de sincronización
      setState(() {
        _isSyncing = false;
        _syncController.reset();
        _clientSyncStates.removeWhere(
          (key, value) => value.isSyncing || value.isSynced,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se puede sincronizar en este momento. Verifica tu conexión a internet.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    setState(() {
      _isSyncing = true;
      _syncController.repeat();
      // Al reconectar, mostrar "Sincronizando" para todos los que estaban pendientes
      final box = Hive.box<ClientHive>('clients');
      for (final c in box.values) {
        // Considerar pendiente de sincronizar si no está sincronizado ni pendiente de eliminar
        if ((!c.synced && !c.pendingDelete) || c.pendingDelete == true) {
          _clientSyncStates[c.id] = SyncMessageState.syncing();
        }
      }
    });

    // --- OPTIMIZACIÓN: Flujo de Sincronización Mejorado ---
    await provider.syncPendingClients(widget.userId);
    await provider.cleanLocalPendingDeletedClients();
    await txProvider.syncPendingTransactions(widget.userId);
    await txProvider.cleanLocalOrphanTransactions();

    await Future.wait([
      provider.loadClients(widget.userId),
      txProvider.loadTransactions(widget.userId),
    ]);

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncController.reset();
        // Mostrar "Sincronizado" para los que estaban en syncing
        final ids = _clientSyncStates.keys.toList();
        for (final id in ids) {
          if (_clientSyncStates[id]?.isSyncing == true) {
            _clientSyncStates[id] = SyncMessageState.synced();
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _clientSyncStates.remove(id);
                });
              }
            });
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sincronización de clientes y transacciones completada.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void showClientForm([ClientHive? client]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withAlpha((0.25 * 255).toInt()),
      builder: (dialogContext) => AddGlobalTransactionModal(
        userId: widget.userId,
        child: ClientForm(
          initialClient: client,
          userId: widget.userId,
          onSave: (newClient, initialDescription) async {
            final provider = Provider.of<ClientProvider>(
              context,
              listen: false,
            );
            final txProvider = Provider.of<TransactionProvider>(
              context,
              listen: false,
            );
            final clientId = client?.id ?? newClient.id;
            setState(() {
              _clientSyncStates[clientId] = SyncMessageState.syncing();
            });
            bool isOnline = true;
            try {
              isOnline = await txProvider.isOnline();
            } catch (_) {
              isOnline = false;
            }
            if (client == null) {
              final realId = await provider.addClient(
                Client.fromHive(newClient),
                widget.userId,
              );
              await provider.loadClients(widget.userId);
              if (newClient.balance != 0) {
                final now = DateTime.now();
                final transactionDate = DateTime(now.year, now.month, now.day);
                final tx = Transaction(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  clientId: realId,
                  userId: widget.userId,
                  type: newClient.balance > 0 ? 'payment' : 'debt',
                  amount: newClient.balance.abs(),
                  description: initialDescription?.isNotEmpty == true
                      ? initialDescription!
                      : 'Saldo inicial',
                  date: transactionDate,
                  createdAt: now,
                  synced: false,
                  currencyCode: newClient.currencyCode,
                  anchorUsdValue: newClient.anchorUsdValue != null
                      ? CurrencyUtils.normalizeAnchorUsd(
                          newClient.anchorUsdValue!,
                        )
                      : null,
                );
                await txProvider.addTransaction(tx, widget.userId, realId);
                Future.delayed(const Duration(seconds: 2), () async {
                  if (!mounted) return;
                  if (isOnline) {
                    await _syncAll();
                  } else {
                    setState(() {
                      _clientSyncStates.remove(realId);
                    });
                  }
                });
                await txProvider.loadTransactions(widget.userId);
                await provider.loadClients(widget.userId);
                if (isOnline) {
                  await txProvider.syncPendingTransactions(widget.userId);
                }
              }
              await txProvider.loadTransactions(widget.userId);
            } else {
              await provider.updateClient(
                Client(
                  id: client.id,
                  name: newClient.name,
                  address: newClient.address,
                  phone: newClient.phone,
                  balance: client.balance,
                ),
                widget.userId,
              );
              Future.delayed(const Duration(seconds: 2), () async {
                if (!mounted) return;
                if (isOnline) {
                  await provider.syncPendingClients(widget.userId);
                  await txProvider.syncPendingTransactions(widget.userId);
                }
                setState(() {
                  if (isOnline) {
                    _clientSyncStates[client.id] = SyncMessageState.synced();
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) {
                        setState(() {
                          _clientSyncStates.remove(client.id);
                        });
                      }
                    });
                  } else {
                    _clientSyncStates.remove(client.id);
                  }
                });
              });
            }
            return newClient;
          },
          readOnlyBalance: client != null,
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (_showSearch) {
        // Da foco al campo de búsqueda solo cuando se activa
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _searchFocusNode.requestFocus();
        });
      } else {
        _searchText = '';
        _searchController.clear();
        FocusScope.of(context).unfocus();
      }
    });
  }

  // 🚨 NUEVO: Widget auxiliar para las etiquetas de sección
  Widget _buildCategoryHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            // --- INICIO: AJUSTE REALIZADO AQUÍ ---
            // Se quita el withValues(alpha: 0.1) para hacerlo sólido
            color: color.withOpacity(0.95), // Fondo casi sólido
            borderRadius: BorderRadius.circular(20),
            // Se quita el withValues(alpha: 0.3) para un borde sólido o casi sólido
            border: Border.all(color: color.withOpacity(0.95), width: 1),
            // --- FIN: AJUSTE REALIZADO AQUÍ ---
          ),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white, // Se cambia el color del texto a blanco para mejor contraste
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // 🚨 NUEVO: Widget auxiliar para envolver el card con el estilo existente
  Widget _buildClientCardWrapper(
    BuildContext context,
    ClientHive client,
    TransactionProvider txProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5), // Espaciado vertical entre cards
      child: Container(
        decoration: BoxDecoration(
          color: const Color.fromARGB(0, 0, 0, 0),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(
                0,
                0,
                0,
                0,
              ).withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ExpandableClientCard(
          client: client,
          userId: widget.userId,
          expanded: _expandedClientId == client.id,
          onExpand: () {
            setState(() {
              _expandedClientId =
                  _expandedClientId == client.id ? null : client.id;
            });
          },
          onEdit: () => showClientForm(client),
          onDelete: () async {
            final provider = Provider.of<ClientProvider>(
              context,
              listen: false,
            );
            final userTx = txProvider.transactions
                .where((tx) => tx.clientId == client.id)
                .toList();

            final String? choice = await showDialog<String>(
              context: context,
              builder: (ctx) {
                final message = userTx.isEmpty
                    ? '"${client.name}" no tiene transacciones.\n¿Eliminarlo?'
                    : '"${client.name}" tiene ${userTx.length} transacción(es).\n¿Qué deseas eliminar?';

                final indigoStyle = ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(244, 54, 133, 244),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 44),
                );
                final dangerStyle = ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 44),
                );
                final neutralStyle = ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEDEDF4),
                  foregroundColor: const Color(0xFF1F1F39),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 44),
                );

                final String confirmLabel =
                    userTx.isEmpty ? 'Sí' : 'Cliente y Transacciones';

                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (userTx.isNotEmpty) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: indigoStyle,
                            onPressed: () => Navigator.of(ctx).pop('txOnly'),
                            child: const Text('Transacciones'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: dangerStyle,
                          onPressed: () =>
                              Navigator.of(ctx).pop('clientAndTx'),
                          child: Text(confirmLabel),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: neutralStyle,
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: const Text('Cancelar'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );

            if (choice == null) return;

            try {
              if (choice == 'txOnly') {
                for (final t in userTx) {
                  await txProvider.deleteTransaction(t.id, widget.userId);
                }
                await txProvider.loadTransactions(widget.userId);
                await txProvider.syncPendingTransactions(widget.userId);
                await provider.loadClients(widget.userId);
                if (!mounted) return;
                final isOnline = await txProvider.isOnline();
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isOnline
                          ? 'Transacciones del cliente eliminadas.'
                          : 'Transacciones pendientes por eliminar.',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else if (choice == 'clientAndTx') {
                await provider.deleteClient(client.id, widget.userId);
                await provider.loadClients(widget.userId);
                if (mounted) {
                  setState(() {});
                }
                await provider.cleanLocalPendingDeletedClients();
                await provider.syncPendingClients(widget.userId);
                await txProvider.syncPendingTransactions(widget.userId);
                await txProvider.cleanLocalOrphanTransactions();
                await txProvider.loadTransactions(widget.userId);
                if (!mounted) return;
                final isOnline = await txProvider.isOnline();
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isOnline
                          ? 'Cliente y transacciones eliminados.'
                          : 'Cliente y transacciones pendientes por eliminar.',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              if (!mounted) return;
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error al eliminar: $e')),
              );
            }
          },
          onAddTransaction: () => _showTransactionForm(client),
          onViewMovements: (clientId) {
            if (_showSearch || _searchText.isNotEmpty) {
              setState(() {
                _showSearch = false;
                _searchText = '';
                _searchController.clear();
                _searchFocusNode.unfocus();
              });
            }
            if (widget.onViewMovements != null) {
              widget.onViewMovements!(clientId);
            }
          },
          onReceipt: () {
            final clientData = [
              {
                'client': client,
                'transactions': txProvider.transactions
                    .where((tx) => tx.clientId == client.id)
                    .toList(),
              },
            ];
            showDialog(
              context: context,
              builder: (_) => GeneralReceiptModal(clientData: clientData),
            );
          },
          syncMessage: _clientSyncStates[client.id] ??
              SyncMessageState.fromClient(client),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fondo degradado global y notch transparente igual que TransactionsScreen
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;
    final double topPadding = isMobile ? 24.0 : 70.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
        // Si el buscador está abierto y no tiene foco, ciérralo
        if (_showSearch && !_searchFocusNode.hasFocus) {
          setState(() {
            _showSearch = false;
            _searchText = '';
            _searchController.clear();
          });
        }
      },
      child: Stack(
        children: [
          // Fondo degradado igual que main_scaffold.dart
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF7C3AED),
                  Color(0xFF4F46E5),
                  Color(0xFF60A5FA),
                ],
              ),
            ),
          ),
          // Contenido principal
          Padding(
            padding: EdgeInsets.fromLTRB(0, topPadding, 0, 0),
            child: FocusScope(
              node: _screenFocusScopeNode,
              child: Consumer<ClientProvider>(
                builder: (context, provider, child) {
                  final box = Hive.box<ClientHive>('clients');
                  final allClients = box.values.toList();
                  final txProvider = Provider.of<TransactionProvider>(
                    context,
                    listen: false,
                  );
                  // Ordena alfabéticamente por la primera letra del nombre
                  List<ClientHive> clients =
                      _showSearch && _searchText.isNotEmpty
                          ? allClients
                              .where(
                                (c) => c.name.toLowerCase().contains(
                                      _searchText.toLowerCase(),
                                    ),
                              )
                              .toList()
                          : List<ClientHive>.from(allClients);
                  clients.sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

                  // 🚨 CLASIFICACIÓN DE CLIENTES
                  final deudores =
                      clients.where((c) => c.balance < 0).toList();
                  final saldoFavor =
                      clients.where((c) => c.balance > 0).toList();
                  final sinMovimientos =
                      clients.where((c) => c.balance == 0).toList();

                  // --- LAYOUT INDEPENDIENTE Y MODERNO ---
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(
                                  (0.92 * 255).toInt(),
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(
                                      (0.08 * 255).toInt(),
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 18,
                                horizontal: 10,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Clientes registrados',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF7C3AED),
                                          fontSize: 28,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _mainActionBtn(
                                        tooltip: 'Registrar Cliente',
                                        icon: Icons.add,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        onPressed: () => showClientForm(),
                                        heroTag: 'registrarCliente',
                                        wrapWithScaleOnTap: true,
                                      ),
                                      if (allClients.isNotEmpty) ...[
                                        const SizedBox(width: 12),
                                        _mainActionBtn(
                                          tooltip: 'Recibo general',
                                          icon: Icons.receipt_long,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          onPressed: () {
                                            final clientData = allClients
                                                .map(
                                                  (c) => {
                                                    'client':
                                                        Client.fromHive(c),
                                                    'transactions': txProvider
                                                        .transactions
                                                        .where(
                                                          (tx) =>
                                                              tx.clientId ==
                                                              c.id,
                                                        )
                                                        .toList(),
                                                  },
                                                )
                                                .toList();
                                            showDialog(
                                              context: context,
                                              builder: (_) =>
                                                  GeneralReceiptModal(
                                                    clientData: clientData,
                                                  ),
                                            );
                                          },
                                          heroTag: 'reciboGeneral',
                                          wrapWithScaleOnTap: true,
                                        ),
                                        const SizedBox(width: 12),
                                        FutureBuilder<bool>(
                                          future:
                                              Provider.of<TransactionProvider>(
                                            context,
                                            listen: false,
                                          ).isOnline(),
                                          builder: (context, snapshot) {
                                            final online =
                                                snapshot.data ?? true;
                                            if (!online) {
                                              return const SizedBox.shrink();
                                            }
                                            return _mainActionBtn(
                                              tooltip:
                                                  'Forzar sincronización de clientes y transacciones',
                                              icon: Icons.sync,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              onPressed: _isSyncing
                                                  ? () {}
                                                  : _syncAll,
                                              enabled: !_isSyncing,
                                              heroTag: 'syncClientes',
                                              child: AnimatedBuilder(
                                                animation: _syncController,
                                                builder: (context, child) {
                                                  return Transform.rotate(
                                                    angle: _isSyncing
                                                        ? -_syncController
                                                                .value *
                                                            6.28319
                                                        : 0,
                                                    child: Icon(
                                                      Icons.sync,
                                                      color: _isSyncing
                                                          ? Colors.green
                                                          : Theme.of(context)
                                                              .colorScheme
                                                              .primary,
                                                    ),
                                                  );
                                                },
                                              ),
                                              wrapWithScaleOnTap: true,
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 12),
                                        _mainActionBtn(
                                          tooltip: _showSearch
                                              ? 'Ocultar buscador'
                                              : 'Buscar cliente',
                                          icon: Icons.search,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          onPressed: _toggleSearch,
                                          heroTag: 'buscarCliente',
                                          wrapWithScaleOnTap: true,
                                        ),
                                        const SizedBox(width: 12),
                                        _mainActionBtn(
                                          tooltip:
                                              'Eliminar TODOS los clientes',
                                          icon: Icons.delete_forever,
                                          color: Colors.red[700] ?? Colors.red,
                                          onPressed: () async {
                                            final provider =
                                                Provider.of<ClientProvider>(
                                              context,
                                              listen: false,
                                            );
                                            final txProvider = Provider.of<
                                                TransactionProvider>(
                                              context,
                                              listen: false,
                                            );
                                            final box = Hive.box<ClientHive>(
                                              'clients',
                                            );
                                            final allClients =
                                                box.values.toList();
                                            if (allClients.isEmpty) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'No hay clientes para eliminar.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            // Estilos de botones (mismo ancho)
                                            final indigoStyle =
                                                ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF4F46E5),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 0,
                                              minimumSize: const Size(
                                                double.infinity,
                                                44,
                                              ),
                                            );
                                            final dangerStyle =
                                                ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 0,
                                              minimumSize: const Size(
                                                double.infinity,
                                                44,
                                              ),
                                            );
                                            final neutralStyle =
                                                ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFEDEDF4),
                                              foregroundColor:
                                                  const Color(0xFF1F1F39),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 0,
                                              minimumSize: const Size(
                                                double.infinity,
                                                44,
                                              ),
                                            );
                                            final String? choice =
                                                await showDialog<String>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                title: const Text(
                                                  '¿Qué deseas eliminar?',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                content: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        style: indigoStyle,
                                                        onPressed: () =>
                                                            Navigator.of(ctx)
                                                                .pop(
                                                          'txOnlyAll',
                                                        ),
                                                        child: const Text(
                                                          'Todas las transacciones',
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        style: dangerStyle,
                                                        onPressed: () =>
                                                            Navigator.of(ctx)
                                                                .pop(
                                                          'clientsAndTxAll',
                                                        ),
                                                        child: const Text(
                                                          'Todos los clientes',
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        style: neutralStyle,
                                                        onPressed: () =>
                                                            Navigator.of(ctx)
                                                                .pop(null),
                                                        child: const Text(
                                                          'Cancelar',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                            if (choice == null) return;

                                            // SEGUNDO DIÁLOGO DE CONFIRMACIÓN
                                            bool confirmed = true;
                                            if (choice == 'txOnlyAll' ||
                                                choice == 'clientsAndTxAll') {
                                              String warningMsg = choice ==
                                                      'txOnlyAll'
                                                  ? '¿Estás seguro de que deseas eliminar TODAS las transacciones? Esta acción no se puede deshacer.'
                                                  : '¿Estás seguro de que deseas eliminar TODOS los clientes y sus transacciones? Esta acción no se puede deshacer.';
                                              confirmed =
                                                  await showDialog<bool>(
                                                        context: context,
                                                        builder: (ctx) =>
                                                            AlertDialog(
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              16,
                                                            ),
                                                          ),
                                                          title: const Text(
                                                            'Confirmar eliminación',
                                                          ),
                                                          content:
                                                              Text(warningMsg),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                ctx,
                                                              ).pop(false),
                                                              child: const Text(
                                                                'Cancelar',
                                                              ),
                                                            ),
                                                            ElevatedButton(
                                                              style:
                                                                  dangerStyle,
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                ctx,
                                                              ).pop(true),
                                                              child: const Text(
                                                                'Eliminar',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ) ??
                                                      false;
                                              if (!confirmed) return;
                                            }

                                            try {
                                              if (choice == 'txOnlyAll') {
                                                final allTx = List.of(
                                                  txProvider.transactions,
                                                );
                                                if (allTx.isEmpty) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'No hay transacciones para eliminar.',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return;
                                                }
                                                for (final t in allTx) {
                                                  await txProvider
                                                      .deleteTransaction(
                                                    t.id,
                                                    widget.userId,
                                                  );
                                                }
                                                await txProvider
                                                    .loadTransactions(
                                                  widget.userId,
                                                );
                                                await txProvider
                                                    .syncPendingTransactions(
                                                  widget.userId,
                                                );
                                                await provider.loadClients(
                                                  widget.userId,
                                                );
                                                await txProvider
                                                    .cleanLocalOrphanTransactions();
                                                if (!mounted) return;
                                                final isOnline =
                                                    await txProvider.isOnline();
                                                if (!mounted) return;
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      isOnline
                                                          ? 'Todas las transacciones eliminadas.'
                                                          : 'Transacciones pendientes por eliminar.',
                                                    ),
                                                  ),
                                                );
                                              } else if (choice ==
                                                  'clientsAndTxAll') {
                                                for (final c in allClients) {
                                                  provider.deleteClient(
                                                    c.id,
                                                    widget.userId,
                                                  );
                                                }
                                                await _syncAll();
                                                if (mounted) {
                                                  final isOnline =
                                                      await txProvider
                                                          .isOnline();
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        isOnline
                                                            ? 'Todos los clientes eliminados.'
                                                            : 'Clientes pendientes por eliminar.',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Error al eliminar: $e',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          heroTag: 'eliminarTodos',
                                          wrapWithScaleOnTap: true,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (_showSearch && allClients.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 14.0),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 350,
                                        ),
                                        curve: Curves.easeInOut,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F6FD),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: _searchText.isNotEmpty
                                                ? const Color(0xFF7C3AED)
                                                : Colors.black,
                                            width: 2.2,
                                          ),
                                          boxShadow: _searchText.isNotEmpty
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFF7C3AED,
                                                    ).withAlpha(
                                                      (0.18 * 255).toInt(),
                                                    ),
                                                    blurRadius: 10,
                                                    spreadRadius: 1,
                                                  ),
                                                ]
                                              : [],
                                        ),
                                        child: TextField(
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          style: const TextStyle(
                                            color: Colors.black,
                                          ),
                                          cursorColor: Colors.black,
                                          enableInteractiveSelection: false,
                                          decoration: const InputDecoration(
                                            hintText: 'Buscar por nombre...',
                                            prefixIcon: Icon(
                                              Icons.search,
                                              color: Color(0xFF7C3AED),
                                            ),
                                            border: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            disabledBorder: InputBorder.none,
                                            errorBorder: InputBorder.none,
                                            focusedErrorBorder:
                                                InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 14,
                                            ),
                                            fillColor: Color(0xFFF3F6FD),
                                            filled: true,
                                            hoverColor: Colors.transparent,
                                            focusColor: Colors.transparent,
                                            iconColor: Color(0xFF7C3AED),
                                            prefixIconColor: Color(0xFF7C3AED),
                                            suffixIconColor: Colors.black,
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              _searchText = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (_searchFocusNode.hasFocus) {
                                _searchFocusNode.unfocus();
                              }
                              if (_showSearch && !_searchFocusNode.hasFocus) {
                                setState(() {
                                  _showSearch = false;
                                  _searchText = '';
                                  _searchController.clear();
                                });
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(0, 0, 0, 0),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color.fromARGB(0, 0, 0, 0),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: clients.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No hay clientes.',
                                        style: TextStyle(
                                          color: Color.fromARGB(
                                            255,
                                            255,
                                            255,
                                            255,
                                          ),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    )
                                  : GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: () {
                                        if (_showSearch) {
                                          setState(() {
                                            _showSearch = false;
                                            _searchText = '';
                                            _searchController.clear();
                                            _searchFocusNode.unfocus();
                                          });
                                        }
                                      },
                                      child: ScrollConfiguration(
                                        behavior: NoScrollbarBehavior(),
                                        child: ListView(
                                          padding: const EdgeInsets.fromLTRB(
                                            0,
                                            10,
                                            0,
                                            kBottomNavigationBarHeight + 40,
                                          ),
                                          children: [
                                            if (deudores.isNotEmpty) ...[
                                              _buildCategoryHeader(
                                                  'Deudores', Colors.red),
                                              ...deudores.map(
                                                (c) => _buildClientCardWrapper(
                                                    context, c, txProvider),
                                              ),
                                            ],
                                            if (saldoFavor.isNotEmpty) ...[
                                              _buildCategoryHeader(
                                                  'Saldo a favor',
                                                  Colors.green),
                                              ...saldoFavor.map(
                                                (c) => _buildClientCardWrapper(
                                                    context, c, txProvider),
                                              ),
                                            ],
                                            if (sinMovimientos.isNotEmpty) ...[
                                              _buildCategoryHeader(
                                                  'Sin movimientos',
                                                  Colors.grey),
                                              ...sinMovimientos.map(
                                                (c) => _buildClientCardWrapper(
                                                    context, c, txProvider),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}