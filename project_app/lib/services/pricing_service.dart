import 'dart:math';

class PricingService {
  // Mapping of Wilayas to Zones (0 to 5)
  static final Map<int, List<String>> _zoneMappings = {
    0: ['Algiers'],
    1: ['Blida', 'Boumerdes', 'Tipaza'],
    2: [
      'Chlef', 'Oum El Bouaghi', 'Batna', 'Bejaia', 'Bouira', 'Tlemcen',
      'Tiaret', 'Tizi Ouzou', 'Jijel', 'Setif', 'Saida', 'Skikda',
      'Sidi Bel Abbes', 'Annaba', 'Guelma', 'Constantine', 'Medea',
      'Mostaganem', 'MSila', 'Mascara', 'Oran', 'Bordj Bou Arreridj',
      'El Tarf', 'Tissemsilt', 'Khenchela', 'Souk Ahras', 'Mila',
      'Ain Defla', 'Ain Temouchent', 'Relizane'
    ],
    3: ['Laghouat', 'Biskra', 'Tebessa', 'Djelfa', 'Ouargla', 'El Oued', 'Ghardaia', 'Ouled Djellal', 'Touggourt', 'El Meghaier', 'El Meniaa'],
    4: ['Adrar', 'Bechar', 'El Bayadh', 'Naama', 'Timimoun', 'Bordj Badji Mokhtar', 'Beni Abbes'],
    5: ['Tamanrasset', 'Illizi', 'Tindouf', 'In Salah', 'In Guezzam', 'Djanet']
  };

  // Prices Array from the JSON configuration (Medium + Commission)
  static final Map<String, double> _finalPricesMatrix = {
    '0-0': 110, '0-1': 165, '0-2': 330, '0-3': 495, '0-4': 660, '0-5': 825,
    '1-0': 165, '1-1': 165, '1-2': 275, '1-3': 440, '1-4': 605, '1-5': 770,
    '2-0': 330, '2-1': 275, '2-2': 220, '2-3': 385, '2-4': 550, '2-5': 715,
    '3-0': 495, '3-1': 440, '3-2': 385, '3-3': 275, '3-4': 440, '3-5': 660,
    '4-0': 660, '4-1': 605, '4-2': 550, '4-3': 440, '4-4': 330, '4-5': 550,
    '5-0': 825, '5-1': 770, '5-2': 715, '5-3': 660, '5-4': 550, '5-5': 385
  };

  /// Get the zone for a specific Wilaya
  static int getZone(String wilayaName) {
    for (var entry in _zoneMappings.entries) {
      if (entry.value.contains(wilayaName)) {
        return entry.key;
      }
    }
    return 5; // Default to Zone 5 if not found
  }

  /// Calculate Final Delivery Price (incl. Commission)
  static double calculateFinalDeliveryPrice(String fromWilaya, String toWilaya, String packageType) {
    int zoneA = getZone(fromWilaya);
    int zoneB = getZone(toWilaya);

    double finalPrice = _finalPricesMatrix['$zoneA-$zoneB'] ?? 300.0;

    if (packageType.contains('خفيف') || packageType == 'small') {
      finalPrice -= 45;
    } else if (packageType.contains('ثقيل') || packageType == 'heavy') {
      finalPrice += 165;
    }

    return max(finalPrice, 50.0);
  }

  /// Max increase: Unbounded (Negotiate freely)
  static double getMaxPrice(double price) {
    return double.infinity;
  }

  /// Max decrease: Unbounded (Negotiate freely)
  static double getMinPrice(double price) {
    return 0.0;
  }

  /// Platform Commission - Assumed to be 10% on driver earnings
  /// Since finalPrice = driverEarnings * 1.10
  /// commission = finalPrice - (finalPrice / 1.10)
  static double calculateCommission(double finalPrice) {
    return finalPrice - (finalPrice / 1.10);
  }

  static const double studentDiscountPercent = 15.0;

  /// True when admin approved the student card on Firebase.
  static bool isVerifiedStudent(Map<dynamic, dynamic>? userData) {
    if (userData == null) return false;
    final card = userData['studentCard'];
    final status = userData['studentCardStatus']?.toString() ??
        (card is Map ? card['studentCardStatus']?.toString() : null);
    if (status == 'approved') return true;
    if (userData['studentVerified'] == true) return true;
    if (userData['isVerifiedStudent'] == true) return true;
    if (userData['applyStudentDiscount'] == true && userData['isStudent'] == true) {
      return true;
    }
    return false;
  }

  static double applyVerifiedStudentDiscount(double price) {
    return price * (1 - studentDiscountPercent / 100);
  }
}
