import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_service.dart';
import '../utils/firebase_error_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class DriverRegisterPage extends StatefulWidget {
  const DriverRegisterPage({super.key});

  @override
  State<DriverRegisterPage> createState() => _DriverRegisterPageState();
}

class _DriverRegisterPageState extends State<DriverRegisterPage> {
  int _currentStep = 1;

  final _formKey1 = GlobalKey<FormState>();
  final _formKey2 = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nomController = TextEditingController(); // last name
  final _prenomController = TextEditingController(); // first name
  String? _selectedGender; // male / female
  File? _profileImageFile;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        _profileImageFile = File(pickedFile.path);
      });
    }
  }

  File? _licenseFile;
  File? _grayCardFile;
  File? _insuranceFile;

  Future<void> _pickDocument(int type) async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        if (type == 1) _licenseFile = File(pickedFile.path);
        else if (type == 2) _grayCardFile = File(pickedFile.path);
        else if (type == 3) _insuranceFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadToSupabase(File file, String bucketName, String userId) async {
    final String fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    debugPrint('⬆️ Uploading to bucket: $bucketName, file: $fileName');

    // Try 1: upsert:false (INSERT only) — required by most anon RLS INSERT-only policies
    try {
      await Supabase.instance.client.storage.from(bucketName).upload(
        fileName,
        file,
        fileOptions: const FileOptions(
          upsert: false,
          contentType: 'image/jpeg',
        ),
      );
      final url = Supabase.instance.client.storage.from(bucketName).getPublicUrl(fileName);
      debugPrint('✅ Upload success (upsert:false): $url');
      return url;
    } on StorageException catch (e1) {
      debugPrint('⚠️ upsert:false failed [$bucketName] statusCode=${e1.statusCode} msg=${e1.message} — retrying with upsert:true');
    } catch (e1) {
      debugPrint('⚠️ upsert:false unknown error [$bucketName]: $e1 — retrying with upsert:true');
    }

    // Try 2: upsert:true (INSERT or UPDATE) — needed when bucket RLS allows SELECT+UPDATE for anon
    try {
      await Supabase.instance.client.storage.from(bucketName).upload(
        fileName,
        file,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/jpeg',
        ),
      );
      final url = Supabase.instance.client.storage.from(bucketName).getPublicUrl(fileName);
      debugPrint('✅ Upload success (upsert:true): $url');
      return url;
    } on StorageException catch (e2) {
      debugPrint('❌ Supabase StorageException [$bucketName] statusCode=${e2.statusCode} msg=${e2.message}');
      final detail = '${e2.statusCode ?? ""}: ${e2.message}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في رفع الملف ($bucketName) — $detail'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return null;
    } catch (e2) {
      debugPrint('❌ Supabase upload unknown error [$bucketName]: $e2');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في رفع الملف ($bucketName): $e2'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return null;
    }
  }

  final _vehicleMakeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateNumberController = TextEditingController();
  
  String? _selectedVehicleType;
  final _customVehicleModelController = TextEditingController();

  String? _selectedTransportType;
  final int _selectedSeats = 4; // Default to 4 seats

  bool _isSaving = false;
  bool _submitted1 = false;
  bool _submitted2 = false;
  bool _acceptedTerms = false;

  static const List<String> _carModels = [
    'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Nissan', 'Hyundai', 'Kia',
    'Chevrolet', 'Mercedes', 'BMW', 'Audi', 'Renault', 'Peugeot', 'Suzuki',
    'Mitsubishi', 'Subaru', 'Jeep', 'Land Rover', 'Other',
  ];

  List<String> get _currentVehicleModels {
    return _carModels;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _nomController.dispose();
    _prenomController.dispose();
    _vehicleMakeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    _plateNumberController.dispose();
    _customVehicleModelController.dispose();
    super.dispose();
  }

  String? _validateAlgerianPlate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'الرجاء إدخال رقم لوحة المركبة';

    // Accept: NNNN – XX – YY (dash or en-dash), optional spaces
    final match = RegExp(r'^(\d{4})\s*[-–]\s*(\d{2})\s*[-–]\s*(\d{2})$')
        .firstMatch(v);
    if (match == null) {
      return 'يجب أن تكون اللوحة مثل: 0001-12-16';
    }

    final yy = int.tryParse(match.group(3)!);
    if (yy == null || yy < 1 || yy > 58) {
      return 'يجب أن يكون رمز الولاية بين 01 و 58';
    }
    return null;
  }

  Future<void> _saveDriverProfile() async {
    if (_isSaving) return;
    setState(() => _submitted2 = true);
    if (!_formKey2.currentState!.validate()) return;
    
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب الموافقة على شروط الخدمة')),
      );
      return;
    }

    if (_licenseFile == null || _grayCardFile == null || _insuranceFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء رفع جميع وثائق التحقق المطلوبة')),
      );
      setState(() => _isSaving = false);
      return;
    }

    final rawEmail = _emailController.text.trim();
    final rawPhone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    final vehicleType = _customVehicleModelController.text.trim();

    if (vehicleType.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إدخال صنف المركبة')),
        );
        setState(() => _isSaving = false);
      }
      return;
    }



    String authEmail = rawEmail.isNotEmpty ? rawEmail : '$rawPhone@phone.local';

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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا الحساب موجود بالفعل. يرجى تسجيل الدخول بدلاً من إنشاء حساب جديد.')),
        );
        return;
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getArabicFirebaseError(e))),
        );
        return;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل إنشاء حساب السائق')),
      );
      return;
    }

    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل إنشاء حساب السائق')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? profileImageUrl;
      if (_profileImageFile != null) {
        try {
          profileImageUrl =
              await ProfileService.uploadProfilePicture(_profileImageFile!);
        } catch (e) {
          debugPrint('⚠️ Profile image upload failed: $e');
          profileImageUrl = null;
        }
      }

      // Upload documents — failures show detailed error but don't block registration.
      // If a URL is null the admin dashboard will show no document for that slot.
      String? licenseUrl = await _uploadToSupabase(_licenseFile!, 'driver_licence', user.uid);
      String? grayCardUrl = await _uploadToSupabase(_grayCardFile!, 'carte_grise', user.uid);
      String? insuranceUrl = await _uploadToSupabase(_insuranceFile!, 'iInsurance', user.uid);

      debugPrint('📄 Document URLs — license: $licenseUrl | grayCard: $grayCardUrl | insurance: $insuranceUrl');

      // Unified Driver Structure under "users" node
      final userData = {
        'name': '${_prenomController.text.trim()} ${_nomController.text.trim()}',
        'firstName': _prenomController.text.trim(),
        'lastName': _nomController.text.trim(),
        'email': rawEmail.isNotEmpty ? rawEmail : null,
        'phone': rawPhone,
        'role': 'driver',
        'status': 'pending',
        'profileImage': profileImageUrl,
        'createdAt': ServerValue.timestamp,
        'isOnline': false,
        'loginId': rawEmail.isNotEmpty ? rawEmail : rawPhone,
        'password': password,
        'gender': _selectedGender,
        'vehicle': {
          'transportType': _selectedTransportType,
          'vehicleType': vehicleType,
          'vehicleMake': _vehicleMakeController.text.trim(),
          'vehicleSecondaryModel': _modelController.text.trim(),
          'vehicleYear': _yearController.text.trim(),
          'vehicleColor': _colorController.text.trim(),
          'plateNumber': _plateNumberController.text.trim(),
          'availableSeats': 4, // Default taken from backend or user context
        },
        'documents': {
          'driver_license': licenseUrl,
          'carte_grise': grayCardUrl,
          'insurance': insuranceUrl,
        },
        'updatedAt': ServerValue.timestamp,
      };

      await FirebaseDatabase.instance.ref().child('users').child(user.uid).set(userData);

      // Assurez-vous de mettre à jour explicitement le profil avec les URLs
      await FirebaseDatabase.instance.ref().child('users').child(user.uid).update({
        'documents': {
          'driver_license': licenseUrl,
          'carte_grise': grayCardUrl,
          'insurance': insuranceUrl,
        }
      });

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
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              },
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل حفظ ملف السائق: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (_currentStep == 2) {
              setState(() => _currentStep = 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: const Text('طلب السائق', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepper(),
            const SizedBox(height: 24),
            if (_currentStep == 1) _buildStep1() else _buildStep2(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Row(
      children: [
        _buildStepCircle('1', isActive: true),
        const SizedBox(width: 8),
        _buildStepCircle('2', isActive: _currentStep >= 2),
        const SizedBox(width: 8),
        _buildStepCircle('3', isActive: _currentStep >= 3, isGhost: true),
      ],
    );
  }

  Widget _buildStepCircle(String number, {bool isActive = false, bool isGhost = false}) {
    Color bgColor = isActive ? const Color(0xFF43C59E) : Colors.grey.shade300;
    if (isGhost) bgColor = Colors.grey.shade200;
    Color textColor = (isActive || isGhost) ? Colors.white : Colors.grey.shade600;
    if (isGhost) textColor = Colors.grey.shade400;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        number,
        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _buildStep1() {
    return Form(
      key: _formKey1,
      autovalidateMode: _submitted1 ? AutovalidateMode.always : AutovalidateMode.disabled,
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
            "المعلومات الشخصية",
             style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "أدخل بياناتك الشخصية للبدء.",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 30),
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
          Row(
            children: [
              Expanded(
                child: _buildModernTextField(
                  controller: _prenomController,
                  label: 'الاسم الأول',
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildModernTextField(
                  controller: _nomController,
                  label: 'الاسم الأخير',
                  icon: Icons.person_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            initialValue: _selectedGender,
            decoration: _modernInputDecoration('الجنس', Icons.wc),
            items: const [
              DropdownMenuItem(value: 'male', child: Text('ذكر')),
              DropdownMenuItem(value: 'female', child: Text('أنثى')),
            ],
            onChanged: (v) => setState(() => _selectedGender = v),
            validator: (v) => v == null ? 'الجنس مطلوب' : null,
          ),
          const SizedBox(height: 15),
          _buildModernTextField(controller: _emailController, label: 'البريد الإلكتروني', icon: Icons.email_outlined),
          const SizedBox(height: 15),
          _buildModernTextField(
            controller: _phoneController,
            label: 'رقم الهاتف',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (v) {
              if (v == null || v.isEmpty) return 'حقل مطلوب';
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
          const SizedBox(height: 15),
          _buildModernTextField(controller: _passwordController, label: 'كلمة المرور', icon: Icons.lock_outline, obscureText: true),
          
          const SizedBox(height: 30),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                setState(() => _submitted1 = true);
                if (_formKey1.currentState!.validate()) {
                  final rawEmail = _emailController.text.trim();
                  final rawPhone = _phoneController.text.trim();
                  if (rawEmail.isEmpty && rawPhone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('الرجاء إدخال البريد الإلكتروني أو رقم الهاتف')),
                    );
                    return;
                  }
                  if (_passwordController.text.trim().length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يجب أن تتكون كلمة المرور من 6 أحرف على الأقل')),
                    );
                    return;
                  }
                  setState(() => _currentStep = 2);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43C59E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
              ),
              child: const Text(
                'التالي',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Form(
      key: _formKey2,
      autovalidateMode: _submitted2 ? AutovalidateMode.always : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("تفاصيل المركبة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 4),
          const Text("أخبرنا عن نوع النقل والمركبة الخاصة بك", style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 20),
          
          DropdownButtonFormField<String>(
            initialValue: _selectedTransportType,
            decoration: _modernInputDecoration('نوع النقل', Icons.commute),
            items: const [
              DropdownMenuItem(value: 'car', child: Text('سيارة 🚗')),
            ],
            onChanged: (v) => setState(() {
               _selectedTransportType = v;
               _selectedVehicleType = null;
            }),
            validator: (v) => v == null ? 'نوع النقل مطلوب' : null,
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _buildModernTextField(
                  controller: _yearController,
                  label: 'السنة',
                  keyboardType: TextInputType.number,
                  icon: null,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildModernTextField(
                  controller: _colorController,
                  label: 'اللون',
                  icon: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildModernTextField(
            controller: _plateNumberController,
            label: 'رقم اللوحة',
            icon: Icons.badge_outlined,
            validator: _validateAlgerianPlate,
          ),
          const SizedBox(height: 15),
          DropdownMenu<String>(
            initialSelection: _selectedVehicleType,
            controller: _customVehicleModelController,
            label: const Text('صنف المركبة'),
            expandedInsets: EdgeInsets.zero,
            requestFocusOnTap: true,
            dropdownMenuEntries: _currentVehicleModels.map((m) => DropdownMenuEntry(value: m, label: m)).toList(),
            onSelected: (v) => setState(() => _selectedVehicleType = v),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43C59E), width: 2)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

          const SizedBox(height: 30),
          const Text("وثائق التحقق", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 4),
          Text("صور واضحة لوثائقك الرسمية", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const SizedBox(height: 20),
          _buildDocumentUploadCard(
            title: "رخصة القيادة",
            status: _licenseFile != null ? "تم اختيار الملف" : "مطلوب",
            statusColor: _licenseFile != null ? const Color(0xFF43C59E) : Colors.red,
            icon: Icons.contact_mail_outlined,
            onUpload: () => _pickDocument(1),
          ),
          const SizedBox(height: 15),
          _buildDocumentUploadCard(
            title: "البطاقة الرمادية",
            status: _grayCardFile != null ? "تم اختيار الملف" : "مطلوب",
            statusColor: _grayCardFile != null ? const Color(0xFF43C59E) : Colors.red,
            icon: Icons.description_outlined,
            onUpload: () => _pickDocument(2),
          ),
          const SizedBox(height: 15),
          _buildDocumentUploadCard(
            title: "بوليصة التأمين",
            status: _insuranceFile != null ? "تم اختيار الملف" : "مطلوب",
            statusColor: _insuranceFile != null ? const Color(0xFF43C59E) : Colors.red,
            icon: Icons.verified_user_outlined,
            onUpload: () => _pickDocument(3),
          ),
          
          const SizedBox(height: 25),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: _acceptedTerms,
                  onChanged: (v) {
                    setState(() => _acceptedTerms = v ?? false);
                  },
                  activeColor: const Color(0xFF43C59E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "أقر بأن جميع المعلومات المقدمة دقيقة وأوافق على شروط خدمة السائقين في راحتي.",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveDriverProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43C59E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'تقديم الطلب',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: Text(
              "يقوم فريقنا بمراجعة الطلبات عادة خلال 24-48 ساعة.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildDocumentUploadCard({
    required String title,
    required String status,
    required Color statusColor,
    required IconData icon,
    required VoidCallback onUpload,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Icon(icon, color: Colors.black87),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('رفع المستند'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF43C59E),
              side: const BorderSide(color: Color(0xFF43C59E)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: _modernInputDecoration(label, icon),
      validator: validator ?? (value) => (value == null || value.isEmpty) ? 'حقل مطلوب' : null,
    );
  }

  InputDecoration _modernInputDecoration(String label, IconData? icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43C59E), width: 2)),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}
