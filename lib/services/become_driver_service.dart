import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

/// Passenger → driver upgrade without creating a new account.
class BecomeDriverService {
  static bool hasVehicle(Map<dynamic, dynamic> userData) {
    final vehicle = userData['vehicle'];
    if (vehicle == null) return false;
    if (vehicle is Map) return vehicle.isNotEmpty;
    return true;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// True when this is only a passenger waiting for admin (not an existing driver).
  static bool isPassengerUpgradePending(Map<dynamic, dynamic> userData) {
    final appStatus = _str(userData['driverApplicationStatus']);
    if (appStatus == 'pending' && userData['driverUpgradeFromPassenger'] == true) {
      return true;
    }
    final role = _str(userData['role'])?.toLowerCase();
    if (appStatus == 'pending' &&
        (role == 'passenger' || role == 'customer') &&
        userData['isDriver'] != true) {
      return true;
    }
    return false;
  }

  /// Registered / approved driver (including accounts created before dual-role fields).
  static bool canSwitchToDriver(Map<dynamic, dynamic> userData) {
    if (isPassengerUpgradePending(userData)) return false;

    final appStatus = _str(userData['driverApplicationStatus']);
    if (appStatus == 'rejected' && userData['isDriver'] != true) return false;

    // Dual-role: passenger approved as driver
    if (userData['isDriver'] == true) {
      if (appStatus == 'approved' ||
          userData['isVerified'] == true ||
          _str(userData['driverStatus']) == 'active' ||
          _str(userData['status']) == 'active') {
        return true;
      }
    }

    final role = _str(userData['role'])?.toLowerCase();
    if (role == 'driver' && hasVehicle(userData)) {
      final dStatus = _str(userData['driverStatus']);
      final acctStatus = _str(userData['status']);
      if (userData['isVerified'] == true) return true;
      if (dStatus == 'active' || acctStatus == 'active') return true;
      if (appStatus == 'approved') return true;
      // Legacy approved driver (no dual-role fields, not stuck in pending)
      if (userData['driverUpgradeFromPassenger'] != true &&
          dStatus != 'pending' &&
          acctStatus != 'pending' &&
          appStatus != 'pending') {
        return true;
      }
    }

    // Approved upgrade on passenger account
    if (hasVehicle(userData) &&
        appStatus == 'approved' &&
        userData['canAccessDriverApp'] == true) {
      return true;
    }

    return false;
  }

  /// Also checks /drivers/{uid} for legacy profiles missing flags on /users.
  static Future<bool> resolveCanSwitchToDriver(
    String uid,
    Map<dynamic, dynamic> userData,
  ) async {
    if (canSwitchToDriver(userData)) return true;

    if (isPassengerUpgradePending(userData)) return false;

    try {
      final driverSnap =
          await FirebaseDatabase.instance.ref().child('drivers').child(uid).get();
      if (!driverSnap.exists || driverSnap.value == null) return false;

      final driver = Map<dynamic, dynamic>.from(driverSnap.value as Map);
      final dStatus = _str(driver['status']) ?? _str(driver['driverStatus']);
      if (driver['isVerified'] == true || dStatus == 'active') {
        return hasVehicle(userData) || _hasVehicleMap(driver);
      }
      if (hasVehicle(userData) &&
          dStatus != 'pending' &&
          dStatus != 'rejected' &&
          userData['driverUpgradeFromPassenger'] != true) {
        return true;
      }
    } catch (e) {
      debugPrint('resolveCanSwitchToDriver: $e');
    }
    return false;
  }

  static bool _hasVehicleMap(Map<dynamic, dynamic> data) {
    final vehicle = data['vehicle'];
    return vehicle != null && vehicle is Map && vehicle.isNotEmpty;
  }

  static Future<String?> uploadDocument(File file, String bucketName, String userId) async {
    final String fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await Supabase.instance.client.storage.from(bucketName).upload(
        fileName,
        file,
        fileOptions: const FileOptions(upsert: false, contentType: 'image/jpeg'),
      );
      return Supabase.instance.client.storage.from(bucketName).getPublicUrl(fileName);
    } on StorageException {
      try {
        await Supabase.instance.client.storage.from(bucketName).upload(
          fileName,
          file,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
        return Supabase.instance.client.storage.from(bucketName).getPublicUrl(fileName);
      } catch (e) {
        debugPrint('BecomeDriver upload failed [$bucketName]: $e');
        return null;
      }
    } catch (e) {
      debugPrint('BecomeDriver upload failed [$bucketName]: $e');
      return null;
    }
  }

  static Future<void> submitPassengerDriverApplication({
    required String vehicleModel,
    required String plateNumber,
    required File licenseFile,
    required File grayCardFile,
    required File insuranceFile,
    File? identityFile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final userRef = FirebaseDatabase.instance.ref().child('users').child(user.uid);
    final snap = await userRef.get();
    if (!snap.exists) throw Exception('User profile not found');

    final existing = Map<dynamic, dynamic>.from(snap.value as Map);

    if (canSwitchToDriver(existing) ||
        await resolveCanSwitchToDriver(user.uid, existing)) {
      throw Exception('أنت مسجل بالفعل كسائق. استخدم التبديل إلى السائق من القائمة.');
    }

    final appStatus = existing['driverApplicationStatus']?.toString();
    if (appStatus == 'pending') {
      throw Exception('طلبك قيد المراجعة بالفعل');
    }

    final licenseUrl = await uploadDocument(licenseFile, 'driver_licence', user.uid);
    final grayCardUrl = await uploadDocument(grayCardFile, 'carte_grise', user.uid);
    final insuranceUrl = await uploadDocument(insuranceFile, 'iInsurance', user.uid);

    if (licenseUrl == null || grayCardUrl == null || insuranceUrl == null) {
      throw Exception('فشل رفع الوثائق. تحقق من الاتصال وحاول مرة أخرى.');
    }

    String? identityUrl;
    if (identityFile != null) {
      identityUrl = await uploadDocument(identityFile, 'identity_card', user.uid);
    }
    identityUrl ??= existing['profileImage']?.toString();

    final vehicleData = {
      'transportType': 'car',
      'vehicleType': vehicleModel.trim(),
      'vehicleMake': vehicleModel.trim(),
      'plateNumber': plateNumber.trim(),
      'availableSeats': 4,
    };

    final documents = {
      'driver_license': licenseUrl,
      'carte_grise': grayCardUrl,
      'insurance': insuranceUrl,
      'identity_card': identityUrl,
    };

    final userPatch = {
      'role': 'passenger',
      'currentRole': existing['currentRole'] ?? 'passenger',
      'isPassenger': true,
      'driverApplicationStatus': 'pending',
      'driverUpgradeFromPassenger': true,
      'isDriver': false,
      'driverStatus': 'pending',
      'vehicle': vehicleData,
      'documents': documents,
      'updatedAt': ServerValue.timestamp,
    };

    await userRef.update(userPatch);

    await FirebaseDatabase.instance.ref().child('drivers').child(user.uid).set({
      'firstName': existing['firstName'],
      'lastName': existing['lastName'],
      'email': existing['email'],
      'phone': existing['phone'],
      'profilePhoto': existing['profileImage'],
      'gender': existing['gender'],
      'vehicle': vehicleData,
      'documents': documents,
      'status': 'pending',
      'driverStatus': 'pending',
      'driverApplicationStatus': 'pending',
      'driverUpgradeFromPassenger': true,
      'isVerified': false,
      'linkedPassengerUid': user.uid,
      'createdAt': existing['createdAt'] ?? ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });
  }

  static bool isApplicationPending(Map<dynamic, dynamic> userData) {
    if (canSwitchToDriver(userData)) return false;
    return isPassengerUpgradePending(userData);
  }

  static bool isApplicationRejected(Map<dynamic, dynamic> userData) {
    if (canSwitchToDriver(userData)) return false;
    return _str(userData['driverApplicationStatus']) == 'rejected' &&
        userData['isDriver'] != true &&
        _str(userData['role'])?.toLowerCase() != 'driver';
  }

  static String rejectionMessage(Map<dynamic, dynamic> userData) {
    return userData['driverRejectionReason']?.toString() ??
        'تم رفض طلبك. يمكنك التواصل مع الدعم أو إعادة المحاولة.';
  }
}
