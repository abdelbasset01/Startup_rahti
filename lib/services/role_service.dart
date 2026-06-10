
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'become_driver_service.dart';

class RoleService {
  /// `driver` or `customer` — which home screen to show after login.
  static String loginViewRole(DataSnapshot userSnap) {
    final role = userSnap.child('role').value?.toString().toLowerCase() ?? '';
    final currentRole =
        userSnap.child('currentRole').value?.toString().toLowerCase() ?? role;
    final hasVehicle = userSnap.child('vehicle').exists;
    final isVerified = userSnap.child('isVerified').value == true;
    final appStatus =
        userSnap.child('driverApplicationStatus').value?.toString() ?? '';
    final isDriverFlag = userSnap.child('isDriver').value == true;
    final upgradePending = appStatus == 'pending' &&
        userSnap.child('driverUpgradeFromPassenger').value == true;

    if (upgradePending) {
      return currentRole == 'driver' ? 'driver' : 'customer';
    }
    if (currentRole == 'driver') return 'driver';
    if (currentRole == 'customer' || currentRole == 'passenger') {
      return 'customer';
    }
    if (role == 'driver' && hasVehicle && (isVerified || appStatus.isEmpty)) {
      return 'driver';
    }
    if (isDriverFlag && appStatus == 'approved') {
      return 'driver';
    }
    return 'customer';
  }

  static Future<void> switchRole(BuildContext context, String targetRole) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (targetRole == 'customer') {
      await _updateRoleAndNavigate(context, user.uid, 'customer', '/home');
      return;
    }

    if (targetRole == 'driver') {
      final userSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .get();

      if (!userSnapshot.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الملف الشخصي غير موجود')),
          );
        }
        return;
      }

      final data = Map<dynamic, dynamic>.from(userSnapshot.value as Map);

      final canDrive = await BecomeDriverService.resolveCanSwitchToDriver(user.uid, data);
      if (canDrive) {
        await _updateRoleAndNavigate(context, user.uid, 'driver', '/driver-home');
        return;
      }

      if (BecomeDriverService.isApplicationPending(data)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('طلبك قيد المراجعة. سيتم إشعارك بعد موافقة الإدارة.'),
              backgroundColor: Color(0xFF43C59E),
            ),
          );
        }
        return;
      }

      if (BecomeDriverService.isApplicationRejected(data)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(BecomeDriverService.rejectionMessage(data)),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const DriverRegistrationDialog(),
        );
      }
    }
  }

  static Future<void> _updateRoleAndNavigate(
      BuildContext context, String uid, String role, String route) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(uid)
          .update({'currentRole': role});

      if (context.mounted) {
        Navigator.pop(context);
        Navigator.pushNamedAndRemoveUntil(context, route, (route) => false);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error switching role: $e')),
        );
      }
    }
  }
}

class DriverRegistrationDialog extends StatefulWidget {
  const DriverRegistrationDialog({super.key});

  @override
  State<DriverRegistrationDialog> createState() => _DriverRegistrationDialogState();
}

class _DriverRegistrationDialogState extends State<DriverRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleModelController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  File? _licenseFile;
  File? _grayCardFile;
  File? _insuranceFile;
  File? _identityFile;

  @override
  void dispose() {
    _vehicleModelController.dispose();
    _plateNumberController.dispose();
    super.dispose();
  }

  String? _validateAlgerianPlate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'يرجى إدخال رقم لوحة المركبة';
    final match = RegExp(r'^(\d{4})\s*[-–]\s*(\d{2})\s*[-–]\s*(\d{2})$').firstMatch(v);
    if (match == null) return 'Format: 0001-12-16';
    final yy = int.tryParse(match.group(3)!);
    if (yy == null || yy < 1 || yy > 58) return 'Wilaya (YY): 01-58';
    return null;
  }

  Future<void> _pickDoc(int type) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (picked == null) return;
    setState(() {
      if (type == 1) _licenseFile = File(picked.path);
      if (type == 2) _grayCardFile = File(picked.path);
      if (type == 3) _insuranceFile = File(picked.path);
      if (type == 4) _identityFile = File(picked.path);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_licenseFile == null || _grayCardFile == null || _insuranceFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء رفع جميع وثائق التحقق المطلوبة')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await BecomeDriverService.submitPassengerDriverApplication(
        vehicleModel: _vehicleModelController.text.trim(),
        plateNumber: _plateNumberController.text.trim(),
        licenseFile: _licenseFile!,
        grayCardFile: _grayCardFile!,
        insuranceFile: _insuranceFile!,
        identityFile: _identityFile,
      );

      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('طلبك قيد المراجعة', style: TextStyle(color: Color(0xFF43C59E))),
          content: const Text(
            'تم إرسال معلومات المركبة والوثائق. حسابك كراكب لم يتغير. '
            'بعد موافقة الإدارة يمكنك التبديل إلى وضع السائق من القائمة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _docRow(String label, File? file, VoidCallback onPick) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: file != null ? const Color(0xFF43C59E) : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(file != null ? Icons.check_circle : Icons.upload_file,
              color: file != null ? const Color(0xFF43C59E) : Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: onPick, child: Text(file != null ? 'تغيير' : 'رفع')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'سجّل كسائق',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'انضم إلينا وكن جزءًا من فريق السائقين لدينا\n(نفس حسابك كراكب — بدون إنشاء حساب جديد)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _vehicleModelController,
                  decoration: InputDecoration(
                    labelText: 'موديل السيارة',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  validator: (v) => v?.trim().isEmpty == true ? 'مطلوب' : null,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _plateNumberController,
                  decoration: InputDecoration(
                    labelText: 'رقم لوحة المركبة',
                    hintText: '0001-12-16',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  validator: _validateAlgerianPlate,
                ),
                const SizedBox(height: 12),
                _docRow('رخصة القيادة *', _licenseFile, () => _pickDoc(1)),
                _docRow('Carte grise (grise) *', _grayCardFile, () => _pickDoc(2)),
                _docRow('التأمين *', _insuranceFile, () => _pickDoc(3)),
                _docRow('بطاقة التعريف (اختياري إذا لديك صورة ملف)', _identityFile, () => _pickDoc(4)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43C59E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'انطلق معنا كسائق',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
