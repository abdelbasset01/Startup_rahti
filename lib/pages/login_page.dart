
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'global.dart';
import '../utils/firebase_error_helper.dart';
import '../services/role_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailOrPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isFirstTimeUser = false;

  // Animations
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic)),
    );
    _animController.forward();
    _checkFirstTimeUser();
  }

  Future<void> _checkFirstTimeUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstTime = prefs.getBool('first_time_user') ?? true;
    if (isFirstTime) {
      setState(() {
        _isFirstTimeUser = true;
      });
      await prefs.setBool('first_time_user', false);
    }
  }

  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loginUser() async {
    try {
      final id = _emailOrPhoneController.text.trim();
      final password = _passwordController.text.trim();

      // If user typed an email, use it directly.
      // If they typed a phone number, derive the synthetic email "phone@phone.local"
      final String authEmail = id.contains('@') ? id : '$id@phone.local';

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: authEmail,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        if (!mounted) return;
        _showErrorSnackBar('فشل تسجيل الدخول. يرجى المحاولة مرة أخرى.');
        return;
      }

      currentUserId = user.uid;

      // Read role from Realtime Database
      String role = 'none';
      String currentRole = 'none';
      String status = 'approved';
      DataSnapshot? userSnapshot;
      try {
        userSnapshot =
            await FirebaseDatabase.instance.ref().child('users').child(user.uid).get();
        if (userSnapshot.exists) {
          role = userSnapshot.child('role').value?.toString() ?? 'none';
          currentRole =
              userSnapshot.child('currentRole').value?.toString() ?? role;
          status = userSnapshot.child('status').value?.toString() ?? 'approved';
        }
      } catch (_) {}

      if (status == 'pending') {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('حسابك قيد المراجعة', style: TextStyle(color: Color(0xFF43C59E))),
            content: const Text('تم إنشاء حسابك بنجاح. حسابك الآن قيد المراجعة، وسيتم تفعيل إمكانية تسجيل الدخول بعد التحقق من ملفاتك.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        return;
      }

      if (status == 'suspended') {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('حساب موقوف', style: TextStyle(color: Colors.red)),
            content: const Text('تم إيقاف حسابك بسبب رفض وثائقك أو لمخالفة الشروط. يرجى التواصل مع الدعم الفني.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        return;
      }

      currentUserRole = role;

      String route = '/home';
      if (userSnapshot != null && userSnapshot.exists) {
        final viewRole = RoleService.loginViewRole(userSnapshot);
        if (viewRole == 'driver') {
          route = '/driver-home';
        }
      } else if (currentRole == 'driver') {
        route = '/driver-home';
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(getArabicFirebaseError(e));
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(getArabicFirebaseError(e));
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle()),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.grey.shade50,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    // Large Logo
                    Image.asset(
                      'lib/images/Rahti logo.png',
                      height: 200,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isFirstTimeUser ? 'مرحبًا بك في تطبيق راحتي' : 'مرحباً بعودتك',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Form inside pure column
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPremiumTextField(
                            controller: _emailOrPhoneController,
                            hint: 'البريد الإلكتروني أو رقم الهاتف',
                            icon: Icons.person_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) => val == null || val.isEmpty ? 'حقل مطلوب' : null,
                          ),
                          const SizedBox(height: 20),
                          _buildPremiumTextField(
                            controller: _passwordController,
                            hint: 'كلمة المرور',
                            icon: Icons.lock_outline_rounded,
                            isPassword: true,
                            validator: (val) => val == null || val.isEmpty ? 'حقل مطلوب' : null,
                          ),
                          
                          // Forgot Password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                'هل نسيت كلمة المرور؟',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF43C59E), // primary color
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Login Button
                          SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  _loginUser();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF43C59E), // primary color
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'تسجيل الدخول',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          // Sign Up Link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "ليس لديك حساب؟",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pushNamed(context, '/selection'),
                                child: const Text(
                                  "إنشاء حساب",
                                  style: TextStyle(
                                    color: Color(0xFF43C59E),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.black87, fontSize: 16),
        cursorColor: const Color(0xFF43C59E),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.grey.shade600,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          errorStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500, height: 1.2),
        ),
        validator: validator,
      ),
    );
  }
}
