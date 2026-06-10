import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/trip_model.dart';
import '../services/pricing_service.dart';
import '../widgets/user_profile_avatar.dart';

class Seat {
  bool isTaken;
  String gender; // 'male', 'female', 'kids', or ''
  int seatNumber;
  String? takenBy; // User ID or Name

  Seat({
    required this.isTaken,
    this.gender = '',
    required this.seatNumber,
    this.takenBy,
  });
}

class SeatSelectionPage extends StatefulWidget {
  final Trip trip;

  const SeatSelectionPage({super.key, required this.trip});

  @override
  State<SeatSelectionPage> createState() => _SeatSelectionPageState();
}

class _SeatSelectionPageState extends State<SeatSelectionPage> {
  Map<int, Map<String, dynamic>> selectedSeats = {}; // Map of seatIndex -> {'gender': 'male', 'luggage': false}
  int numberOfSeats = 5; // Default to 5 seats
  List<Seat> seats = [];
  StreamSubscription<DatabaseEvent>? _seatsSubscription;
  bool _isLoading = true;
  final TextEditingController _suggestedPriceController =
      TextEditingController();
  final TextEditingController _promoCodeController = TextEditingController();
  String? _appliedPromoCode;
  double _promoDiscount = 0.0;
  String? _promoError;
  int _negotiationPrice = 0;
  String _selectedGender = 'male';
  bool _verifiedStudent = false;

  @override
  void initState() {
    super.initState();
    _initializeSeats();
    _negotiationPrice = widget.trip.price.toInt();
    _suggestedPriceController.text = _negotiationPrice.toString();
    _listenToSeatUpdates();
    _loadVerifiedStudentStatus();
  }

  Future<void> _loadVerifiedStudentStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .get();
      if (!snap.exists || !mounted) return;
      final data = snap.value as Map<dynamic, dynamic>;
      setState(() {
        _verifiedStudent = PricingService.isVerifiedStudent(data);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _seatsSubscription?.cancel();
    _suggestedPriceController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  void _initializeSeats() {
    numberOfSeats = widget.trip.totalSeats + 1;
    
    // Initial fill
    seats = List.generate(
      numberOfSeats,
      (index) =>
          Seat(isTaken: index == 0, seatNumber: index), // Driver always taken
    );
  }

  void _listenToSeatUpdates() {
    final tripRef = FirebaseDatabase.instance
        .ref()
        .child('trips')
        .child(widget.trip.id)
        .child('takenSeats');

    _seatsSubscription = tripRef.onValue.listen((event) {
      if (!mounted) return;

      // Reset seats (keep driver)
      final newSeats = List.generate(
        numberOfSeats,
        (index) => Seat(isTaken: index == 0, seatNumber: index),
      );

      if (event.snapshot.value != null) {
        Map<dynamic, dynamic> safeMap = {};
        if (event.snapshot.value is List) {
          final list = event.snapshot.value as List;
          for (int i = 0; i < list.length; i++) {
            if (list[i] != null) safeMap[i.toString()] = Map<dynamic, dynamic>.from(list[i] as Map);
          }
        } else if (event.snapshot.value is Map) {
          safeMap = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        }

        safeMap.forEach((key, booking) {
          try {
            final bookingMap = Map<dynamic, dynamic>.from(booking as Map);
            
            // Do not mark seats as taken if the booking was rejected or canceled
            final status = bookingMap['status']?.toString() ?? 'pending';
            if (status == 'canceled' || status == 'refused' || status == 'rejected') {
              return;
            }

            final List<int> indices = _extractSeatIndices(bookingMap['seatIndices']);
            final rawGenders = bookingMap['seatGenders'];
            
            final String fallbackGender = bookingMap['gender']?.toString() ?? 'unknown';

            for (final idx in indices) {
              if (idx > 0 && idx < numberOfSeats) {
                String specificGender = fallbackGender;
                if (rawGenders is Map) {
                  specificGender = rawGenders[idx.toString()]?.toString() ?? rawGenders[idx]?.toString() ?? fallbackGender;
                } else if (rawGenders is List) {
                  if (idx >= 0 && idx < rawGenders.length && rawGenders[idx] != null) {
                    specificGender = rawGenders[idx].toString();
                  }
                }

                newSeats[idx] = Seat(
                  isTaken: true,
                  seatNumber: idx,
                  gender: specificGender,
                  takenBy: bookingMap['userName'],
                );
              }
            }
          } catch (e) {
            debugPrint("Error parsing individual booking seat: $e");
          }
        });
      }

      if (mounted) {
        setState(() {
          seats = newSeats;
          _isLoading = false;

          // Remove any selected seats that are now taken
          selectedSeats.removeWhere((idx, _) => seats[idx].isTaken);
        });
      }
    });
  }

  List<int> _extractSeatIndices(dynamic rawSeatIndices) {
    final List<int> indices = [];

    void addIndex(dynamic value) {
      if (value is int) {
        indices.add(value);
        return;
      }
      if (value is num) {
        indices.add(value.toInt());
        return;
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          indices.add(parsed);
        }
      }
    }

    if (rawSeatIndices is List) {
      for (final value in rawSeatIndices) {
        addIndex(value);
      }
    } else if (rawSeatIndices is Map) {
      for (final value in rawSeatIndices.values) {
        addIndex(value);
      }
    } else {
      addIndex(rawSeatIndices);
    }

    return indices.toSet().toList()..sort();
  }

  Color getSeatColor(Seat seat, int index) {
    if (index == 0) return Colors.black87; // Driver

    if (seat.isTaken) {
      if (seat.gender == 'male') return Colors.blue.shade800;
      if (seat.gender == 'female') return Colors.pink.shade400;
      if (seat.gender == 'kids') return Colors.orange;
      return Colors.grey.shade400;
    }

    if (selectedSeats.containsKey(index)) {
      String assignedGender = selectedSeats[index]!['gender'];
      if (assignedGender == 'male') return Colors.blue.shade800;
      if (assignedGender == 'female') return Colors.pink.shade400;
      if (assignedGender == 'kids') return Colors.orange;
      return const Color(0xFF43C59E);
    }

    return Colors.white;
  }



  // Promotion codes from discount page
  bool _validatePromoCode(String code, Trip trip, bool hasPackage) {
    switch (code) {
      case 'WELCOME50':
        // First confirmed trip - we'll allow it (could check user history in future)
        return true;

      case 'SUMMER24':
        // Coastal destinations in Algeria
        final coastalWilayas = [
          'Alger',
          'Oran',
          'Annaba',
          'Bejaia',
          'Jijel',
          'Skikda',
          'Mostaganem',
          'Tipaza',
          'Tlemcen',
          'Chlef',
        ];
        return coastalWilayas.contains(trip.toWilaya) ||
            coastalWilayas.contains(trip.fromWilaya);

      case 'STUDENT':
        // Inter-wilaya trips (different wilayas)
        return trip.fromWilaya != trip.toWilaya;

      case 'FREESHIP':
        // Only for package delivery
        return hasPackage && trip.allowsLuggage;

      default:
        return false;
    }
  }

  Map<String, dynamic>? _getPromoInfo(String code) {
    switch (code) {
      case 'WELCOME50':
        return {'discount': 50.0, 'title': 'عرض الرحلة الأولى'};
      case 'SUMMER24':
        return {'discount': 20.0, 'title': 'أجواء الصيف'};
      case 'STUDENT':
        return {'discount': 15.0, 'title': 'توفير الطلاب'};
      case 'FREESHIP':
        return {'discount': 100.0, 'title': 'توصيل مجاني'};
      default:
        return null;
    }
  }

  void _applyPromoCode() {
    final code = _promoCodeController.text.trim().toUpperCase();
    setState(() {
      _promoError = null;
      _appliedPromoCode = null;
      _promoDiscount = 0.0;
    });

    if (code.isEmpty) {
      setState(() {
        _promoError = 'الرجاء إدخال رمز الخصم';
      });
      return;
    }

    final promoInfo = _getPromoInfo(code);
    if (promoInfo == null) {
      setState(() {
        _promoError = 'رمز خصم غير صالح';
      });
      return;
    }

    bool anyPackage = selectedSeats.values.any((s) => s['luggage'] == true);
    if (!_validatePromoCode(code, widget.trip, anyPackage)) {
      setState(() {
        _promoError = 'هذا الرمز لا يطبق على هذه الرحلة';
      });
      return;
    }

    setState(() {
      _appliedPromoCode = code;
      _promoDiscount = promoInfo['discount'] as double;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تطبيق ${promoInfo['title']}! خصم ${_promoDiscount.toInt()}%',
        ),
        backgroundColor: const Color(0xFF43C59E),
      ),
    );
  }

  double _calculateFinalPrice() {
    if (widget.trip.allowsNegotiation && _negotiationPrice > 0) {
      return _negotiationPrice.toDouble();
    }
    int seatCount = selectedSeats.length;
    double basePrice = widget.trip.price * seatCount;

    // Apply promotion discount if code is applied
    if (_appliedPromoCode != null && _promoDiscount > 0) {
      basePrice = basePrice * (1 - _promoDiscount / 100);
    } else if (_verifiedStudent &&
        widget.trip.fromWilaya != widget.trip.toWilaya) {
      // Auto 15% for admin-verified students (inter-wilaya), same rule as STUDENT promo
      basePrice = PricingService.applyVerifiedStudentDiscount(basePrice);
    }

    return basePrice;
  }

  void toggleSeatSelection(int index) {
    if (seats[index].isTaken || index == 0) return;
    setState(() {
      if (selectedSeats.containsKey(index)) {
        if (selectedSeats[index]!['gender'] == _selectedGender) {
           selectedSeats.remove(index);
        } else {
           selectedSeats[index]!['gender'] = _selectedGender;
        }
      } else {
        selectedSeats[index] = {'gender': _selectedGender, 'luggage': false};
      }
      
      if (widget.trip.allowsNegotiation) {
         int seatCount = selectedSeats.isEmpty ? 1 : selectedSeats.length;
         _negotiationPrice = (widget.trip.price * seatCount).toInt();
         if (_negotiationPrice < 100) _negotiationPrice = 100;
         _suggestedPriceController.text = _negotiationPrice.toString();
      }
    });
  }

  Widget _buildCategoryToggle(String gender, String label, Color color) {
    bool isSelected = _selectedGender == gender;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = gender),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : Colors.transparent),
          boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> confirmBooking() async {
    int bookingSeatCount = selectedSeats.length;

    if (bookingSeatCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء تحديد مقعد واحد على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (bookingSeatCount > widget.trip.availableSeats) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يتوفر ${widget.trip.availableSeats} مقاعد فقط.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("الرجاء تسجيل الدخول لحجز رحلة.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    // 1. Get User Name
    String userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
    String firstName = '';
    String lastName = '';
    try {
      final userSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .get();
      if (userSnapshot.exists) {
        final data = userSnapshot.value as Map<dynamic, dynamic>;
        firstName = data['firstName']?.toString() ?? '';
        lastName = data['lastName']?.toString() ?? '';
        userName = "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
        if (userName.isEmpty) userName = data['name'] ?? 'Passenger';
      }
    } catch (_) {}

    // Calculate final price with discount
    final finalPrice = _calculateFinalPrice();
    int seatCount = selectedSeats.length;
    final basePrice = widget.trip.price * seatCount;

    final Map<String, String> seatGenders = {};
    final Map<String, bool> seatLuggage = {};
    bool anyPackage = false;
    selectedSeats.forEach((key, value) {
      seatGenders[key.toString()] = value['gender'];
      seatLuggage[key.toString()] = value['luggage'] == true;
      if (value['luggage'] == true) anyPackage = true;
    });

    if (widget.trip.allowsNegotiation && _negotiationPrice < 100) {
      _negotiationPrice = 100;
    }

    final primaryGender = selectedSeats.isNotEmpty ? selectedSeats.values.first['gender'] : 'male';

    final tripRef = FirebaseDatabase.instance
        .ref()
        .child('trips')
        .child(widget.trip.id);

    // Check if the passenger was previously removed to mark this as a rejoin request
    bool isRejoin = false;
    try {
      final chatStatusSnap = await tripRef.child('chatStatus').child(user.uid).get();
      if (chatStatusSnap.exists) {
        final status = chatStatusSnap.value?.toString();
        if (status == 'removed' || status == 'deleted') {
          isRejoin = true;
        }
      }
    } catch (_) {}

    // 2. Prepare Data for trip/takenSeats
    final bookingData = {
      'userId': user.uid,
      'userName': userName,
      'firstName': firstName,
      'lastName': lastName,
      'seats': seatCount,
      'seatIndices': selectedSeats.keys.toList(),
      'seatGenders': seatGenders,
      'seatLuggage': seatLuggage,
      'gender': primaryGender,
      'hasPackage': anyPackage,
      'luggagePrice': 0,
      'wantsNegotiation': widget.trip.allowsNegotiation,
      'suggestedPrice': widget.trip.allowsNegotiation ? _negotiationPrice : null,
      'promoCode': _appliedPromoCode,
      'promoDiscount': _appliedPromoCode != null ? _promoDiscount : null,
      'totalPrice': finalPrice,
      'basePrice': basePrice,
      'status': 'booked',
      'isRejoin': isRejoin,
      'bookingTime': ServerValue.timestamp,
    };

    try {
      // 1. Retrieve the old seatKey if this is a rejoin request, to enforce a true RESTORE flow
      String? oldSeatKey;
      if (isRejoin) {
        final bookingsSnap = await FirebaseDatabase.instance.ref().child('bookings').child(user.uid).orderByChild('tripId').equalTo(widget.trip.id).get();
        if (bookingsSnap.exists) {
          final map = bookingsSnap.value as Map<dynamic, dynamic>;
          for (var entry in map.entries) {
            final b = entry.value as Map<dynamic, dynamic>;
            if (b['status'] == 'cancelled') {
              oldSeatKey = entry.key.toString();
              break;
            }
          }
        }
      }

      final takenSeatsRef = tripRef.child('takenSeats');
      final seatKey = oldSeatKey ?? takenSeatsRef.push().key!;
      final newSeatRef = takenSeatsRef.child(seatKey);

      // Set the booking in takenSeats
      await newSeatRef.set({
        ...bookingData,
        'bookingKey': seatKey,
        'driverSeen': false,
      });
      
      // Handle the strict RTDB equivalent of Firestore's arrayUnion as requested functionally
      final currentIndicesRef = tripRef.child('bookedSeatIndices');
      final currentIndicesSnap = await currentIndicesRef.get();
      List<dynamic> existingIndices = [];
      if (currentIndicesSnap.exists && currentIndicesSnap.value != null) {
        existingIndices = List<dynamic>.from(currentIndicesSnap.value as List<dynamic>);
      }
      for (int id in selectedSeats.keys) {
        if (!existingIndices.contains(id)) {
           existingIndices.add(id);
        }
      }

      await tripRef.update({
         'bookedSeatIndices': existingIndices,
         'availableSeats': ServerValue.increment(-seatCount),
      });

      // 3. Add to bookings (History) with pending status - will be updated when driver accepts/refuses
      final historyData = {
        'tripId': widget.trip.id,
        'from': widget.trip.from,
        'to': widget.trip.to,
        'date': widget.trip.date,
        'time': widget.trip.time,
        'driverName': widget.trip.driverName,
        'vehicleName': widget.trip.vehicleName,
        'price': finalPrice,
        'basePrice': basePrice,
        'seats': seatCount,
        'status': 'pending',
        'hasPackage': anyPackage,
        'luggagePrice': 0,
        'suggestedPrice': widget.trip.allowsNegotiation ? _negotiationPrice : null,
        'promoCode': _appliedPromoCode,
        'promoDiscount': _appliedPromoCode != null ? _promoDiscount : null,
        'wantsNegotiation': widget.trip.allowsNegotiation,
        'bookingTimestamp': ServerValue.timestamp,
        'seatKey': seatKey,
        'driverId': widget.trip.driverId,
        'gender': primaryGender,
        'seatGenders': seatGenders,
        'seatLuggage': seatLuggage,
        'seatIndices': selectedSeats.keys.toList(),
        'totalSeats': widget.trip.totalSeats,
        'username': userName,
        'passengerSeen': true,
        'isRejoin': isRejoin,
      };

      final bookingRef = FirebaseDatabase.instance
          .ref()
          .child('bookings')
          .child(user.uid)
          .child(seatKey);
      await bookingRef.update(historyData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
        content: Text("تم تأكيد الحجز! تمت إضافة التفاصيل إلى سجلك. يرجى الانتظار حتى يرد السائق على طلبك."),            backgroundColor: Color(0xFF43C59E),
          ),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/history', (r) => false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل الحجز: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: const Text(
          'تحديد المقاعد',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body:
          _isLoading &&
              seats
                  .isEmpty // Only show loader if we have NO data yet
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF43C59E)),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // 1. Trip Summary Card
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43C59E), // Reverted to Green
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.trip.from,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    widget.trip.time,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: Icon(
                                Icons.arrow_right_alt,
                                color: Colors.white,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    widget.trip.to,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    widget.trip.date,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            UserProfileAvatar(
                              userId: widget.trip.driverId,
                              radius: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.trip.driverName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (widget.trip.vehicleName.isNotEmpty)
                                    Text(
                                      widget.trip.vehicleName,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                selectedSeats.isNotEmpty
                                    ? '${(widget.trip.price * selectedSeats.length).toStringAsFixed(0)} دج'
                                    : '${widget.trip.price.toStringAsFixed(0)} دج',
                                style: const TextStyle(
                                  color: Color(0xFF43C59E),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 2. Legend
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildLegendCircle(Colors.blue.shade800, "ذكر"),
                        _buildLegendCircle(Colors.pink.shade400, "أنثى"),
                        _buildLegendCircle(Colors.orange, "مقعد رضيع"),
                        _buildLegendCircle(Colors.white, "متاح", hasBorder: true),
                      ],
                    ),
                  ),

const SizedBox(height: 20),

                  // 3. Category Selector UI
                 Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Center(
        child: Text(
          "حدد المقعد المراد حجزه",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _buildCategoryToggle('male', "ذكر", Colors.blue.shade800)),
          const SizedBox(width: 8),
          Expanded(child: _buildCategoryToggle('female', "أنثى", Colors.pink.shade400)),
          const SizedBox(width: 8),
          Expanded(child: _buildCategoryToggle('kids', "مقعد رضيع", Colors.orange)),
        ],
      ),
    ],
  ),
),

                  const SizedBox(height: 20),

                  // 4. Vehicle Visualization
                  Center(
                    child: _buildCarLayout(),
                  ),

                  if (selectedSeats.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("تفاصيل الركاب (المقاعد المحددة):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          ...selectedSeats.entries.map((e) {
                            int seatNum = e.key;
                            bool hasLug = e.value['luggage'] == true;
                            String gender = e.value['gender'];
                            String genderLabel = gender == 'male' ? "ذكر" : (gender == 'female' ? "أنثى" : "طفل");
                            
                            return Column(
                              children: [
                                if (widget.trip.allowsLuggage)
                                  CheckboxListTile(
                                    title: Text("مقعد $seatNum ($genderLabel)"),
                                    subtitle: const Text("إضافة أمتعة لهذا الراكب"),
                                    value: hasLug,
                                    onChanged: (val) {
                                      setState(() {
                                        selectedSeats[seatNum]!['luggage'] = val ?? false;
                                      });
                                    },
                                    activeColor: const Color(0xFF43C59E),
                                    controlAffinity: ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                  )
                                else
                                  ListTile(
                                    title: Text("مقعد $seatNum ($genderLabel)"),
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.person, color: e.value['gender'] == 'male' ? Colors.blue.shade800 : (e.value['gender'] == 'female' ? Colors.pink.shade400 : Colors.orange)),
                                  ),
                                const Divider(height: 1),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),

                  if (widget.trip.allowsNegotiation)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.blue.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 5,
                                          spreadRadius: 1,
                                        )
                                      ],
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.remove, color: Colors.black87),
                                      onPressed: () {
                                        setState(() {
                                          if (_negotiationPrice >= 150) {
                                            _negotiationPrice -= 50;
                                          } else {
                                            _negotiationPrice = 100;
                                          }
                                          _suggestedPriceController.text = _negotiationPrice.toString();
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        const Text("سعر الرحلة", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _suggestedPriceController,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                            suffixText: 'دج',
                                            suffixStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: Colors.grey.shade300),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: Colors.grey.shade300),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: const BorderSide(color: Color(0xFF43C59E), width: 2),
                                            ),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              int parsedValue = int.tryParse(value) ?? 0;
                                              // Only strictly enforce >= 100 on the final state or if they try to erase everything?
                                              // It's better to let them type (e.g. '1', '0', '0') and enforce the minimum when they confirm or leave it. 
                                              // But since we want to prevent less than 100:
                                              _negotiationPrice = parsedValue < 100 && value.isNotEmpty ? parsedValue : (parsedValue == 0 ? 100 : parsedValue);
                                              // Note: If we force 100 immediately on typing '1', they can't type '100'. So we allow intermediate typing.
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF43C59E),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF43C59E).withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        )
                                      ],
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.add, color: Colors.white),
                                      onPressed: () {
                                        setState(() {
                                          _negotiationPrice += 50;
                                          _suggestedPriceController.text = _negotiationPrice.toString();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                          // Promotion Code Section
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _appliedPromoCode != null
                                    ? const Color(0xFF43C59E)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "رمز الخصم",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _promoCodeController,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: InputDecoration(
                                          hintText: 'أدخل الرمز',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: Colors.white,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                          errorText: _promoError,
                                          errorMaxLines: 2,
                                        ),
                                        onChanged: (value) {
                                          if (_promoError != null) {
                                            setState(() => _promoError = null);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: _appliedPromoCode != null
                                          ? null
                                          : _applyPromoCode,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF43C59E,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: _appliedPromoCode != null
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 20,
                                            )
                                          : const Text(
                                              "تطبيق",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                                if (_appliedPromoCode != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: const Color(0xFF43C59E),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_getPromoInfo(_appliedPromoCode!)!['title']} - خصم ${_promoDiscount.toInt()}%',
                                          style: TextStyle(
                                            color: const Color(0xFF43C59E),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _appliedPromoCode = null;
                                              _promoDiscount = 0.0;
                                              _promoCodeController.clear();
                                            });
                                          },
                                          child: const Text(
                                            "إزالة",
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                  const SizedBox(height: 20),

                  // Safety & Legal Guidelines
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              "شروط السلامة والقوانين",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildRuleText("• يُمنع حمل طفل أقل من 3 سنوات في الحضن داخل السيارة."),
                        _buildRuleText("• الأطفال من 3 سنوات فما فوق: يجب الجلوس في مقعد مناسب (مقعد أطفال أو مقعد عادي آمن)."),
                        _buildRuleText("• القاصرون (أقل من 18 سنة): مسموح فقط بإذن من الولي أو مع مرافق بالغ."),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 6. Confirm Footer
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 20,
                          offset: Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "المجموع",
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (_appliedPromoCode != null)
                                    Text(
                                      "${(widget.trip.price * (selectedSeats.isEmpty ? 0 : selectedSeats.length)).toStringAsFixed(0)} دج",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                "${_calculateFinalPrice().toStringAsFixed(0)} دج",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _appliedPromoCode != null
                                      ? const Color(0xFF43C59E)
                                      : Colors.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: selectedSeats.isEmpty
                                ? null
                                : confirmBooking,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading && selectedSeats.isNotEmpty
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    "تأكيد الحجز",
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 
                                        selectedSeats.isEmpty ? 0.5 : 1,
                                      ),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }



  Widget _buildCarLayout() {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(30),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(100),
          bottom: Radius.circular(40),
        ),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Front
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDriverSeat(),
              _buildSeat(1), // Front Passenger
            ],
          ),
          const SizedBox(height: 40),
          // Back
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSeat(2),
              _buildSeat(3),
              _buildSeat(4),
              // Handle Van (has 7 seats) logic if needed
              if (numberOfSeats > 5) ...[
                 _buildSeat(5),
                 _buildSeat(6),
              ],
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildDriverSeat() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.directions_car, color: Colors.grey, size: 24),
          SizedBox(height: 4),
          Text(
            "السائق",
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSeat(int index) {
    if (index >= seats.length) return const SizedBox(width: 50, height: 50);

    final seat = seats[index];
    final isSelected = selectedSeats.containsKey(index);
    final selectedGender = selectedSeats[index]?['gender']?.toString();
    final seatColor = getSeatColor(seat, index);

    return GestureDetector(
      onTap: seat.isTaken ? null : () => toggleSeatSelection(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: seatColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: seatColor.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [],
        ),
        child: Center(
          child: isSelected
              ? (selectedGender == 'kids'
                    ? const Tooltip(
                        message: "مقعد رضيع (siège auto)",
                        child: _BabySeatIcon(color: Colors.white),
                      )
                    : const Icon(Icons.close, color: Colors.white, size: 20))
              : (seat.isTaken
                    ? (seat.gender == 'kids'
                        ? const Tooltip(
                            message: "يجب استخدامه للأطفال دون سن 3 سنوات",
                            child: _BabySeatIcon(color: Colors.white),
                          )
                        : Icon(Icons.close, 
                            color: Colors.white,
                            size: 24))
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 16,
                        ),
                      )
              ),
        ),
      ),
    );
  }

  Widget _buildLegendCircle(Color color, String label, {bool hasBorder = false}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: hasBorder ? Border.all(color: Colors.grey) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildRuleText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.red.shade900,
          height: 1.4,
        ),
      ),
    );
  }
}

class _BabySeatIcon extends StatelessWidget {
  final Color color;
  const _BabySeatIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.event_seat_rounded, color: color, size: 20),
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.95),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.child_care_rounded, size: 8, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
