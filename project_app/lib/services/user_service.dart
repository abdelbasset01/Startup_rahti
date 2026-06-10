import 'package:firebase_database/firebase_database.dart';
import '../models/user_model.dart';

class UserService {
  final DatabaseReference _usersRef = FirebaseDatabase.instance.ref().child('users');

  // Stream user profile based on uid for real-time updates globally
  Stream<UserModel?> getUserStream(String uid) {
    return _usersRef.child(uid).onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        return UserModel.fromMap(uid, data);
      }
      return null;
    });
  }

  // Get one-time user profile
  Future<UserModel?> getUser(String uid) async {
    final snapshot = await _usersRef.child(uid).get();
    if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        return UserModel.fromMap(uid, data);
    }
    return null;
  }

  // Set or update user exactly as they are currently doing
  Future<void> saveUser(String uid, Map<String, dynamic> userData) async {
    await _usersRef.child(uid).set(userData);
  }
  
  // Specifically update certain fields (e.g., profile picture URL)
  Future<void> updateUserFields(String uid, Map<String, dynamic> updates) async {
    await _usersRef.child(uid).update(updates);
  }
}

final userService = UserService();
