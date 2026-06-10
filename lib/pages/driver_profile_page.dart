import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/profile_service.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/user_profile_avatar.dart';
import '../widgets/logout_confirmation_dialog.dart';
import 'revenue_dashboard_page.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  Map<dynamic, dynamic>? _driverData;
  Map<String, dynamic>? _driverEarnings;
  bool _isLoading = true;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
  }

  Future<void> _loadDriverProfile() async {
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

      // Fetch driver trips to calculate earnings
      final tripsSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('trips')
          .orderByChild('driverId')
          .equalTo(user.uid)
          .get();
      
      double totalEarnings = 0.0;
      List<FlSpot> weeklySpots = [
        const FlSpot(0, 0), const FlSpot(1, 0), const FlSpot(2, 0),
        const FlSpot(3, 0), const FlSpot(4, 0), const FlSpot(5, 0), const FlSpot(6, 0),
      ];
      
      if (tripsSnapshot.exists) {
         Map<int, double> earningsPerDay = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};
         final now = DateTime.now();
         final tripsData = tripsSnapshot.value as Map<dynamic, dynamic>;
         
         tripsData.forEach((key, value) {
            final trip = value as Map<dynamic, dynamic>;
            final takenSeats = trip['takenSeats'] as Map<dynamic, dynamic>?;
            if (takenSeats != null) {
                takenSeats.forEach((seatKey, seatValue) {
                   final seat = seatValue as Map<dynamic, dynamic>;
                   if (seat['status'] == 'accepted') {
                      double price = 0.0;
                      if (seat['suggestedPrice'] != null) {
                        price = (seat['suggestedPrice'] as num).toDouble();
                      } else if (seat['totalPrice'] != null) {
                        price = (seat['totalPrice'] as num).toDouble();
                      } else {
                        final tripPrice = (trip['price'] as num?)?.toDouble() ?? 0.0;
                        final seats = (seat['seats'] as num?)?.toInt() ?? (seat['seatsBooked'] as num?)?.toInt() ?? 1;
                        price = tripPrice * seats;
                      }
                      
                      totalEarnings += price;
                      
                      // Calculate days ago for chart
                      if (trip['date'] != null) {
                        final dateParts = trip['date'].toString().split('/');
                        if (dateParts.length == 3) {
                          final tripDate = DateTime(
                            int.tryParse(dateParts[2]) ?? 2000, 
                            int.tryParse(dateParts[1]) ?? 1, 
                            int.tryParse(dateParts[0]) ?? 1
                          );
                          final difference = now.difference(tripDate).inDays;
                          
                          if (difference >= 0 && difference < 7) {
                             // index 6 is today, 0 is 6 days ago
                             int index = 6 - difference;
                             earningsPerDay[index] = (earningsPerDay[index] ?? 0) + price;
                          }
                        }
                      }
                   }
                });
            }
         });

         // Convert max value to a scale if needed, for now just plot raw/scaled to fit 0-10 or real money
         // fl_chart handles raw values natively, we will pass the raw spots.
         weeklySpots = earningsPerDay.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
      }

      if (snapshot.exists && mounted) {
        setState(() {
          _driverData = snapshot.value as Map<dynamic, dynamic>;
          _driverEarnings = {
            'total': totalEarnings,
            'spots': weeklySpots,
          };
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSafetyToolkit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const DriverSafetyToolkitSheet(),
    );
  }

  void _showEarningsChart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RevenueDashboardPage()),
    );
  }

  void _showPersonalInfo() {
    if (_driverData == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("المعلومات الشخصية", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFF43C59E)),
              title: const Text("الاسم الكامل"),
              subtitle: Text("${_driverData!['firstName'] ?? ''} ${_driverData!['lastName'] ?? ''}"),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.email, color: Color(0xFF43C59E)),
              title: const Text("البريد الإلكتروني"),
              subtitle: Text(_driverData!['email'] ?? 'غير متوفر'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.phone, color: Color(0xFF43C59E)),
              title: const Text("رقم الهاتف"),
              subtitle: Text(_driverData!['phone'] ?? 'غير متوفر'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43C59E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("إغلاق", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPersonalInfo() {
    if (_driverData == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditPersonalInfoSheet(
        driverData: _driverData!,
        onSaved: () {
          _loadDriverProfile(); // Refresh after save
        },
      ),
    );
  }

  void _showEditVehicleInfo() {
    if (_driverData == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditVehicleInfoSheet(
        driverData: _driverData!,
        onSaved: () {
          _loadDriverProfile(); // Refresh after save
        },
      ),
    );
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
      await _loadDriverProfile();
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
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        '''مرحبًا بك في مركز المساعدة لتطبيق "راحتي"
نحن هنا لمساعدتك في أي وقت لضمان تجربة استخدام سهلة وآمنة

يمكنك من خلال هذا القسم:
• التعرف على كيفية استخدام التطبيق خطوة بخطوة
• حل المشكلات الشائعة المتعلقة بالحساب أو الرحلات أو الطرود
• التواصل مع فريق الدعم عند الحاجة إلى مساعدة إضافية

📌 إذا واجهت أي مشكلة أثناء استخدام التطبيق، لا تتردد في التواصل معنا، وسيقوم فريق الدعم بالرد عليك في أقرب وقت ممكن

نحن نعمل باستمرار على تحسين خدماتنا لضمان أفضل تجربة ممكنة لك''',
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
        ),
      ),
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
''':باستخدامك لتطبيق "راحتي"، فإنك توافق على الا  لتزام بالشروط والأحكام التالية

• يلتزم المستخدم بتقديم معلومات صحيحة ودقيقة عند إنشاء الحساب أو استخدام الخدمات
• يمنع استخدام التطبيق لأي أغراض غير قانونية أو مخالفة للقوانين المعمول بها
• يتحمل المستخدم المسؤولية الكاملة عن أي نشاط يتم من خلال حسابه
• يلتزم السائق بالحفاظ على سلامة الأمتعة والطرود أثناء عملية النقل وتسليمها بشكل آمن إلى الوجهة المحددة
• يُمنع منعًا باتًا الاحتفاظ أو التصرف في أمتعة أو طرود الركاب لأي سبب كان
• في حال نسيان أي أغراض داخل مركبة السائق، يجب على السائق التواصل مع صاحبها وإرجاعها في أقرب وقت ممكن
• في حال عدم نجاح عملية تسليم الطرد، يتم إرجاعه إلى صاحبه الأصلي بطريقة آمنة
• يحتفظ التطبيق بحق تعديل أو تحديث الخدمات أو السياسات في أي وقت دون إشعار مسبق
• يحتفظ التطبيق بحق تعليق أو إيقاف أي حساب في حال مخالفة شروط الاستخدام
• باستخدامك للتطبيق، فإنك تقر بأنك قرأت هذه الشروط وفهمتها ووافقت عليها بالكامل''',
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

    final driverName = _driverData != null 
        ? "${_driverData!['firstName'] ?? ''} ${_driverData!['lastName'] ?? ''}".trim() 
        : "اسم السائق";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text("إعدادات", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                    driverName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          "⭐ ${((_driverData?['rating'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} (${(_driverData?['ratingCount'] as num?)?.toInt() ?? 0}) • سائق",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Green Custom Driver Mode button
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
                      "وضع السائق",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Vehicle Information
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("معلومات المركبة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                 GestureDetector(
                   onTap: _showEditVehicleInfo,
                   child: Text("تعديل", style: TextStyle(color: const Color(0xFF43C59E).withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
                 ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${_driverData?['vehicle']?['vehicleMake'] ?? ''} ${_driverData?['vehicle']?['vehicleType'] ?? ''}".trim().isEmpty 
                            ? "المركبة" 
                            : "${_driverData?['vehicle']?['vehicleMake'] ?? ''} ${_driverData?['vehicle']?['vehicleType'] ?? ''}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF43C59E).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text("تم التحقق منه", style: TextStyle(color: Color(0xFF43C59E), fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _driverData?['vehicle']?['plateNumber']?.toString() ?? "0000-00-00",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildVehicleStat("السنة", _driverData?['vehicle']?['vehicleYear'] ?? "غير متوفر"),
                      _buildVehicleStat("اللون", _driverData?['vehicle']?['vehicleColor'] ?? "غير متوفر"),
                      _buildVehicleStat("النوع", _driverData?['vehicle']?['transportType'] ?? "غير متوفر"),
                    ],
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
              onTap: _showPersonalInfo,
            ),
            _buildSettingTile(
              icon: Icons.account_balance_wallet_outlined,
              title: "الأرباح والمدفوعات",
              subtitle: "رصيد المحفظة: ${_driverEarnings != null ? _driverEarnings!['total'].toStringAsFixed(0) : '0'} د.ج",
              onTap: _showEarningsChart,
            ),
            _buildSettingTile(
              icon: Icons.verified_user_outlined,
              title: "المستندات",
              subtitle: "رخصة القيادة والتأمين",
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ميزة المستندات قريباً")));
              },
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

  Widget _buildVehicleStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
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
// Driver Earnings Sheet
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Edit Personal Info Sheet
// ----------------------------------------------------------------------
class EditPersonalInfoSheet extends StatefulWidget {
  final Map<dynamic, dynamic> driverData;
  final VoidCallback onSaved;
  const EditPersonalInfoSheet({super.key, required this.driverData, required this.onSaved});

  @override
  State<EditPersonalInfoSheet> createState() => _EditPersonalInfoSheetState();
}

class _EditPersonalInfoSheetState extends State<EditPersonalInfoSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.driverData['firstName'] ?? '');
    _lastNameController = TextEditingController(text: widget.driverData['lastName'] ?? '');
    _phoneController = TextEditingController(text: widget.driverData['phone'] ?? '');
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
        // Update users node with flat schema
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
// Edit Vehicle Info Sheet
// ----------------------------------------------------------------------
class EditVehicleInfoSheet extends StatefulWidget {
  final Map<dynamic, dynamic> driverData;
  final VoidCallback onSaved;
  const EditVehicleInfoSheet({super.key, required this.driverData, required this.onSaved});

  @override
  State<EditVehicleInfoSheet> createState() => _EditVehicleInfoSheetState();
}

class _EditVehicleInfoSheetState extends State<EditVehicleInfoSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _makeController;
  late TextEditingController _modelController;
  late TextEditingController _yearController;
  late TextEditingController _colorController;
  late TextEditingController _typeController;
  late TextEditingController _plateController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.driverData['vehicle'] as Map<dynamic, dynamic>? ?? {};
    _makeController = TextEditingController(text: vehicle['vehicleMake']?.toString() ?? '');
    _modelController = TextEditingController(text: vehicle['vehicleSecondaryModel']?.toString() ?? vehicle['vehicleModel']?.toString() ?? '');
    _yearController = TextEditingController(text: vehicle['vehicleYear']?.toString() ?? '');
    _colorController = TextEditingController(text: vehicle['vehicleColor']?.toString() ?? '');
    _typeController = TextEditingController(text: vehicle['vehicleType']?.toString() ?? '');
    _plateController = TextEditingController(text: vehicle['plateNumber']?.toString() ?? '');
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    _typeController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final updates = {
          'vehicle/vehicleMake': _makeController.text.trim(),
          'vehicle/vehicleSecondaryModel': _modelController.text.trim(),
          'vehicle/vehicleYear': _yearController.text.trim(),
          'vehicle/vehicleColor': _colorController.text.trim(),
          'vehicle/vehicleType': _typeController.text.trim(),
          'vehicle/plateNumber': _plateController.text.trim(),
        };

        await FirebaseDatabase.instance.ref().child('users').child(user.uid).update(updates);
        
        widget.onSaved();
        if (mounted) Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث معلومات المركبة بنجاح")));
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
      // Need scroll for smaller screens with keyboard
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(child: Text("تعديل معلومات المركبة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _makeController,
                      decoration: _inputDecoration("العلامة التجارية (مثل تويوتا)"),
                      validator: (v) => v!.isEmpty ? "مطلوب" : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _modelController,
                      decoration: _inputDecoration("الموديل (مثل كورولا)"),
                      validator: (v) => v!.isEmpty ? "مطلوب" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _yearController,
                      decoration: _inputDecoration("السنة"),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? "مطلوب" : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _colorController,
                      decoration: _inputDecoration("اللون"),
                      validator: (v) => v!.isEmpty ? "مطلوب" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plateController,
                decoration: _inputDecoration("رقم اللوحة (12345-116-16)"),
                validator: (v) => v!.isEmpty ? "مطلوب" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _typeController,
                decoration: _inputDecoration("نوع المركبة (مثل سيدان، سيارة رياضية)"),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ----------------------------------------------------------------------
// Safety Toolkit Sheet
// ----------------------------------------------------------------------
class DriverSafetyToolkitSheet extends StatelessWidget {
  const DriverSafetyToolkitSheet({super.key});

  Future<void> _makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  void _shareTrip() {
    // Generate dummy info assuming we have Ahmed's details
    const message = "أنا في رحلة مع راحتي مع أحمد، رقم المركبة 12345-116-19، من سطيف إلى الجزائر.";
    Share.share(message, subject: "رحلتي مع راحتي");
  }

  Future<void> _handleReportProblem(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final snap = await FirebaseDatabase.instance.ref().child('trips').orderByChild('driverId').equalTo(user.uid).limitToLast(10).get();
      if (!snap.exists || snap.value == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب أن يكون لديك رحلة للإبلاغ عنها.')));
        return;
      }
      
      Map<dynamic,dynamic> map = snap.value as Map<dynamic,dynamic>;
      List<Map<String, dynamic>> seats = [];
      map.forEach((tripId, tripVal) {
        final tripData = tripVal as Map;
        final takenSeats = tripData['takenSeats'];
        if (takenSeats is Map) {
          takenSeats.forEach((seatKey, seatVal) {
             final node = Map<String, dynamic>.from(seatVal as Map);
             node['tripId'] = tripId;
             node['seatKey'] = seatKey;
             node['date'] = tripData['date'];
             seats.add(node);
          });
        }
      });
      
      if (seats.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد رحلات نشطة للإبلاغ عنها.')));
        return;
      }
      
      seats.sort((a,b) => (b['timestamp'] as int? ?? 0).compareTo((a['timestamp'] as int? ?? 0)));
      final latestSeat = seats.first;
      
      String tripId = latestSeat['tripId']?.toString() ?? '';
      String passengerId = latestSeat['userId']?.toString() ?? '';
      String passengerName = latestSeat['userName']?.toString() ?? 'راكب';
      String date = latestSeat['date']?.toString() ?? '';

      if (context.mounted) _showReportDialogUI(context, tripId, passengerId, passengerName, date);
    } catch(e) {
       if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء جلب تفاصيل الرحلة.')));
    }
  }

  void _showReportDialogUI(BuildContext context, String tripId, String passengerId, String passengerName, String date) {
    String selectedProblemType = 'مشكلة مع راكب';
    final List<String> problemTypes = ['مشكلة مع راكب', 'مشكلة في الدفع', 'مشكلة في الطرد', 'سلوك غير لائق', 'إلغاء أو عدم حضور', 'مشكلة تقنية', 'أخرى'];
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("تفاصيل الرحلة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text("اسم الراكب: $passengerName", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text("تاريخ الرحلة: $date", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text("رقم الرحلة: $tripId", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
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
                    const Text("وصف المشكلة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 4,
                      minLines: 2,
                      decoration: InputDecoration(
                        hintText: "يرجى شرح المشكلة بالتفصيل...",
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
                    if (desc.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال وصف المشكلة")));
                      return;
                    }
                    try {
                      final logRef = FirebaseDatabase.instance.ref().child('reports').push();
                      await logRef.set({
                        'tripId': tripId,
                        'passengerId': passengerId,
                        'driverId': FirebaseAuth.instance.currentUser?.uid,
                        'problemType': selectedProblemType,
                        'description': desc,
                        'timestamp': ServerValue.timestamp,
                        'status': 'pending',
                        'reporter': 'driver',
                      });
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("تم استلام بلاغك بنجاح. سيقوم فريق الدعم بمراجعته والرد عليك في أقرب وقت ممكن.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  onTap: _shareTrip,
                ),

                // 3. Driver Verification Badge
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFF43C59E).withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.security, color: Color(0xFF43C59E), size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("سائق موثق", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF43C59E))),
                            SizedBox(height: 4),
                            Text("تم التحقق من الهوية ورخصة القيادة ووثائق المركبة بواسطة راحتي.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Report a Problem
                _buildSafetyActionCard(
                  icon: Icons.report_problem_outlined,
                  title: "الإبلاغ عن مشكلة",
                  subtitle: "مشكلة مع راكب، مشكلة في الدفع، وغيرها...",
                  buttonText: "إبلاغ",
                  onTap: () => _handleReportProblem(context),
                ),

                // 5. General Emergency Services (Algeria)
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
