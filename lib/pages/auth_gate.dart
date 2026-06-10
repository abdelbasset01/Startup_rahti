import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';
import 'intro_pages.dart';
import 'global.dart';
import 'home_page.dart';
import 'driver_home_page.dart';
import '../services/role_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Widget> _getUserHome(String uid) async {
    try {
      final snapshot =
          await FirebaseDatabase.instance.ref().child('users').child(uid).get();
      if (snapshot.exists) {
        currentUserRole =
            snapshot.child('role').value?.toString() ?? 'none';
        final viewRole = RoleService.loginViewRole(snapshot);
        if (viewRole == 'driver') {
          return const DriverHomePage();
        }
        return const HomePage();
      }
    } catch (_) {}
    return const HomePage();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF43C59E)),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        } else {
          currentUserId = user.uid;
          return FutureBuilder<Widget>(
            future: _getUserHome(user.uid),
            builder: (context, widgetSnapshot) {
              if (widgetSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Color(0xFF43C59E)),
                  ),
                );
              }
              
              return widgetSnapshot.data ?? const HomePage();
            },
          );
        }
      },
    );
  }
}
