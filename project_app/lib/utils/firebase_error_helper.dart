import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

String getArabicFirebaseError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح.';
      case 'user-disabled':
        return 'لقد تم تعطيل حساب المستخدم هذا.';
      case 'user-not-found':
        return 'لم يتم العثور على مستخدم مسجل بهذا البريد الإلكتروني.';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة.';
      case 'email-already-in-use':
        return 'البريد الإلكتروني مستخدم بالفعل لحساب آخر.';
      case 'operation-not-allowed':
        return 'تسجيل الدخول غير مفعل في الوقت الحالي.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة. يجب أن تتكون من 6 أحرف على الأقل.';
      case 'network-request-failed':
        return 'حدث خطأ في الاتصال بالشبكة. يرجى التحقق من اتصالك بالإنترنت.';
      case 'too-many-requests':
        return 'لقد تجاوزت الحد المسموح به من المحاولات. يرجى المحاولة لاحقاً.';
      case 'credential-already-in-use':
        return 'بيانات الاعتماد مستخدمة مسبقاً.';
      case 'invalid-credential':
        return 'بيانات تسجيل الدخول أو الرمز غير صالحين.';
      case 'invalid-verification-code':
        return 'رمز التحقق الذي أدخلته غير صحيح.';
      case 'invalid-verification-id':
        return 'مُعرّف التحقق غير صالح.';
      case 'missing-verification-code':
        return 'يرجى إدخال رمز التحقق.';
      case 'missing-verification-id':
        return 'مُعرّف التحقق مفقود.';
      case 'quota-exceeded':
        return 'تم تجاوز الحد الأقصى للمحاولات المسموح بها.';
      case 'session-expired':
        return 'انتهت صلاحية جلسة التحقق من الرسائل القصيرة. يرجى طلب الرمز مرة أخرى.';
      case 'app-not-authorized':
        return 'هذا التطبيق غير مصرح له باستخدام مصادقة Firebase بالرقم المختار.';
      default:
        return _cleanFirebaseMessage(e.message ?? 'حدث خطأ أثناء المصادقة.');
    }
  } else if (e is FirebaseException) {
    if (e.code == 'network-request-failed' || e.message?.contains('network') == true) {
      return 'حدث خطأ في الاتصال بالشبكة. يرجى التحقق من اتصالك بالإنترنت.';
    }
    return _cleanFirebaseMessage(e.message ?? 'حدث خطأ في قاعدة البيانات.');
  }

  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _cleanFirebaseMessage(String message) {
  // Remove [firebase_auth/xyz], [core/xyz], etc.
  final rawMessage = message.replaceAll(RegExp(r'\[.*?\]\s*'), '').trim();
  
  if (rawMessage.isEmpty) {
    return 'حدث خطأ غير معروف.';
  }
  
  // If the error contains English keywords we haven't mapped, fallback to generic
  final lowerRaw = rawMessage.toLowerCase();
  if (lowerRaw.contains('network') || lowerRaw.contains('connection') || lowerRaw.contains('timeout')) {
    return 'حدث خطأ في الاتصال بالشبكة. يرجى التحقق من اتصالك بالإنترنت.';
  }
  
  return rawMessage;
}
