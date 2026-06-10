import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rahti/models/trip_model.dart';
import 'package:rahti/pages/intro_pages.dart';
import 'package:rahti/pages/auth_gate.dart';
// localization removed

// Pages
import 'pages/selection_page.dart';
import 'pages/customer_register.dart';
import 'pages/driver_register.dart';
import 'pages/driver_home_page.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/history_page.dart';
import 'pages/delivery_page.dart';
import 'pages/discount_page.dart';
import 'pages/seat_selection_page.dart';
import 'pages/forgot_password_page.dart';
import 'pages/reset_password_page.dart';
import 'pages/messages_page.dart';
import 'pages/chat_page.dart';
import 'pages/quran_page.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'services/chat_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("Firebase init error: $e");
  }
  
  try {
    await Supabase.initialize(
      url: 'https://nwnsqvdvipayohhtybkq.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53bnNxdmR2aXBheW9oaHR5YmtxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1Mzc1OTAsImV4cCI6MjA5MjExMzU5MH0.sNZ5zjLsNnzMqui9fWQh7AF1hsl8Lf74ugFcciC_FZE',
    );
  } catch (e) {
    print("Supabase init error: $e");
  }
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      _chatService.setOnlineStatus(user.uid, true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _chatService.setOnlineStatus(user.uid, false);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (state == AppLifecycleState.resumed) {
      _chatService.setOnlineStatus(user.uid, true);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _chatService.setOnlineStatus(user.uid, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rahti',
      locale: const Locale('ar', ''), // Force Arabic
      supportedLocales: const [
        Locale('ar', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        fontFamily: 'Tajawal',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF43C59E),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Tajawal',
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          titleMedium: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.normal),
          bodyMedium: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.normal),
          labelLarge: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
      initialRoute: '/',
      routes: {
        '/': (context) => const IntroPage(),
        '/auth': (context) => const AuthGate(),
        '/selection': (context) => const SelectionPage(),
        '/customer-register': (context) => const CustomerRegisterPage(),
        '/driver-register': (context) => const DriverRegisterPage(),
        '/driver-home': (context) => const DriverHomePage(),
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/history': (context) => const HistoryPage(),
        '/delivery': (context) => const DeliveryPage(),
        '/discount': (context) => const DiscountPage(),
        '/forgot-password': (context) => const ForgotPasswordPage(),
        '/reset-password': (context) => const ResetPasswordPage(),
        '/seat-selection': (context) {
          final trip = ModalRoute.of(context)!.settings.arguments as Trip;
          return SeatSelectionPage(trip: trip);
        },
        '/messages': (context) => const MessagesPage(),
        '/chat': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ChatPage(
            tripId: args['tripId'],
            route: args['route'],
            driverName: args['driverName'],
          );
        },
        '/quran': (context) => const QuranPage(),
      },
    );
  }
}
