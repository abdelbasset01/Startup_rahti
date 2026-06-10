import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/profile_service.dart';

class ProfilePictureDialog extends StatefulWidget {
  const ProfilePictureDialog({super.key});

  @override
  State<ProfilePictureDialog> createState() => _ProfilePictureDialogState();
}

class _ProfilePictureDialogState extends State<ProfilePictureDialog> {
  bool _isEnabled = false;
  File? _imageFile;
  String? _currentImageUrl;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseDatabase.instance.ref().child('users').child(user.uid).get();
    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      final raw = data['profileImage'];
      final url = raw == null ? null : raw.toString().trim();
      setState(() {
        _isEnabled = data['isProfilePictureEnabled'] == true;
        _currentImageUrl = (url != null && url.isNotEmpty) ? url : null;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _isEnabled = true; // Auto enable when picking new image
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    try {
      String? finalImageUrl = _currentImageUrl;

      if (_imageFile != null) {
        finalImageUrl = await ProfileService.uploadProfilePicture(_imageFile!);
      }

      await ProfileService.updateProfilePicture(finalImageUrl, _isEnabled);

      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث الملف الشخصي بنجاح'),
          backgroundColor: Color(0xFF43C59E),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حفظ الصورة: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'الصورة الشخصية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            // Preview
            GestureDetector(
              onTap: _isEnabled ? () => _showPickerOptions() : null,
              child: Stack(
                children: [
                   Container(
                     width: 100,
                     height: 100,
                     decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       color: Colors.grey.shade200,
                       border: Border.all(color: _isEnabled ? const Color(0xFF43C59E) : Colors.grey, width: 3),
                       image: (_isEnabled && (_imageFile != null || _currentImageUrl != null))
                           ? DecorationImage(
                               image: _imageFile != null 
                                 ? FileImage(_imageFile!) 
                                 : NetworkImage(_currentImageUrl!) as ImageProvider,
                               fit: BoxFit.cover,
                             )
                           : null,
                     ),
                     child: (!_isEnabled || (_imageFile == null && _currentImageUrl == null))
                       ? const Icon(Icons.person, size: 50, color: Colors.grey)
                       : null,
                   ),
                   if (_isEnabled)
                     Positioned(
                       bottom: 0,
                       right: 0,
                       child: Container(
                         padding: const EdgeInsets.all(6),
                         decoration: const BoxDecoration(
                           color: Colors.blue,
                           shape: BoxShape.circle,
                         ),
                         child: const Icon(Icons.edit, color: Colors.white, size: 16),
                       ),
                     ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Toggle
            SwitchListTile(
              title: const Text("تفعيل الصورة الشخصية"),
              value: _isEnabled,
              activeThumbColor: const Color(0xFF43C59E),
              onChanged: (val) {
                setState(() => _isEnabled = val);
              },
            ),

            if (_isEnabled) ...[
               const SizedBox(height: 10),
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                 children: [
                   TextButton.icon(
                     onPressed: () => _pickImage(ImageSource.gallery),
                     icon: const Icon(Icons.photo_library),
                     label: const Text("المعرض"),
                   ),
                   TextButton.icon(
                     onPressed: () => _pickImage(ImageSource.camera),
                     icon: const Icon(Icons.camera_alt),
                     label: const Text("الكاميرا"),
                   ),
                 ],
               ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("تأكيد", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('جديد من المعرض'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('التقاط صورة'),
              onTap: () {
                Navigator.pop(context);
                 _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }
}
