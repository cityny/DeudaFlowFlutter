import 'package:flutter/material.dart';
import '_animated_tap_to_start.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import '../models/contact_hive.dart';

// Variable global para almacenar los contactos
List<Contact> globalContacts = [];

Future<void> saveContactsToHive(
  List<Contact> contacts, {
  void Function(int saved, int total)? onProgress,
}) async {
  final box = await Hive.openBox<ContactHive>('contacts');
  final Iterable<Contact> withPhones = contacts.where(
    (c) => c.phones.isNotEmpty,
  );
  final int total = withPhones.length;
  int saved = 0;
  for (final c in withPhones) {
    final phone = c.phones.first.number;
    final contactHive = ContactHive(
      id: c.id,
      name: c.displayName,
      phone: phone,
    );
    await box.put(c.id, contactHive);
    saved++;
    if (onProgress != null) onProgress(saved, total);
  }
  debugPrint('[CONTACTS] Contactos guardados en Hive: ${box.length}');
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isFading = false;

  @override
  void initState() {
    super.initState();
    _initContacts();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation =
        Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            Navigator.of(context).pushReplacementNamed('/login');
          }
        });
  }

  Future<void> _initContacts() async {
    final box = await Hive.openBox<ContactHive>('contacts');
    if (box.isNotEmpty) {
      // Cargar desde Hive
      globalContacts = box.values
          .map(
            (c) => Contact(
              id: c.id,
              displayName: c.name,
              phones: [Phone(c.phone)],
            ),
          )
          .toList();
      debugPrint(
        '[CONTACTS] Contactos cargados desde Hive: ${globalContacts.length}',
      );
      return;
    }
    final status = await Permission.contacts.status;
    // Si no hay permiso aún, mostrar la divulgación prominente antes de pedirlo.
    if (!status.isGranted) {
      final accepted = await _showContactDisclosure();
      if (accepted != true) {
        debugPrint('[CONTACTS] Usuario rechazó la divulgación de contactos.');
        return;
      }
    }

    if (status.isGranted || (await Permission.contacts.request()).isGranted) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      globalContacts = contacts;
      debugPrint(
        '[CONTACTS] Contactos cargados del sistema: ${contacts.length}',
      );
      // Guardar en Hive para futuras cargas rápidas
      for (final c in contacts) {
        if (c.phones.isNotEmpty) {
          final phone = c.phones.first.number;
          final contactHive = ContactHive(
            id: c.id,
            name: c.displayName,
            phone: phone,
          );
          box.put(c.id, contactHive);
        }
      }
      debugPrint('[CONTACTS] Contactos guardados en Hive: ${box.length}');
    } else {
      debugPrint('[CONTACTS] Permiso de contactos no concedido al iniciar');
    }
  }

  Future<bool?> _showContactDisclosure() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Permiso de contactos'),
          content: const Text(
            'La aplicación necesita acceder a tus contactos para facilitar la selección de clientes y autocompletar números. '
            'Los contactos se almacenarán localmente en tu dispositivo y no se compartirán con terceros. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!_isFading) {
      setState(() {
        _isFading = true;
      });
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7C3AED), // Morado principal
                Color(0xFF4F46E5), // Azul/morado
                Color(0xFF60A5FA), // Azul claro
              ],
            ),
          ),
          child: FadeTransition(
            opacity: _animation,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Bienvenido',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          offset: Offset(0, 2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Comienza a gestionar tus deudas y clientes aquí.',
                    style: TextStyle(fontSize: 20, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  AnimatedTapToStart(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
