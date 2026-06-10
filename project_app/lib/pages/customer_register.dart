import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:image_picker/image_picker.dart';
import '../services/profile_service.dart';
import '../utils/firebase_error_helper.dart';

class CustomerRegisterPage extends StatefulWidget {
  const CustomerRegisterPage({super.key});

  @override
  State<CustomerRegisterPage> createState() => _CustomerRegisterPageState();
}

class _CustomerRegisterPageState extends State<CustomerRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  // This field accepts either email or phone number
  final _contactController = TextEditingController();
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _birthDateController = TextEditingController(); // Added birth date controller
  File? _profileImageFile;
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  bool _submitted = false;
  bool _isStudent = false;
  File? _studentCardFile;

  Future<void> _pickStudentCard() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        _studentCardFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        _profileImageFile = File(pickedFile.path);
      });
    }
  }

  @override
  void dispose() {
    _contactController.dispose();
    _nameController.dispose();
    _lastNameController.dispose();
    _passwordController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Future<void> _selectBirthDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      String formattedDate = pickedDate.toIso8601String().split('T').first;
      setState(() {
        _birthDateController.text = formattedDate;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'إنشاء حساب',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          autovalidateMode: _submitted ? AutovalidateMode.always : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  'lib/images/Rahti logo.png',
                  height: 120,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "لنبدأ!",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "أنشئ حساباً لحجز الرحلات والتوصيل بعناية.",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
              const SizedBox(height: 32),

              // Profile Picture (Optional)
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF43C59E), width: 2),
                        ),
                        child: _profileImageFile == null
                            ? const Icon(Icons.person, size: 50, color: Colors.grey)
                            : ClipOval(child: Image.file(_profileImageFile!, fit: BoxFit.cover, width: 100, height: 100)),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF43C59E),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              _buildModernTextField(
                controller: _contactController,
                label: 'البريد الإلكتروني أو رقم الهاتف',
                icon: Icons.contact_mail_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'حقل مطلوب';
                  
                  if (v.contains('@')) {
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                      return 'البريد الإلكتروني غير صالح';
                    }
                    return null;
                  }

                  bool has10Digits = v.length == 10 && RegExp(r'^\d+$').hasMatch(v);
                  bool validStart = v.startsWith('05') || v.startsWith('06') || v.startsWith('07');

                  if (!has10Digits && !validStart) {
                    return 'رقم الهاتف غير صالح. يجب أن يحتوي على 10 أرقام ويبدأ بـ 06 أو 05 أو 07.';
                  } else if (!has10Digits) {
                    return 'رقم الهاتف يجب أن يحتوي على 10 أرقام.';
                  } else if (!validStart) {
                    return 'رقم الهاتف يجب أن يبدأ بـ 06 أو 05 أو 07.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: _buildModernTextField(
                      controller: _nameController,
                      label: 'الاسم الأول',
                      icon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildModernTextField(
                      controller: _lastNameController,
                      label: 'الاسم الأخير',
                      icon: Icons.person_outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              _buildModernTextField(
                controller: _passwordController,
                label: 'كلمة المرور',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              
              GestureDetector(
                onTap: _selectBirthDate,
                child: AbsorbPointer(
                  child: _buildModernTextField(
                    controller: _birthDateController,
                    label: 'تاريخ الميلاد',
                    icon: Icons.calendar_today_outlined,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              SwitchListTile(
                title: const Text( 'هل أنت طالب؟ (قريبا)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF43C59E))),
                value: _isStudent,
                onChanged: (bool value) {
                  setState(() {
                    _isStudent = value;
                    if (!value) _studentCardFile = null;
                  });
                },
                activeThumbColor: const Color(0xFF43C59E),
              ),
              if (_isStudent) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _pickStudentCard,
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                    ),
                    child: _studentCardFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_studentCardFile!, fit: BoxFit.cover),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt, color: Colors.grey, size: 40),
                              SizedBox(height: 8),
                              Text('الرجاء مسح بطاقة الطالب', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ),
              ],
              
              const SizedBox(height: 40),
              
              // Submit Button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          // ... (Existing submit logic)
                          setState(() => _submitted = true);
                          if (!_formKey.currentState!.validate()) return;
                          
                          if (_isStudent && _studentCardFile == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء مسح بطاقة الطالب المرفقة')));
                            return;
                          }

                          setState(() => _isSaving = true);
                          try {
                            final contact = _contactController.text.trim();
                            final password = _passwordController.text.trim();
  
                            String authEmail;
                            String? email;
                            String? phone;
                            if (contact.contains('@')) {
                              authEmail = contact;
                              email = contact;
                            } else {
                              authEmail = '$contact@phone.local';
                              phone = contact;
                            }
  
                            User? user;
                            try {
                              final credential = await FirebaseAuth.instance
                                  .createUserWithEmailAndPassword(
                                email: authEmail,
                                password: password,
                              );
                              user = credential.user;
                            } on FirebaseAuthException catch (e) {
                              if (e.code == 'email-already-in-use') {
                                throw Exception('هذا الحساب موجود بالفعل. يرجى تسجيل الدخول بدلاً من إنشاء حساب جديد.');
                              } else {
                                rethrow;
                              }
                            }
  
                            if (user == null) throw Exception('فشل إنشاء أو تسجيل الدخول للمستخدم');
                            
                            String? profileImageUrl;
                            if (_profileImageFile != null) {
                              try {
                                profileImageUrl =
                                    await ProfileService.uploadProfilePicture(_profileImageFile!);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('تعذر رفع صورة الملف: $e')),
                                );
                              }
                            }
                            
                            String? studentCardUrl;
                            if (_isStudent && _studentCardFile != null) {
                              try {
                                final fileName = 'student_card_${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                await Supabase.instance.client.storage
                                    .from('student_cards')
                                    .upload(fileName, _studentCardFile!, fileOptions: const FileOptions(upsert: true));
                                studentCardUrl = Supabase.instance.client.storage
                                    .from('student_cards')
                                    .getPublicUrl(fileName);
                              } catch(e) {
                                print("Error uploading student card: $e");
                              }
                            }
  
                            // Unified Users Structure
                            final userData = {
                              'name': '${_nameController.text.trim()} ${_lastNameController.text.trim()}',
                              'firstName': _nameController.text.trim(),
                              'lastName': _lastNameController.text.trim(),
                              'email': email,
                              'phone': phone,
                              'role': 'passenger',
                              'profileImage': profileImageUrl,
                              'createdAt': ServerValue.timestamp,
                              'isOnline': true,
                              'loginId': contact,
                              'password': password,
                              'isStudent': _isStudent,
                              'studentCardURL': studentCardUrl,
                              'updatedAt': ServerValue.timestamp,
                            };
                            
                            await FirebaseDatabase.instance.ref().child('users').child(user.uid).set(userData);

  
                            if (!mounted) return;
                            final navigator = Navigator.of(context);
                            navigator.pushNamedAndRemoveUntil('/home', (route) => false);
                          } catch (e) {
                            if (!mounted) return;
                            final messenger = ScaffoldMessenger.of(context);
                            messenger.showSnackBar(
                              SnackBar(content: Text(getArabicFirebaseError(e))),
                            );
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43C59E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'تسجيل',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF43C59E), width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) return 'حقل مطلوب';
        return null;
      },
    );
  }
}
