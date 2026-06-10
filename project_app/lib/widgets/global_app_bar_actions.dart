import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../services/role_service.dart';
import 'logout_confirmation_dialog.dart';
import '../pages/customer_profile_page.dart';
import '../pages/driver_profile_page.dart';
import 'user_profile_avatar.dart';

class GlobalAppBarActions extends StatefulWidget {
  final bool isDriverView;
  const GlobalAppBarActions({super.key, this.isDriverView = false});

  @override
  State<GlobalAppBarActions> createState() => _GlobalAppBarActionsState();
}

class _GlobalAppBarActionsState extends State<GlobalAppBarActions> {
  StreamSubscription<DatabaseEvent>? _userSubscription;
  Map<dynamic, dynamic>? _userData;
  String _role = 'customer';

  @override
  void initState() {
    super.initState();
    _listenToUserData();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  void _listenToUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userSubscription = FirebaseDatabase.instance.ref().child('users').child(user.uid).onValue.listen((event) {
      if (mounted && event.snapshot.value != null) {
        setState(() {
          _userData = event.snapshot.value as Map<dynamic, dynamic>;
          _role = _userData?['currentRole'] ?? _userData?['role'] ?? 'customer';
        });
      }
    });
  }

  Future<void> _logout() async {
    final shouldLogout = await showLogoutConfirmationDialog(context);
    if (shouldLogout != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    String pfpUrl = _userData?['profileImage'] ?? '';
    bool hasPfp = pfpUrl.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.black),
          onPressed: () {
            if (_role == 'driver') {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverProfilePage()));
            } else {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerProfilePage()));
            }
          },
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          offset: const Offset(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                UserProfileAvatar(
                  userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                  radius: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  "${_userData?['firstName'] ?? ''} ${_userData?['lastName'] ?? ''}".trim(),
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: Colors.black, size: 16),
              ],
            ),
          ),
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${_userData?['firstName'] ?? ''} ${_userData?['lastName'] ?? ''}".trim(),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  Text(
                    _userData?['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'switch',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFE8F8F5), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.swap_horiz, color: Color(0xFF43C59E), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.isDriverView ? 'التبديل إلى راكب' : 'التبديل إلى السائق', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    ],
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.logout, color: Colors.red.shade400, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                ],
              ),
            ),
          ],
          onSelected: (value) async {
            if (value == 'switch') {
              await RoleService.switchRole(context, widget.isDriverView ? 'customer' : 'driver');
            } else if (value == 'logout') {
              _logout();
            }
          },
        ),
        const SizedBox(width: 24),
      ],
    );
  }
}
