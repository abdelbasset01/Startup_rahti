class Trip {
  final String id;
  final String vehicleName;
  final String fromWilaya;
  final String fromDistrict;
  final String toWilaya;
  final String toDistrict;
  final String time;
  final double price;
  final String driverName;
  final String carType;
  final bool allowsPackages;
  final String driverId;
  final String date; // Added date field
  final int availableSeats;
  final String transportType;
  final int totalSeats;
  final String status;
  final List<int> bookedSeatIndices;

  Trip({
    required this.id,
    required this.vehicleName,
    required this.fromWilaya,
    required this.fromDistrict,
    required this.toWilaya,
    required this.toDistrict,
    required this.time,
    required this.price,
    required this.driverName,
    required this.carType,
    required this.date,
    this.allowsPackages = false,
    this.allowsLuggage = false,
    this.allowsNegotiation = false,
    this.driverId = '',
    this.meetingPoint = '',
    this.availableSeats = 0,
    this.transportType = 'car',
    this.totalSeats = 4,
    this.status = 'active',
    this.bookedSeatIndices = const [],
    this.packagePrices,
  });

  final String meetingPoint;
  final bool allowsNegotiation;
  final bool allowsLuggage;
  final Map<String, dynamic>? packagePrices;

  String get from => '$fromWilaya, $fromDistrict';
  String get to => '$toWilaya, $toDistrict';

  // Convert Trip to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'driverName': driverName, // Kept for UI convenience
      'from': from,
      'to': to,
      'date': date,
      'time': time,
      'price': price,
      'availableSeats': availableSeats,
      'carType': carType,
      'totalSeats': totalSeats,
      'status': 'active',
      
      // Additional properties requested by old UI, kept so it doesn't break everything else
      'vehicleName': vehicleName,
      'allowsPackages': allowsPackages,
      'allowsLuggage': allowsLuggage,
      'allowsNegotiation': allowsNegotiation,
      'transport_type': transportType,
      'packagePrices': packagePrices,
    };
  }

  // Create Trip from Firebase Map
  factory Trip.fromMap(Map<dynamic, dynamic> map, String id) {
    // Legacy support for separated fields
    final fromStr = map['from']?.toString() ?? '';
    final toStr = map['to']?.toString() ?? '';
    final fromParts = fromStr.split(',');
    final toParts = toStr.split(',');

    int tSeats = (map['totalSeats'] as num?)?.toInt() ?? 4;
    
    // Parse the unified seats structure: map['seats']
    int takenCount = 0;
    List<int> bookedIndices = [];
    
    if (map['takenSeats'] != null) {
      final seatsMap = map['takenSeats'] as Map<dynamic, dynamic>;
      seatsMap.forEach((key, value) {
        final valMap = value as Map<dynamic, dynamic>;
        final status = valMap['status']?.toString() ?? '';
        final statusNorm = status.toLowerCase().trim();
        bool isTaken = false;
        if (statusNorm.isEmpty) {
           isTaken = true; 
        } else if (statusNorm == 'accepted' || statusNorm == 'completed' || statusNorm == 'starting' || statusNorm == 'arrived' || statusNorm.contains('تسليم')) {
           isTaken = true;
        } else if (statusNorm == 'pending' || statusNorm == 'driver_countered' || statusNorm == 'passenger_countered') {
           isTaken = false;
        } else if (statusNorm == 'refused' || statusNorm == 'cancelled' || statusNorm == 'canceled' || statusNorm == 'rejected' || statusNorm == 'removed' || statusNorm == 'deleted' || statusNorm == 'archived') {
           isTaken = false;
        } else {
           isTaken = true; 
        }

        if (isTaken) {
          int sCount = 1;
          if (valMap['seatIndices'] != null) {
            if (valMap['seatIndices'] is List) {
              sCount = (valMap['seatIndices'] as List).where((e) => e != null).length;
            } else if (valMap['seatIndices'] is Map) {
              sCount = (valMap['seatIndices'] as Map).length;
            } else if (valMap['seatIndices'] is String) {
              final clean = valMap['seatIndices'].toString().replaceAll('[', '').replaceAll(']', '');
              if (clean.trim().isNotEmpty) {
                sCount = clean.split(',').length;
              } else {
                sCount = 0;
              }
            }
          } else {
             sCount = (valMap['seats'] as num?)?.toInt() ?? (valMap['seatsBooked'] as num?)?.toInt() ?? 1;
          }
          takenCount += sCount;
        }
      });
    }

    if (map['bookedSeatIndices'] != null) {
      if (map['bookedSeatIndices'] is List) {
        bookedIndices = (map['bookedSeatIndices'] as List).where((e) => e != null).map((e) => (e as num).toInt()).toList();
      } else if (map['bookedSeatIndices'] is Map) {
        bookedIndices = (map['bookedSeatIndices'] as Map).values.map((e) => (e as num).toInt()).toList();
      }
    }

    int authAvailable = tSeats - takenCount;
    if (authAvailable < 0) authAvailable = 0;
    // The `availableSeats` field can be temporarily stale in RTDB.
    // When `takenSeats` exists, compute availability from it to keep the home page accurate.
    final storedAvailable = (map['availableSeats'] as num?)?.toInt();
    final effectiveAvailable = map['takenSeats'] != null
        ? authAvailable
        : (storedAvailable != null ? storedAvailable.clamp(0, tSeats) : authAvailable);

    return Trip(
      id: id,
      driverId: map['driverId']?.toString() ?? '',
      driverName: map['driverName']?.toString() ?? '',
      fromWilaya: fromParts.length > 1 ? fromParts[0].trim() : fromStr,
      fromDistrict: fromParts.length > 1 ? fromParts[1].trim() : '',
      toWilaya: toParts.length > 1 ? toParts[0].trim() : toStr,
      toDistrict: toParts.length > 1 ? toParts[1].trim() : '',
      date: map['date']?.toString() ?? '',
      time: map['time']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      availableSeats: effectiveAvailable,
      carType: map['carType']?.toString() ?? '',
      totalSeats: tSeats,
      
      // additional fields
      vehicleName: map['vehicleName']?.toString() ?? '',
      allowsPackages: map['allowsPackages'] == true,
      allowsLuggage: map['allowsLuggage'] == true,
      allowsNegotiation: map['allowsNegotiation'] == true,
      transportType: map['transport_type']?.toString() ?? 'car',
      status: map['status']?.toString() ?? 'active',
      bookedSeatIndices: bookedIndices,
      packagePrices: map['packagePrices'] != null ? Map<String, dynamic>.from(map['packagePrices']) : null,
    );
  }
}
