import 'package:flutter/material.dart';
import '../widgets/message_badge.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../data/wilaya_districts.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/user_profile_avatar.dart';
import '../widgets/history_badge.dart';
import '../services/pricing_service.dart';

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key});

  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  String? selectedFromWilaya;
  String? selectedFromDistrict;
  String? selectedToWilaya;
  String? selectedToDistrict;
  final TextEditingController _packageDetailsController =
      TextEditingController();

  // Package Types
  String selectedPackageType = 'خفيف (0-5 كغ)';
  final List<String> packageTypes = [
    'خفيف (0-5 كغ)',
    'متوسط (5-15 كغ)',
    'ثقيل (15-20 كغ)',
  ];

  // Bottom nav index
  int _currentIndex = 3;

  @override
  void dispose() {
    _packageDetailsController.dispose();
    super.dispose();
  }

  bool _isSearching = false;
  bool _showDrivers = false;

  List<Map<String, dynamic>> _driversList = [];
  DateTime? _deliveryDueDate;

  Future<void> _createPackageBooking(
    Map<String, dynamic> driver,
    String senderName,
    String senderPhone,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userSnap = await FirebaseDatabase.instance.ref().child('users').child(user.uid).get();
    final userData = userSnap.exists ? (userSnap.value as Map<dynamic, dynamic>) : <dynamic, dynamic>{};
    final passengerName = "${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}".trim();
    final tripRef = FirebaseDatabase.instance.ref().child('trips').child(driver['tripId'].toString());
    final takenSeatsRef = tripRef.child('takenSeats');
    final newSeatRef = takenSeatsRef.push();
    final seatKey = newSeatRef.key!;
    
    String loadType = 'خفيف';
    if (selectedPackageType.contains('متوسط')) loadType = 'متوسط';
    if (selectedPackageType.contains('ثقيل')) loadType = 'ثقيل';
    
    double finalPrice = driver['packagePrices']?[selectedPackageType] != null
        ? (driver['packagePrices'][selectedPackageType] as num).toDouble()
        : PricingService.calculateFinalDeliveryPrice(selectedFromWilaya ?? '', selectedToWilaya ?? '', loadType);

    if (PricingService.isVerifiedStudent(userData) &&
        (selectedFromWilaya ?? '') != (selectedToWilaya ?? '')) {
      finalPrice = PricingService.applyVerifiedStudentDiscount(finalPrice);
    }

    final bookingData = {
      'userId': user.uid,
      'userName': passengerName,
      'senderName': senderName,
      'senderPhone': senderPhone,
      'hasPackage': true,
      'isDelivery': true,
      'packageType': selectedPackageType,
      'packageDetails': _packageDetailsController.text.trim(),
      'basePrice': finalPrice,
      'price': finalPrice,
      'status': 'pending',
      'bookingTime': ServerValue.timestamp,
      'bookingKey': seatKey,
      'from': selectedFromWilaya ?? '',
      'to': selectedToWilaya ?? '',
      'driverSeen': false,
    };
    
    await newSeatRef.set(bookingData);

    final bookingRef = FirebaseDatabase.instance.ref().child('bookings').child(user.uid).child(seatKey);
    await bookingRef.set({
      'tripId': driver['tripId'],
      'driverId': driver['driverId'],
      'driverName': driver['name'],
      'from': selectedFromWilaya ?? '',
      'to': selectedToWilaya ?? '',
      'date': _deliveryDueDate != null
          ? "${_deliveryDueDate!.day}/${_deliveryDueDate!.month}/${_deliveryDueDate!.year}"
          : '',
      'time': '',
      'status': 'pending',
      'hasPackage': true,
      'packageType': selectedPackageType,
      'packageDetails': _packageDetailsController.text.trim(),
      'senderName': senderName,
      'senderPhone': senderPhone,
      'basePrice': finalPrice,
      'price': finalPrice,
      'commissionAmount': PricingService.calculateCommission(finalPrice),
      'transportType': 'package',
      'username': passengerName,
      'bookingTimestamp': ServerValue.timestamp,
      'seatKey': seatKey,
      'passengerSeen': true,
    });
  }
  DateTime? _parseTripDate(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return null;
    final txt = rawDate.trim();
    try {
      if (txt.contains('-')) {
        return DateTime.parse(txt);
      }
      final parts = txt.split('/');
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]) ?? 1;
        final month = int.tryParse(parts[1]) ?? 1;
        final year = int.tryParse(parts[2]) ?? 2000;
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseTripDateTime(String? rawDate, String? rawTime) {
    final date = _parseTripDate(rawDate);
    if (date == null || rawTime == null || rawTime.trim().isEmpty) return null;

    var time = rawTime.trim().toUpperCase();
    time = time.replaceAll('ص', 'AM').replaceAll('م', 'PM');
    time = time.replaceAll(RegExp(r'\s+'), ' ');

    final match = RegExp(r'^(\d{1,2}):(\d{1,2})(?:\s*(AM|PM))?$').firstMatch(time);
    if (match == null) {
      return DateTime(date.year, date.month, date.day, 23, 59);
    }

    int hour = int.tryParse(match.group(1) ?? '') ?? 0;
    final int minute = int.tryParse(match.group(2) ?? '') ?? 0;
    final suffix = match.group(3);

    if (suffix != null) {
      if (suffix == 'PM' && hour < 12) hour += 12;
      if (suffix == 'AM' && hour == 12) hour = 0;
    }

    return DateTime(date.year, date.month, date.day, hour.clamp(0, 23), minute.clamp(0, 59));
  }

  void _searchDrivers() async {
    if (selectedFromWilaya == null || selectedToWilaya == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء اختيار المواقع')));
      return;
    }

    if (_deliveryDueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء تحديد تاريخ التسليم الأقصى')));
      return; 
    }
    setState(() {
      _isSearching = true;
      _showDrivers = false;
      _driversList = [];
    });

    try {
      final snap = await FirebaseDatabase.instance.ref().child('trips').get();
      if (snap.exists) {
        final data = snap.value as Map<dynamic, dynamic>;
        final List<Map<String, dynamic>> foundTrips = [];
        
        for (var entry in data.entries) {
          final key = entry.key.toString();
          final val = entry.value as Map<dynamic, dynamic>;
          
          final status = val['status']?.toString() ?? '';
          if (!(status == 'active' || status == 'full' || status == 'starting')) continue;

          // Keep trip available for package delivery as long as its departure
          // date has not passed yet (ignore trip hour).
          final tripDate = _parseTripDate(val['date']?.toString());
          if (tripDate != null) {
             final tripDateOnly = DateTime(tripDate.year, tripDate.month, tripDate.day);
             final now = DateTime.now();
             final nowDateOnly = DateTime(now.year, now.month, now.day);
             if (nowDateOnly.isAfter(tripDateOnly)) continue;
          }

          final fromWilaya = val['fromWilaya']?.toString() ?? '';
          final toWilaya = val['toWilaya']?.toString() ?? '';
          
          if (fromWilaya != selectedFromWilaya || toWilaya != selectedToWilaya) continue;

          bool allowsPackages = val['allowsPackages'] == true;
          if (!allowsPackages) continue;
          
          Map? acceptedPackages = val['acceptedPackages'] as Map?;
          if (acceptedPackages == null || acceptedPackages[selectedPackageType] != true) continue;

          if (tripDate == null) continue;
          final tripDateOnly = DateTime(tripDate.year, tripDate.month, tripDate.day);
          final dueDateOnly = DateTime(
            _deliveryDueDate!.year,
            _deliveryDueDate!.month,
            _deliveryDueDate!.day,
          );
          if (tripDateOnly.isBefore(dueDateOnly)) continue;

          final driverId = val['driverId']?.toString() ?? '';
          if (driverId.isEmpty) continue;
          
          final dSnap = await FirebaseDatabase.instance.ref().child('users').child(driverId).get();
          if (!dSnap.exists) continue;
          
          final dData = dSnap.value as Map<dynamic, dynamic>;

          double rating = (dData['rating'] as num?)?.toDouble() ?? 0.0;
          int ratingCount = (dData['ratingCount'] as num?)?.toInt() ?? 0;

          String loadTypeForDriver = 'خفيف';
          if (selectedPackageType.contains('متوسط')) loadTypeForDriver = 'متوسط';
          if (selectedPackageType.contains('ثقيل')) loadTypeForDriver = 'ثقيل';
          
          Map? packagePrices = val['packagePrices'] as Map?;
          double baseTripPrice = (val['price'] as num?)?.toDouble() ?? 0.0;
          double calculatedPackagePrice = PricingService.calculateFinalDeliveryPrice(fromWilaya, toWilaya, loadTypeForDriver);
          double customPackagePrice = packagePrices?[selectedPackageType] != null ? (packagePrices![selectedPackageType] as num).toDouble() : calculatedPackagePrice;

          foundTrips.add({
             'tripId': key,
             'driverId': driverId,
             'name': val['driverName']?.toString() ?? 'سائق',
             'car': val['vehicleName']?.toString() ?? val['carType']?.toString() ?? 'مركبة',
             'rating': double.parse(rating.toStringAsFixed(1)),
             'ratingCount': ratingCount,
             'time': "${val['date']} ${val['time']}",
             'tripDate': tripDateOnly, // Add trip date for UI logic
             'price': customPackagePrice, // Show the specific package price for the selected type
             'tripBasePrice': baseTripPrice, // Passenger transport base price
             'acceptedPackages': acceptedPackages,
             'packagePrices': packagePrices,
          });
        }
        
        // Deduplicate by driverId
        final Map<String, Map<String, dynamic>> uniqueDrivers = {};
        for (var trip in foundTrips) {
           final dId = trip['driverId'].toString();
           if (!uniqueDrivers.containsKey(dId)) {
               uniqueDrivers[dId] = trip;
           } else {
               // Keep the trip that is earlier
               final existingDate = uniqueDrivers[dId]!['tripDate'] as DateTime;
               final newDate = trip['tripDate'] as DateTime;
               if (newDate.isBefore(existingDate)) {
                   uniqueDrivers[dId] = trip;
               }
           }
        }
        final List<Map<String, dynamic>> deduplicatedTrips = uniqueDrivers.values.toList();
        
        if (mounted) {
           setState(() {
              _driversList = deduplicatedTrips;
              _showDrivers = true;
              _isSearching = false;
           });
        }
      } else {
        if (mounted) {
           setState(() { _isSearching = false; _showDrivers = true; });
        }
      }
    } catch(e) {
      if (mounted) {
        setState(() { _isSearching = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في البحث: $e')));
      }
    }
  }

  void _showSenderInfoDialog(Map<String, dynamic> driver) {
    final senderNameController = TextEditingController();
    final senderPhoneController = TextEditingController();
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "إرسال مع ${driver['name']}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: senderNameController,
                decoration: const InputDecoration(
                  labelText: "إسم و لقب المستلم",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: senderPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "رقم هاتف المستلم",
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (senderNameController.text.trim().isEmpty || senderPhoneController.text.trim().isEmpty) {
                      setModalState(() {
                        errorMessage = "يرجى إدخال اسم ورقم هاتف المستلم";
                      });
                      return;
                    }

                    final phone = senderPhoneController.text.trim();
                    bool has10Digits = phone.length == 10 && RegExp(r'^\d+$').hasMatch(phone);
                    bool validStart = phone.startsWith('05') || phone.startsWith('06') || phone.startsWith('07');

                    if (!has10Digits && !validStart) {
                      setModalState(() {
                        errorMessage = "رقم الهاتف غير صالح. يجب أن يحتوي على 10 أرقام ويبدأ بـ 06 أو 05 أو 07.";
                      });
                      return;
                    } else if (!has10Digits) {
                      setModalState(() {
                        errorMessage = "رقم الهاتف يجب أن يحتوي على 10 أرقام.";
                      });
                      return;
                    } else if (!validStart) {
                      setModalState(() {
                        errorMessage = "رقم الهاتف يجب أن يبدأ بـ 06 أو 05 أو 07.";
                      });
                      return;
                    }
                    
                    setModalState(() {
                      errorMessage = null;
                    });
                    
                    await _createPackageBooking(
                      driver,
                      senderNameController.text.trim(),
                      senderPhoneController.text.trim(),
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("تم إرسال طلب الطرد وسيظهر في سجل الطرود")),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43C59E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("تأكيد الطلب", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
    });

    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (index == 1) {
      Navigator.pushReplacementNamed(context, '/history');
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/messages');
    } else if (index == 3) {
      // Already here
    } else if (index == 4) {
      Navigator.pushReplacementNamed(context, '/discount');
    } else if (index == 5) {
      Navigator.pushNamed(context, '/quran');
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showLogoutConfirmationDialog(context);
    if (shouldLogout != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("تم تسجيل الخروج")));
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacementNamed(context, '/home');
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
      appBar: AppBar(
  backgroundColor: const Color(0xFF43C59E),
  elevation: 0,
  centerTitle: false, // 👈 change this only

  title: const Align(
    alignment: Alignment.centerLeft, // 👈 force left
    child: Text(
      'توصيل',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
    ),
  ),
        actions: const [
          GlobalAppBarActions()
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRouteCard(),
              const SizedBox(height: 16),
              _buildPackageCard(),
              const SizedBox(height: 24),
              if (!_showDrivers)
                ElevatedButton(
                  onPressed: _isSearching ? null : _searchDrivers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSearching
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "البحث عن سائقين متاحين",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              const SizedBox(height: 24),
              if (_showDrivers) ...[
                const Text(
                  "السائقون المتاحون",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 12),
                if (_driversList.isEmpty)
                   const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text("لا توجد رحلات توصيل متاحة في هذا الموعد.", style: TextStyle(color: Colors.grey)),
                   )
                else
                   ..._driversList.map((driver) => _buildDriverCard(driver)),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Directionality(
        textDirection: TextDirection.ltr,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF43C59E),
          unselectedItemColor: Colors.grey,
          onTap: _onBottomNavTapped,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: HistoryBadge(child: Icon(Icons.history)), label: 'السجل'),
            BottomNavigationBarItem(icon: MessageBadge(child: Icon(Icons.message)), label: 'الرسائل'),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping),
              label: 'توصيل',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.discount),
              label: 'خصومات',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book),
              label: 'اقرأ',
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildRouteCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.category, color: Color(0xFF43C59E)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "إلى أين سيذهب الطرد؟",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, color: Color(0xFF43C59E), size: 12),
                  Container(width: 2, height: 40, color: Colors.grey.shade200),
                  const Icon(Icons.location_on, color: Colors.pink, size: 12),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _buildDropdown(
                      hint: "من الولاية",
                      value: selectedFromWilaya,
                      items: wilayaDistricts.keys.toList(),
                      onChanged: (val) => setState(() {
                        selectedFromWilaya = val;
                        selectedFromDistrict = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      hint: "إلى الولاية",
                      value: selectedToWilaya,
                      items: wilayaDistricts.keys.toList(),
                      onChanged: (val) => setState(() {
                        selectedToWilaya = val;
                        selectedToDistrict = null;
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "تفاصيل الطرد",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "نوع الطرد",
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: packageTypes.map((type) {
                final isSelected = selectedPackageType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: isSelected,
                    selectedColor: const Color(0xFF43C59E),
                    backgroundColor: Colors.grey.shade100,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected
                            ? Colors.transparent
                            : Colors.grey.shade300,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => selectedPackageType = type);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _packageDetailsController,
            decoration: InputDecoration(
              hintText: "الوصف (مثلاً: صندوق ملابس، 5 كغ)",
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.description, color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          // ADD DATE PICKER FOR DELIVERY DATE
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _deliveryDueDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked != null) {
                setState(() => _deliveryDueDate = picked);
                _searchDrivers();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _deliveryDueDate == null 
                        ? "تاريخ تسليم الحزمة الأقصى *" 
                        : "${_deliveryDueDate!.year}-${_deliveryDueDate!.month.toString().padLeft(2, '0')}-${_deliveryDueDate!.day.toString().padLeft(2, '0')}",
                      style: TextStyle(
                          color: _deliveryDueDate == null ? Colors.grey.shade700 : Colors.black87,
                          fontSize: 16
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    Map? acceptedPackages = driver['acceptedPackages'];
    Map? packagePrices = driver['packagePrices'];

    List<Widget> packageWidgets = [];
    if (acceptedPackages != null) {
      if (acceptedPackages['خفيف (0-5 كغ)'] == true) {
        double defaultLight = PricingService.calculateFinalDeliveryPrice(selectedFromWilaya ?? '', selectedToWilaya ?? '', 'خفيف');
        double p = packagePrices?['خفيف (0-5 كغ)']?.toDouble() ?? defaultLight;
        packageWidgets.add(_buildPackagePriceRow('خفيف (0-5 كغ)', p));
      }
      if (acceptedPackages['متوسط (5-15 كغ)'] == true) {
        double defaultMed = PricingService.calculateFinalDeliveryPrice(selectedFromWilaya ?? '', selectedToWilaya ?? '', 'متوسط');
        double p = packagePrices?['متوسط (5-15 كغ)']?.toDouble() ?? defaultMed;
        packageWidgets.add(_buildPackagePriceRow('متوسط (5-15 كغ)', p));
      }
      if (acceptedPackages['ثقيل (15-20 كغ)'] == true) {
        double defaultHeavy = PricingService.calculateFinalDeliveryPrice(selectedFromWilaya ?? '', selectedToWilaya ?? '', 'ثقيل');
        double p = packagePrices?['ثقيل (15-20 كغ)']?.toDouble() ?? defaultHeavy;
        packageWidgets.add(_buildPackagePriceRow('ثقيل (15-20 كغ)', p));
      }
    }

    return InkWell(
      onTap: () => _showSenderInfoDialog(driver),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF43C59E), width: 2),
                  ),
                  child: UserProfileAvatar(
                    userId: driver['driverId']?.toString() ?? '',
                    radius: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver['car'],
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  driver['time']?.toString() ?? '',
                                  style: const TextStyle(color: Color(0xFF43C59E), fontSize: 12, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: StreamBuilder<DatabaseEvent>(
                              stream: FirebaseDatabase.instance
                                  .ref()
                                  .child('users')
                                  .child(driver['driverId'].toString())
                                  .onValue,
                              builder: (context, snapshot) {
                                final data = snapshot.data?.snapshot.value as Map<dynamic, dynamic>?;
                                final liveRating = (data?['rating'] as num?)?.toDouble() ??
                                    (driver['rating'] as num?)?.toDouble() ??
                                    0.0;
                                final liveCount = (data?['ratingCount'] as num?)?.toInt() ??
                                    (driver['ratingCount'] as num?)?.toInt() ??
                                    0;
                                return Text(
                                  "⭐ ${liveRating.toStringAsFixed(1)} ($liveCount) • شريك سائق",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: const [
                 Icon(Icons.inventory_2, color: Colors.orange, size: 18),
                 SizedBox(width: 8),
                 Text("📦 أسعار الطرود", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            ...packageWidgets,
          ],
        ),
      ),
    );
  }

  Widget _buildPackagePriceRow(String title, double price) {
     return Padding(
       padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.spaceBetween,
         children: [
           Expanded(child: Text(title, style: TextStyle(color: Colors.grey.shade800, fontSize: 13), overflow: TextOverflow.ellipsis)),
           Text("${price.toInt()} دج", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
         ],
       ),
     );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        hintText: hint,
      ),
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(e, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildPackageCheckbox(Map? acceptedPackages, String fullType, String label) {
    bool isAccepted = acceptedPackages != null && acceptedPackages[fullType] == true;
    return Container(
       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
       decoration: BoxDecoration(
          color: isAccepted ? const Color(0xFF43C59E).withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isAccepted ? const Color(0xFF43C59E) : Colors.grey.shade300),
       ),
       child: Row(
         children: [
           Expanded(
             child: Text(
               label, 
               style: TextStyle(
                 fontSize: 10, 
                 fontWeight: FontWeight.bold, 
                 color: isAccepted ? const Color(0xFF43C59E) : Colors.grey.shade500
               ),
               overflow: TextOverflow.ellipsis,
             ),
           ),
           const SizedBox(width: 4),
           Icon(
             isAccepted ? Icons.check_circle : Icons.cancel, 
             size: 12, 
             color: isAccepted ? const Color(0xFF43C59E) : Colors.grey.shade400
           )
         ],
       ),
    );
  }
}
