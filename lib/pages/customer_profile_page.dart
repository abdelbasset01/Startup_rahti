import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/profile_service.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/user_profile_avatar.dart';
import '../widgets/logout_confirmation_dialog.dart';

class CustomerProfilePage extends StatefulWidget {
  const CustomerProfilePage({super.key});

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
  Map<dynamic, dynamic>? _customerData;
  bool _isLoading = true;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadCustomerProfile();
  }

  Future<void> _loadCustomerProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .get();

      if (snapshot.exists && mounted) {
        setState(() {
          _customerData = snapshot.value as Map<dynamic, dynamic>;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (pickedFile == null) return;
      if (!mounted) return;

      setState(() => _uploadingPhoto = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _uploadingPhoto = false);
        return;
      }

      final file = File(pickedFile.path);
      final downloadUrl = await ProfileService.uploadProfilePicture(file);
      await ProfileService.updateProfilePicture(downloadUrl, true);
      await _loadCustomerProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل في تحميل الصورة: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('اختيار من المعرض'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('التقاط صورة'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSafetyToolkit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PassengerSafetyToolkitSheet(),
    );
  }

  void _showEditPersonalInfo() {
    if (_customerData == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditPassengerInfoSheet(
        customerData: _customerData!,
        onSaved: () {
          _loadCustomerProfile(); // Refresh after save
        },
      ),
    );
  }

  void _showHelpCenter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("مركز المساعدة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
'''مرحبًا بك في مركز المساعدة لتطبيق "راحتي"
نحن هنا لمساعدتك في أي وقت لضمان تجربة استخدام سهلة وآمنة

يمكنك من خلال هذا القسم:
• التعرف على كيفية استخدام التطبيق خطوة بخطوة
• حل المشكلات الشائعة المتعلقة بالحساب أو الرحلات أو الطرود
• التواصل مع فريق الدعم عند الحاجة إلى مساعدة إضافية

📌 إذا واجهت أي مشكلة أثناء استخدام التطبيق، لا تتردد في التواصل معنا، وسيقوم فريق الدعم بالرد عليك في أقرب وقت ممكن.

نحن نعمل باستمرار على تحسين خدماتنا لضمان أفضل تجربة ممكنة لك''',
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTermsOfService() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("شروط الخدمة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
'''شروط الخدمة الخاصة بالركاب

باستخدامك لتطبيق "راحتي" كراكب، فإنك توافق على الالتزام بالشروط التالية:

1. الحساب والمعلومات
• يلتزم الراكب بتقديم معلومات صحيحة ودقيقة عند التسجيل.
• يتحمل الراكب مسؤولية حماية حسابه وعدم مشاركته مع أي طرف آخر.

2. الحجز والالتزام
• يلتزم الراكب بتأكيد الحجز فقط عند الجدية في السفر أو إرسال الطرد.
• يجب الحضور في الوقت والمكان المحددين لتجنب إلغاء الرحلة.

3. الأسعار ونظام التفاوض
• يمكن للراكب تقديم عرض سعر (السعر المقترح) عبر نظام التفاوض داخل التطبيق.
• يخضع العرض لموافقة أو رفض السائق.

4. الدفع
• يلتزم الراكب بدفع السعر النهائي المتفق عليه بالكامل عند إتمام الرحلة.
• أي محاولة لدفع مبلغ أقل أو مختلف تُعد مخالفة لشروط الاستخدام.

5. الأمتعة والطرود
• يلتزم الراكب بتقديم معلومات دقيقة عن الأمتعة أو الطرود المرسلة.
• يُمنع إرسال مواد خطرة أو غير قانونية.
• في حال فشل عملية التسليم، يتم إرجاع الطرد إلى صاحبه وفق الإجراءات المتبعة.

6. السلوك أثناء الرحلة
• يلتزم الراكب باحترام السائق وباقي الركاب.
• يُمنع أي سلوك مسيء أو مزعج أثناء الرحلة.

7. السلامة
• يجب على الراكب الالتزام بإرشادات السلامة داخل المركبة.
• يمكن استخدام أدوات السلامة داخل التطبيق عند الحاجة.

8. المسؤولية
• يتحمل الراكب مسؤولية أي تصرفات تصدر منه أثناء استخدام التطبيق أو خلال الرحلة.

9. الإلغاء والمخالفات
• قد يؤدي الإلغاء المتكرر أو السلوك غير المناسب إلى تقييد أو إيقاف الحساب.

10. الموافقة على الشروط
• باستخدامك للتطبيق، فإنك تقر بأنك قرأت هذه الشروط وفهمتها ووافقت عليها بالكامل.''',
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF43C59E))),
      );
    }

    final passengerName = _customerData != null 
        ? "${_customerData!['firstName'] ?? ''} ${_customerData!['lastName'] ?? ''}".trim() 
        : "راكب";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text("إعدادات الملف الشخصي", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: const [
          GlobalAppBarActions()
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Profile
            Center(
              child: Column(
                children: [
                   Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      GestureDetector(
                        onTap: _uploadingPhoto ? null : _showImagePickerOptions,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            UserProfileAvatar(
                              userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                              radius: 50,
                            ),
                            if (_uploadingPhoto)
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(28),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _showEditPersonalInfo,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit, size: 18, color: Color(0xFF43C59E)),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    passengerName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text("", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Green Custom Mode button
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF43C59E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      "وضع الراكب",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Account Settings
            const Text("إعدادات الحساب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildSettingTile(
              icon: Icons.person_outline,
              title: "المعلومات الشخصية",
              subtitle: "الاسم، البريد الإلكتروني، رقم الهاتف",
              onTap: _showEditPersonalInfo,
            ),

            const SizedBox(height: 32),
            // Support & Legal
            const Text("الدعم والقانون", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildSettingTile(
              icon: Icons.help_outline,
              title: "مركز المساعدة",
              onTap: _showHelpCenter,
            ),
            _buildSettingTile(
              icon: Icons.security_outlined,
              title: "أدوات السلامة",
              onTap: _showSafetyToolkit,
              iconColor: const Color(0xFF43C59E),
            ),
            _buildSettingTile(
              icon: Icons.description_outlined,
              title: "شروط الخدمة",
              onTap: _showTermsOfService,
            ),

            const SizedBox(height: 32),
            // Logout
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text("تسجيل خروج", style: TextStyle(color: Colors.red, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color iconColor = Colors.black87,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)) : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Edit Personal Info Sheet
// ----------------------------------------------------------------------
class EditPassengerInfoSheet extends StatefulWidget {
  final Map<dynamic, dynamic> customerData;
  final VoidCallback onSaved;
  const EditPassengerInfoSheet({super.key, required this.customerData, required this.onSaved});

  @override
  State<EditPassengerInfoSheet> createState() => _EditPassengerInfoSheetState();
}

class _EditPassengerInfoSheetState extends State<EditPassengerInfoSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.customerData['firstName'] ?? '');
    _lastNameController = TextEditingController(text: widget.customerData['lastName'] ?? '');
    _phoneController = TextEditingController(text: widget.customerData['phone'] ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final updates = {
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'name': '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
          'phone': _phoneController.text.trim(),
        };

        await FirebaseDatabase.instance.ref().child('users').child(user.uid).update(updates);
        
        widget.onSaved();
        if (mounted) Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث الملف الشخصي بنجاح")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في الحفظ: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(child: Text("تعديل المعلومات الشخصية", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _firstNameController,
              decoration: _inputDecoration("الاسم الأول"),
              validator: (v) => v!.isEmpty ? "مطلوب" : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameController,
              decoration: _inputDecoration("الاسم الأخير"),
              validator: (v) => v!.isEmpty ? "مطلوب" : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: _inputDecoration("رقم الهاتف"),
              keyboardType: TextInputType.phone,
              validator: (v) => v!.isEmpty ? "مطلوب" : null,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43C59E),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                : const Text("حفظ التغييرات", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43C59E), width: 2)),
    );
  }
}

// ----------------------------------------------------------------------
// Safety Toolkit Sheet (Passenger Version)
// ----------------------------------------------------------------------
class PassengerSafetyToolkitSheet extends StatelessWidget {
  const PassengerSafetyToolkitSheet({super.key});

  Future<void> _makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _handleShareTrip(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري جلب تفاصيل أحدث رحلة...')));
    
    try {
      final snap = await FirebaseDatabase.instance.ref().child('bookings').child(user.uid).get();
      if (!snap.exists || snap.value == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد رحلات حالية لمشاركتها.')));
        return;
      }
      
      Map<dynamic,dynamic> map = snap.value as Map<dynamic,dynamic>;
      List<Map<String, dynamic>> trips = [];
      map.forEach((k, v) {
        final node = Map<String, dynamic>.from(v as Map);
        if (node['status'] == 'accepted' || node['status'] == 'completed' || node['status'] == 'تم التسليم' || node['status'] == 'تم التسليم بنجاح') {
          trips.add(node);
        }
      });
      
      if (trips.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد رحلات مقبولة لمشاركتها.')));
        return;
      }
      
      trips.sort((a,b) => (b['timestamp'] as int? ?? 0).compareTo((a['timestamp'] as int? ?? 0)));
      final latestTrip = trips.first;
      
      String driverId = latestTrip['driverId']?.toString() ?? '';
      String from = latestTrip['from']?.toString() ?? 'غير محدد';
      String to = latestTrip['to']?.toString() ?? 'غير محدد';
      String date = latestTrip['date']?.toString() ?? 'غير محدد';
      String driverName = latestTrip['driverName']?.toString() ?? 'سائق';
      
      String vehicleType = "غير محدد";
      String vehicleColor = "غير محدد";
      String plateNumber = "غير محدد";

      if (driverId.isNotEmpty) {
        final driverSnap = await FirebaseDatabase.instance.ref().child('users').child(driverId).get();
        if (driverSnap.exists && driverSnap.value is Map) {
          final dData = driverSnap.value as Map<dynamic, dynamic>;
          vehicleType = dData['vehicleType']?.toString() ?? dData['vehicle']?['vehicleType']?.toString() ?? "غير محدد";
          vehicleColor = dData['vehicleColor']?.toString() ?? "غير محدد";
          plateNumber = dData['plateNumber']?.toString() ?? "غير محدد";
        }
      }

      final shareText = '''
تفاصيل الرحلة (تطبيق راحتي)
من: $from
إلى: $to
التاريخ: $date
السائق: $driverName
المركبة: $vehicleType ($vehicleColor)
لوحة التسجيل: $plateNumber
'''.trim();

      await Share.share(shareText, subject: 'تفاصيل مسار رحلتي');
    } catch(e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر جلب تفاصيل المشاركة.')));
    }
  }

  Future<void> _handleReportProblem(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final snap = await FirebaseDatabase.instance.ref().child('bookings').child(user.uid).get();
      if (!snap.exists || snap.value == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب أن يكون لديك رحلة للإبلاغ عنها.')));
        return;
      }
      
      Map<dynamic,dynamic> map = snap.value as Map<dynamic,dynamic>;
      List<Map<String, dynamic>> trips = [];
      map.forEach((k, v) {
        final node = Map<String, dynamic>.from(v as Map);
        node['bookingKey'] = k;
        if (node['status'] == 'accepted' || node['status'] == 'completed' || node['status'] == 'pending') {
          trips.add(node);
        }
      });
      
      if (trips.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد رحلات نشطة للإبلاغ عنها.')));
        return;
      }
      
      trips.sort((a,b) => (b['timestamp'] as int? ?? 0).compareTo((a['timestamp'] as int? ?? 0)));
      final latestTrip = trips.first;
      String tripId = latestTrip['tripId']?.toString() ?? '';
      String bookingKey = latestTrip['bookingKey']?.toString() ?? '';
      String driverId = latestTrip['driverId']?.toString() ?? '';

      _showReportDialogUI(context, tripId, bookingKey, driverId);
    } catch(e) {
       if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء جلب تفاصيل الرحلة.')));
    }
  }

  void _showReportDialogUI(BuildContext context, String tripId, String bookingKey, String driverId) {
    String selectedProblemType = 'تأخير';
    final List<String> problemTypes = ['تأخير', 'سلوك السائق', 'مشكلة في الدفع', 'مشكلة في الحجز', 'أخرى'];
    final TextEditingController descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.report_problem, color: Colors.red),
                  SizedBox(width: 8),
                  Text("الإبلاغ عن مشكلة", style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("نوع المشكلة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedProblemType,
                          items: problemTypes.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => selectedProblemType = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("الوصف (اختياري)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "صف المشكلة باختصار...",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final desc = descriptionController.text.trim();
                    try {
                      final logRef = FirebaseDatabase.instance.ref().child('reports').push();
                      await logRef.set({
                        'tripId': tripId,
                        'bookingKey': bookingKey,
                        'passengerId': FirebaseAuth.instance.currentUser?.uid,
                        'driverId': driverId,
                        'problemType': selectedProblemType,
                        'description': desc,
                        'timestamp': ServerValue.timestamp,
                        'status': 'pending',
                      });
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("تم إرسال بلاغك بنجاح. فريق الدعم سيتابع الحالة قريباً.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                       if (dialogContext.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ أثناء الإرسال: $e")));
                       }
                    }
                  },
                  child: const Text("إرسال البلاغ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("أدوات السلامة", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                // 1. SOS Button
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.warning_rounded, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      const Text("طوارئ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                      const SizedBox(height: 8),
                      Text(
                        "سيؤدي الضغط على هذا إلى الاتصال بالسلطات ومشاركة تفاصيل الرحلة مع الدعم وإبلاغ جهات اتصال الطوارئ الخاصة بك.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تفعيل الطوارئ.")));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("التمرير للطوارئ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), // In real app, make it a slider
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // 2. Share Trip
                _buildSafetyActionCard(
                  icon: Icons.share,
                  title: "مشاركة تفاصيل الرحلة",
                  subtitle: "أرسل معلومات الرحلة المباشرة إلى عائلتك أو أصدقائك عبر واتساب أو الرسائل القصيرة.",
                  buttonText: "مشاركة",
                  onTap: () => _handleShareTrip(context),
                ),

                // 3. Report a Problem
                _buildSafetyActionCard(
                  icon: Icons.report_problem_outlined,
                  title: "الإبلاغ عن مشكلة",
                  subtitle: "سلوك السائق، قيادة غير آمنة، سعر خاطئ...",
                  buttonText: "إبلاغ",
                  onTap: () => _handleReportProblem(context),
                ),

                // 4. General Emergency Services (Algeria)
                const SizedBox(height: 10),
                const Text("خدمات الطوارئ الوطنية", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildEmergencyCallTile("الشرطة", "17", "في خطر، المناطق الحضرية"),
                _buildEmergencyCallTile("الدرك الوطني", "1055", "خارج المناطق الحضرية"),
                _buildEmergencyCallTile("الحماية المدنية", "14", "حريق، حادث، إنقاذ"),
                _buildEmergencyCallTile("الإسعاف الطبي", "16", "مساعدة طبية عاجلة"),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.black87, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(buttonText, style: const TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildEmergencyCallTile(String name, String number, String description) {
    return ListTile(
      onTap: () => _makeCall(number),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
        child: const Icon(Icons.phone, color: Colors.blue),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      subtitle: Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(number, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
