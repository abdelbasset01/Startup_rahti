import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:math';
import '../data/wilaya_districts.dart';
import '../services/role_service.dart';
import '../widgets/logout_confirmation_dialog.dart';
import 'messages_page.dart';
import '../widgets/message_badge.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/user_profile_avatar.dart';
import 'revenue_dashboard_page.dart';
import 'driver_passenger_log_page.dart';
import '../widgets/requests_badge.dart';
import '../services/pricing_service.dart';
import '../services/chat_service.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  int _currentIndex = 0;
  StreamSubscription<DatabaseEvent>? _userSubscription;
  Map<dynamic, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _listenToUserData();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  void _listenToUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userSubscription = FirebaseDatabase.instance.ref().child('users').child(user.uid).onValue.listen((event) {
      if (mounted && event.snapshot.value != null) {
        setState(() {
          _userData = event.snapshot.value as Map<dynamic, dynamic>;
        });
      }
    });
  }

  Future<void> _switchToCustomerMode() async {
    await RoleService.switchRole(context, 'customer');
  }

  Future<void> _logout() async {
    final shouldLogout = await showLogoutConfirmationDialog(context);
    if (shouldLogout != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
  backgroundColor: const Color(0xFF43C59E),
  elevation: 0,
  automaticallyImplyLeading: false,
  centerTitle: true,

  title: const Text(
    'لوحة السائق',
    style: TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600, // softer than bold → more modern
      fontSize: 15, // slightly bigger for hierarchy
    ),
  ),

  actions: const [
    Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: GlobalAppBarActions(isDriverView: true),
    ),
  ],

  // subtle bottom divider for depth
  bottom: PreferredSize(
    preferredSize: Size.fromHeight(1),
    child: Container(
      color: Colors.white.withValues(alpha: 0.1),
      height: 1,
    ),
  ),
),
      body: _getCurrentPage(),
      bottomNavigationBar: Directionality(
        textDirection: TextDirection.ltr,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF43C59E),
          unselectedItemColor: Colors.grey,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.add_road),
              label: 'إنشاء رحلة',
            ),
            BottomNavigationBarItem(icon: RequestsBadge(child: Icon(Icons.inbox)), label: 'الطلبات'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: 'السجل'),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'العمولة و الأرباح'),
            BottomNavigationBarItem(icon: MessageBadge(isDriverMode: true, child: Icon(Icons.message)), label: 'الرسائل'),
          ],
        ),
      ),
    );
  }

  Widget _getCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return const CreateTripPage();
      case 1:
        return const DriverRequestsPage();
      case 2:
        return const DriverHistoryPage();
      case 3:
        return const RevenueDashboardPage();
      case 4:
        return const MessagesPage(isDriverMode: true);
      default:
        return const CreateTripPage();
    }
  }
}


// ------------------------ Create Trip Page ------------------------
class CreateTripPage extends StatefulWidget {
  const CreateTripPage({super.key});

  @override
  State<CreateTripPage> createState() => _CreateTripPageState();
}

class _CreateTripPageState extends State<CreateTripPage> {
  final _formKey = GlobalKey<FormState>();
  String? _fromWilaya;
  String? _fromDistrict;
  String? _toWilaya;
  String? _toDistrict;
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _meetingPointController = TextEditingController();
  String? _selectedDate;
  bool _allowsPackages = false;
  bool _allowsLuggage = false;
  bool _allowsNegotiation = false;
  bool _isCreating = false;
  bool _submitted = false;

  Map<String, bool> _acceptedPackages = {
    'خفيف (0-5 كغ)': false,
    'متوسط (5-15 كغ)': false,
    'ثقيل (15-20 كغ)': false,
  };

  Map<String, double> _packagePrices = {};

  void _updatePackagePrices() {
    setState(() {
       _packagePrices.clear();
    });
  }
  
  String _driverType = 'car';
  int _maxCarSeats = 4;
  bool _isLoadingDriverInfo = true;
  final TextEditingController _totalSeatsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDriverInfo();
  }

  Future<void> _loadDriverInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snap = await FirebaseDatabase.instance.ref().child('users').child(user.uid).get();
      if (snap.exists) {
        final data = snap.value as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
            _driverType = data['vehicle']?['transportType']?.toString() ?? 'car';
            if (_driverType == 'car') {
              _maxCarSeats = 4; // Strict limit for cars
            } else {
              _maxCarSeats = (data['vehicle']?['availableSeats'] as num?)?.toInt() ?? 4;
            }
            
            if (_driverType == 'car') {
              _totalSeatsController.text = '1'; // Default to 1 seat for car
            } else {
              _totalSeatsController.text = _maxCarSeats.toString();
            }
            _isLoadingDriverInfo = false;
          });
        }
      }
    } else {
      if (mounted) setState(() => _isLoadingDriverInfo = false);
    }
  }

  @override
  void dispose() {
    _timeController.dispose();
    _priceController.dispose();
    _meetingPointController.dispose();
    _totalSeatsController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF43C59E)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
         return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF43C59E)),
          ),
          child: child!,
        );
      }
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _timeController.text = picked.format(context);
    });
  }

  Future<void> _createTrip() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء اختيار تاريخ')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء تسجيل الدخول أولاً')));
      return;
    }

    setState(() => _isCreating = true);

    try {
      final driverSnapshot = await FirebaseDatabase.instance.ref().child('users').child(user.uid).get();
      if (!driverSnapshot.exists) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم يتم العثور على ملف تعريف السائق. الرجاء التسجيل كسائق.')));
        return;
      }

      final driverData = driverSnapshot.value as Map<dynamic, dynamic>;
      final driverName = '${driverData['firstName'] ?? ''} ${driverData['lastName'] ?? ''}'.trim();
      final vehicleMake = driverData['vehicle']?['vehicleMake'] ?? '';
      final vehicleModelName = driverData['vehicle']?['vehicleType'] ?? '';
      final vehicleName = '$vehicleMake $vehicleModelName'.trim();

      final tripRef = FirebaseDatabase.instance.ref().child('trips').push();
      final tripId = tripRef.key!;

      await tripRef.set({
        // Exact unified structure
        'driverId': user.uid,
        'from': '${_fromDistrict ?? ''}, ${_fromWilaya ?? ''}'.trim(),
        'to': '${_toDistrict ?? ''}, ${_toWilaya ?? ''}'.trim(),
        'date': _selectedDate,
        'time': _timeController.text.trim(),
        'price': double.tryParse(_priceController.text.trim()) ?? 0.0,
        'availableSeats': int.tryParse(_totalSeatsController.text.trim()) ?? 1,
        'carType': driverData['vehicle']?['vehicleType'] ?? 'Car',
        'totalSeats': int.tryParse(_totalSeatsController.text.trim()) ?? 1,
        'status': 'active', // active / finished / cancelled
        'createdAt': ServerValue.timestamp,
        'seats': <String, dynamic>{},

        // Preserved for legacy app compatibility 
        'id': tripId,
        'driverName': driverName,
        'vehicleName': vehicleName,
        'fromWilaya': _fromWilaya,
        'fromDistrict': _fromDistrict,
        'toWilaya': _toWilaya,
        'toDistrict': _toDistrict,
        'allowsPackages': _allowsPackages,
        'allowsLuggage': _allowsLuggage,
        'allowsNegotiation': _allowsNegotiation,
        'acceptedPackages': _allowsPackages ? _acceptedPackages : null,
        'packagePrices': _allowsPackages ? _packagePrices : null,
        'transport_type': _driverType,
        'meetingPoint': _meetingPointController.text.trim(),
      });

      setState(() {
        _isCreating = false;
        _submitted = false;
        _fromWilaya = null;
        _fromDistrict = null;
        _toWilaya = null;
        _toDistrict = null;
        _selectedDate = null;
        _timeController.clear();
        _priceController.clear();
        _meetingPointController.clear();
        if (_driverType == 'car') {
           _totalSeatsController.text = '1';
        } else {
           _totalSeatsController.text = '4'; 
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء الرحلة بنجاح!'), backgroundColor: Color(0xFF43C59E)),
      );

    } catch (e) {
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDriverInfo) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF43C59E)));
    }
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Form(
        key: _formKey,
        autovalidateMode: _submitted ? AutovalidateMode.always : AutovalidateMode.disabled,
        child: Column(
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF43C59E), Color(0xFF43C59E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF43C59E).withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 4)),
                ],
              ),
              child: const Column(
                children: [
                   Icon(Icons.add_road, size: 48, color: Colors.white),
                   SizedBox(height: 12),
                   Text("نشر رحلة جديدة", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                   SizedBox(height: 4),
                   Text("شارك رحلتك واكسب", style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Route Card
            _buildCard(
              title: "تفاصيل المسار",
              icon: Icons.map,
              child: Column(
                children: [
                  _buildDropdownRow("من", Icons.my_location, _fromWilaya, _fromDistrict, 
                    (w) {
                      setState(() { _fromWilaya = w; _fromDistrict = null; });
                      _updatePackagePrices();
                    },
                    (d) => setState(() => _fromDistrict = d),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Icon(Icons.arrow_downward, color: Colors.grey, size: 20),
                  ),
                  _buildDropdownRow("إلى", Icons.location_on, _toWilaya, _toDistrict,
                    (w) {
                      setState(() { _toWilaya = w; _toDistrict = null; });
                      _updatePackagePrices();
                    },
                    (d) => setState(() => _toDistrict = d),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // Schedule & Price Card
            _buildCard(
              title: "الوقت والسعر", 
              icon: Icons.schedule,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectDate,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: _boxDecoration(),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, color: Colors.grey),
                                const SizedBox(width: 10),
                                Text(_selectedDate ?? "اختر التاريخ", style: TextStyle(color: _selectedDate == null ? Colors.grey[600] : Colors.black)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectTime,
                           child: AbsorbPointer(
                             child: TextFormField(
                               controller: _timeController,
                               decoration: _inputDecoration("الوقت", Icons.access_time),
                               validator: (v) => v!.isEmpty ? "مطلوب" : null,
                             ),
                           ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration("سعر المقعد (دج)", Icons.attach_money),
                    validator: (v) => v!.isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _meetingPointController,
                    decoration: _inputDecoration("نقطة الالتقاء (اختياري)", Icons.meeting_room),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Preferences Card
            _buildCard(
              title: "الخيارات والتفضيلات",
              icon: Icons.tune,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                     children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                             color: const Color(0xFF43C59E).withValues(alpha: 0.1),
                             borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                             "🚗 سيارة", 
                             style: TextStyle(
                               fontWeight: FontWeight.bold, 
                               color: Color(0xFF1E824C),
                             ),
                          ),
                        ),
                     ],
                   ),
                   const SizedBox(height: 16),
                   if (_driverType == 'car') 
                     DropdownButtonFormField<String>(
                        initialValue: _totalSeatsController.text.isEmpty ? '1' : _totalSeatsController.text,
                        decoration: _inputDecoration("Available Passenger Seats", Icons.event_seat),
                        items: ['1', '2', '3', '4'].map((s) => DropdownMenuItem(
                          value: s, 
                          child: Text("$s مقاعد")
                        )).toList(),
                        onChanged: (v) {
                          setState(() {
                            _totalSeatsController.text = v ?? '1';
                          });
                        },
                        validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
                     )
                   else
                     TextFormField(
                       controller: _totalSeatsController,
                       keyboardType: TextInputType.number,
                       decoration: _inputDecoration(
                         "المقاعد المتاحة (الحد الأقصى: $_maxCarSeats)", 
                         Icons.event_seat
                       ),
                       validator: (v) {
                         if (v == null || v.isEmpty) return "مطلوب";
                         final seats = int.tryParse(v);
                         if (seats == null || seats <= 0) return "رقم غير صالح";
                         if (seats > _maxCarSeats) return "لا يمكن تجاوز $_maxCarSeats مقاعد لهذه السيارة";
                         return null;
                       },
                     ),
                   const SizedBox(height: 16),
                   const Divider(height: 1),
                   _buildSwitchTile("قبول الأمتعة", "السماح للركاب باصطحاب أمتعة حقائب أو غيرها", _allowsLuggage, (v) {
                     setState(() => _allowsLuggage = v);
                   }),

                  _buildSwitchTile("السماح بالتفاوض", "السماح للركاب باقتراح سعر", _allowsNegotiation, (v) {
                    setState(() => _allowsNegotiation = v);
                    if (v) _updatePackagePrices();
                  }),
                   const Divider(height: 1),
                   _buildSwitchTile("توصيل طرود", "أوافق على نقل الطرود المنفصلة وتوصيلها", _allowsPackages, (v) {
                     setState(() => _allowsPackages = v);
                     if (v) _updatePackagePrices();
                   }),
                ],
              ),
            ),

            if (_allowsPackages && _fromWilaya != null && _toWilaya != null)
              Column(
                children: [
                  const SizedBox(height: 20),
                  _buildCard(
                    title: "أنواع الطرود المقبولة",
                    icon: Icons.inventory_2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("حدد أنواع الطرود التي تقبلها والسعر المحسوب لكل نوع:", style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                        const SizedBox(height: 16),
                        _buildPackageToggleSwitch('خفيف (0-5 كغ)'),
                        const Divider(),
                        _buildPackageToggleSwitch('متوسط (5-15 كغ)'),
                        const Divider(),
                        _buildPackageToggleSwitch('ثقيل (15-20 كغ)'),
                      ],
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 5,
                  shadowColor: Colors.black26,
                ),
                child: _isCreating 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text("نشر الرحلة", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF43C59E).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: const Color(0xFF43C59E), size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildDropdownRow(String label, IconData icon, String? wilaya, String? district, Function(String?) onWilayaChanged, Function(String?) onDistrictChanged) {
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         DropdownButtonFormField<String>(
            initialValue: wilaya,
            decoration: _inputDecoration("$label الولاية", icon),
            items: wilayaDistricts.keys.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
            onChanged: onWilayaChanged,
            validator: (v) => v == null ? 'مطلوب' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: district,
            decoration: _inputDecoration("$label الدائرة", Icons.location_city),
            items: (wilaya == null ? <String>[] : wilayaDistricts[wilaya] ?? []).map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: onDistrictChanged,
            validator: (v) => v == null ? 'مطلوب' : null,
          ),
       ],
     );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      value: value,
      onChanged: onChanged,
      activeThumbColor: const Color(0xFF43C59E),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildPackageToggleSwitch(String title) {
    bool isAccepted = _acceptedPackages[title] ?? false;
    
    String loadType = 'خفيف';
    if (title.contains('متوسط')) loadType = 'متوسط';
    if (title.contains('ثقيل')) loadType = 'ثقيل';

    double basePrice = PricingService.calculateFinalDeliveryPrice(_fromWilaya!, _toWilaya!, loadType);
    double currentPrice = _packagePrices[title] ?? basePrice;
    
    return Column(
      children: [
        SwitchListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: isAccepted 
             ? Text(
                "السعر: ${currentPrice.toInt()} دج", 
                style: const TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold),
               )
             : const Text("غير مفعل"),
          value: isAccepted,
          onChanged: (v) {
            setState(() {
              _acceptedPackages[title] = v;
              if (v && !_packagePrices.containsKey(title)) {
                _packagePrices[title] = basePrice;
              }
            });
          },
          activeThumbColor: const Color(0xFF43C59E),
          contentPadding: EdgeInsets.zero,
        ),
        if (isAccepted)
          Row(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               IconButton(
                 icon: const Icon(Icons.remove_circle_outline, color: Colors.blue),
                 onPressed: () {
                   setState(() {
                      double newPrice = currentPrice - 100;
                      if (newPrice >= PricingService.getMinPrice(basePrice)) {
                         _packagePrices[title] = newPrice;
                      } else {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الحد الأدنى للسعر هو ${PricingService.getMinPrice(basePrice).toInt()} دج')));
                      }
                   });
                 },
               ),
               Text('${currentPrice.toInt()} دج', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
               IconButton(
                 icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                 onPressed: () {
                   setState(() {
                      double newPrice = currentPrice + 100;
                      if (newPrice <= PricingService.getMaxPrice(basePrice)) {
                         _packagePrices[title] = newPrice;
                      } else {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الحد الأقصى للسعر هو ${PricingService.getMaxPrice(basePrice).toInt()} دج')));
                      }
                   });
                 },
               ),
             ],
          ),
      ]
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.grey.shade50,
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(12),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43C59E), width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

// ------------------------ Driver Requests Page ------------------------
class DriverRequestsPage extends StatefulWidget {
  const DriverRequestsPage({super.key});

  @override
  State<DriverRequestsPage> createState() => _DriverRequestsPageState();
}

class _DriverRequestsPageState extends State<DriverRequestsPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _pendingRequests = []; 
  List<Map<String, dynamic>> _lostItems = [];
  StreamSubscription<DatabaseEvent>? _requestsSubscription;
  StreamSubscription<DatabaseEvent>? _lostItemsSubscription;
  bool _isLoading = true;
  late TabController _tabController;

  bool _isDeliveryObj(Map data) => data['isDelivery'] == true || data['transportType'] == 'package' || data['packageType'] != null;

  void _markSeenForActiveTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (_pendingRequests.isEmpty && _lostItems.isEmpty)) return;
    
    final int safeIndex = _tabController.index;

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted || _tabController.index != safeIndex) return;

      bool requiresUpdate = false;
      if (safeIndex == 0 || safeIndex == 1) {
        for (var r in _pendingRequests) {
          final seatData = r['seatData'] as Map<dynamic, dynamic>;
          if (seatData['driverSeen'] == false) {
            bool isPkg = _isDeliveryObj(seatData);
            if ((safeIndex == 0 && !isPkg) || (safeIndex == 1 && isPkg)) {
              FirebaseDatabase.instance.ref()
                 .child('trips')
                 .child(r['tripId'])
                 .child('takenSeats')
                 .child(r['seatKey'])
                 .update({'driverSeen': true});
              seatData['driverSeen'] = true;
              requiresUpdate = true;
            }
          }
        }
      } else if (safeIndex == 2) {
        for (var item in _lostItems) {
           if (item['driverSeen'] == false) {
              FirebaseDatabase.instance.ref()
                 .child('forgottenItems')
                 .child(user.uid)
                 .child(item['id'])
                 .update({'driverSeen': true});
              item['driverSeen'] = true;
              requiresUpdate = true;
           }
        }
      }
      
      if (requiresUpdate && mounted) {
        setState(() {});
      }
    });
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    _markSeenForActiveTab();
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int _asIntTimestamp(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _initializeData();
  }

  Future<void> _initializeData() async {
    _loadRequests();
    _loadLostItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _requestsSubscription?.cancel();
    _lostItemsSubscription?.cancel();
    super.dispose();
  }

  void _loadRequests() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _requestsSubscription = FirebaseDatabase.instance
        .ref()
        .child('trips')
        .orderByChild('driverId')
        .equalTo(user.uid)
        .onValue
        .listen((event) {
          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          if (data == null) {
            if (mounted) setState(() { _pendingRequests = []; _isLoading = false; });
            return;
          }

          final List<Map<String, dynamic>> loadedRequests = [];

          data.forEach((tripKey, tripValue) {
            if (tripValue is! Map<dynamic, dynamic>) return;
            final tripData = tripValue;
            final takenSeats = tripData['takenSeats'];

            if (takenSeats is Map<dynamic, dynamic>) {
              takenSeats.forEach((seatKey, seatValue) {
                if (seatValue is! Map<dynamic, dynamic>) return;
                
                final seatData = seatValue;
                final status = seatData['status']?.toString() ?? 'booked';

                if (status == 'booked' || status == 'pending' || status == 'passenger_countered') {

                   final sortTs = _asIntTimestamp(seatData['bookingTime']) > 0
                       ? _asIntTimestamp(seatData['bookingTime'])
                       : (_asIntTimestamp(seatData['timestamp']) > 0
                           ? _asIntTimestamp(seatData['timestamp'])
                           : _asIntTimestamp(tripData['createdAt']));
                   loadedRequests.add({
                     'tripId': tripKey,
                     'seatKey': seatKey,
                     'tripData': tripData,
                     'seatData': seatData,
                     'timestamp': sortTs,
                   });
                }
              });
            }
          });

          loadedRequests.sort((a, b) =>
              _asIntTimestamp(b['timestamp']).compareTo(_asIntTimestamp(a['timestamp'])));

          if (mounted) {
            setState(() {
              _pendingRequests = loadedRequests;
              _isLoading = false;
            });
            _markSeenForActiveTab();
          }
        });
  }

  void _loadLostItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _lostItemsSubscription = FirebaseDatabase.instance
        .ref()
        .child('forgottenItems')
        .child(user.uid)
        .onValue
        .listen((event) {
          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          if (data == null) {
            if (mounted) setState(() { _lostItems = []; });
            return;
          }

          final List<Map<String, dynamic>> items = [];
          data.forEach((key, value) {
            final itemData = Map<String, dynamic>.from(value as Map);
            items.add(itemData);
          });

          items.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

          if (mounted) {
            setState(() {
              _lostItems = items;
            });
          }
        });
  }

  Future<void> _updateLostItemStatus(String itemId, String newStatus) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseDatabase.instance
          .ref()
          .child('forgottenItems')
          .child(user.uid)
          .child(itemId)
          .update({
            'status': newStatus,
            'passengerSeen': false,
            'driverSeen': true,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تغيير حالة العنصر كـ $newStatus'),
            backgroundColor: newStatus == 'Found' ? const Color(0xFF43C59E) : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _handleRequest(String tripId, String seatKey, String userId, String actionStatus) async {
    try {
      final status = actionStatus;
      
      final seatSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('trips')
          .child(tripId)
          .child('takenSeats')
          .child(seatKey)
          .get();
      
      if (!seatSnapshot.exists) return;
      
      final seatData = seatSnapshot.value as Map<dynamic, dynamic>;
      final tripSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('trips')
          .child(tripId)
          .get();
      
      if (!tripSnapshot.exists) return;
      
      final tripData = tripSnapshot.value as Map<dynamic, dynamic>;
      
      double finalPrice = 0.0;
      if (status == 'accepted' && seatData['suggestedPrice'] != null) {
        finalPrice = (seatData['suggestedPrice'] as num).toDouble();
      } else if (seatData['totalPrice'] != null) {
        finalPrice = (seatData['totalPrice'] as num).toDouble();
      } else {
        final tripPrice = (tripData['price'] as num?)?.toDouble() ?? 0.0;
        final seatsBooked = (seatData['seats'] as num?)?.toInt() ?? (seatData['seatsBooked'] as num?)?.toInt() ?? 1;
        finalPrice = tripPrice * seatsBooked;
      }
      
      bool isDelivery = seatData['isDelivery'] == true || seatData['transportType'] == 'package' || seatData['packageType'] != null;
      String? generatedOtp;
      if (status == 'accepted' && isDelivery) {
        generatedOtp = (100000 + Random().nextInt(900000)).toString();
      }

      Map<String, dynamic> seatUpdates = {'status': status};
      Map<String, dynamic> bookingUpdates = {
        'status': status,
        'price': finalPrice,
        'suggestedPrice': seatData['suggestedPrice'],
        'commissionAmount': PricingService.calculateCommission(finalPrice),
        'seats': seatData['seats'] ?? (seatData['seatsBooked'] as num?)?.toInt(),
        'seatKey': seatKey,
        'passengerSeen': false,
      };

      if (status == 'accepted') {
        bookingUpdates['removedByDriver'] = null;
      }

      if (generatedOtp != null) {
        seatUpdates['otp'] = generatedOtp;
        seatUpdates['deliveryStatus'] = 'pending_delivery';
        bookingUpdates['otp'] = generatedOtp;
        bookingUpdates['deliveryStatus'] = 'pending_delivery';
      }

      await FirebaseDatabase.instance
          .ref()
          .child('trips')
          .child(tripId)
          .child('takenSeats')
          .child(seatKey)
          .update(seatUpdates);

      final bookingRef = FirebaseDatabase.instance.ref().child('bookings').child(userId).child(seatKey);
      await bookingRef.update(bookingUpdates);

      if (status == 'accepted') {
        // If it's a rejoin request or the passenger was previously removed, restore their chat access
        if (seatData['isRejoin'] == true) {
          await chatService.restorePassengerChat(tripId, userId);
        } else {
          final chatStatusSnap = await FirebaseDatabase.instance.ref().child('trips').child(tripId).child('chatStatus').child(userId).get();
          if (chatStatusSnap.exists && (chatStatusSnap.value == 'removed' || chatStatusSnap.value == 'deleted')) {
            await chatService.restorePassengerChat(tripId, userId);
          }
        }
      }

      if (status == 'refused') {
        final tripRef = FirebaseDatabase.instance.ref().child('trips').child(tripId);
        final tripSnap = await tripRef.get();
        if (tripSnap.exists) {
          final tData = tripSnap.value as Map<dynamic, dynamic>;
          int currentAvailable = int.tryParse(tData['availableSeats']?.toString() ?? '0') ?? 0;
          final seatsBooked = (seatData['seats'] as num?)?.toInt() ?? (seatData['seatsBooked'] as num?)?.toInt() ?? 1;

          // Remove seat indices
          List<dynamic> existingIndices = [];
          if (tData['bookedSeatIndices'] != null && tData['bookedSeatIndices'] is List) {
            existingIndices = List<dynamic>.from(tData['bookedSeatIndices'] as List<dynamic>);
          }
          if (seatData['seatIndices'] != null && seatData['seatIndices'] is List) {
            final indicesToRemove = List<dynamic>.from(seatData['seatIndices'] as List<dynamic>);
            for (var index in indicesToRemove) {
              existingIndices.remove(index);
            }
          }

          await tripRef.update({
            'availableSeats': currentAvailable + seatsBooked,
            'bookedSeatIndices': existingIndices,
          });

          // Delete from takenSeats entirely so it doesn't show in passenger lists
          await tripRef.child('takenSeats').child(seatKey).remove();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'accepted' ? 'تم قبول الطلب' : (status == 'refused' ? 'تم رفض الطلب' : 'تم تعيينه كقيد الانتظار')),
            backgroundColor: status == 'accepted' ? const Color(0xFF43C59E) : (status == 'refused' ? Colors.red : Colors.orange),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF43C59E)));
    }

    final passengerUnseenCount = _pendingRequests.where((r) => !_isDeliveryObj(r['seatData']) && (r['seatData']['driverSeen'] == false || r['seatData']['driverSeen'] == null)).length;
    final packageUnseenCount = _pendingRequests.where((r) => _isDeliveryObj(r['seatData']) && (r['seatData']['driverSeen'] == false || r['seatData']['driverSeen'] == null)).length;
    final lostUnseenCount = _lostItems.where((r) => r['driverSeen'] == false).length;

    final passengerRequests = _pendingRequests.where((r) => !_isDeliveryObj(r['seatData'])).toList();
    final packageRequests = _pendingRequests.where((r) => _isDeliveryObj(r['seatData'])).toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            labelColor: const Color(0xFF43C59E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF43C59E),
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("الركاب"),
                    if (passengerUnseenCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(passengerUnseenCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    ]
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("الطرود"),
                    if (packageUnseenCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(packageUnseenCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    ]
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("العناصر المفقودة"),
                    if (lostUnseenCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(lostUnseenCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildRequestsList(passengerRequests, "لا توجد طلبات ركاب"),
              _buildRequestsList(packageRequests, "لا توجد طلبات طرود"),
              _buildLostItemsList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsList(List<Map<String, dynamic>> requests, String emptyMessage) {
    if (requests.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        return _buildRequestCard(requests[index]);
      },
    );
  }

  Widget _buildLostItemsList() {
    if (_lostItems.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _lostItems.length,
      itemBuilder: (context, index) {
        final item = _lostItems[index];
        final isResolved = item['status'] != 'Pending';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isResolved ? Colors.grey.shade50 : Colors.orange.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.help_outline, color: isResolved ? Colors.grey : Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "مُبلَّغ عنه بواسطة ${item['passengerName']} - ${item['date']}",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isResolved ? Colors.grey.shade700 : Colors.orange.shade800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item['status'] == 'Pending' ? 'قيد الانتظار' : (item['status'] == 'Found' ? 'تم العثور عليه' : 'لم يتم العثور عليه'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: item['status'] == 'Found' ? const Color(0xFF43C59E) : (item['status'] == 'Not Found' ? Colors.red : Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("الرحلة: ${item['from']} → ${item['to']}", style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text("الوصف: ${item['description']}", style: TextStyle(color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Text("الموقع المحتمل: ${item['location']}", style: TextStyle(color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Text("الاتصال: ${item['passengerPhone']}", style: TextStyle(color: Colors.grey.shade700)),
                    
                    if (!isResolved) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _updateLostItemStatus(item['id'], 'Not Found'),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text("لم يتم العثور عليه", style: TextStyle(color: Colors.red)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _updateLostItemStatus(item['id'], 'Found'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF43C59E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text("تم العثور عليه", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  String _getSeatsDescription(Map<dynamic, dynamic> seatData) {
    int regular = 0;
    int withLuggage = 0;
    int baby = 0;
    int babyWithLuggage = 0;
    int seatsBooked = seatData['seats'] ?? seatData['seatsBooked'] ?? 1;

    final seatIndices = seatData['seatIndices'];
    if (seatIndices != null && ((seatIndices is List && seatIndices.isNotEmpty) || (seatIndices is Map && seatIndices.isNotEmpty))) {
      List<dynamic> indices = seatIndices is List ? seatIndices : seatIndices.values.toList();
      final rawGenders = seatData['seatGenders'];
      Map<dynamic, dynamic> genders = {};
      if (rawGenders is Map) {
        genders = Map<dynamic, dynamic>.from(rawGenders);
      } else if (rawGenders is List) {
        for (int i = 0; i < rawGenders.length; i++) {
          if (rawGenders[i] != null) genders[i.toString()] = rawGenders[i];
        }
      }

      final rawLuggages = seatData['seatLuggage'];
      Map<dynamic, dynamic> luggages = {};
      if (rawLuggages is Map) {
        luggages = Map<dynamic, dynamic>.from(rawLuggages);
      } else if (rawLuggages is List) {
        for (int i = 0; i < rawLuggages.length; i++) {
          if (rawLuggages[i] != null) luggages[i.toString()] = rawLuggages[i];
        }
      }
      
      for (var idx in indices) {
        String gender = genders[idx.toString()]?.toString() ?? genders[idx]?.toString() ?? 'male';
        bool luggage = luggages[idx.toString()] == true || luggages[idx] == true;
        if (gender == 'kids') {
          if (luggage) babyWithLuggage++;
          else baby++;
        } else if (luggage) {
          withLuggage++;
        } else {
          regular++;
        }
      }
    } else {
      String gender = seatData['gender']?.toString() ?? 'male';
      bool hasPackage = seatData['hasPackage'] == true;
      if (gender == 'kids') {
         if (hasPackage) {
           babyWithLuggage = 1;
           baby = seatsBooked > 1 ? seatsBooked - 1 : 0;
         } else {
           baby = seatsBooked;
         }
      } else if (hasPackage) {
         withLuggage = 1;
         regular = seatsBooked > 1 ? seatsBooked - 1 : 0;
      } else {
         regular = seatsBooked;
      }
    }

    List<String> parts = [];
    if (regular > 0) parts.add("\u200F$regular مقعد عادي");
    if (withLuggage > 0) parts.add("\u200F$withLuggage مقعد مع أمتعة");
    if (baby > 0) parts.add("\u200F$baby مقعد طفل");
    if (babyWithLuggage > 0) parts.add("\u200F$babyWithLuggage مقعد طفل مع أمتعة");

    if (parts.isEmpty) return "\u200F$seatsBooked مقعد عادي";
    return parts.join(" و ");
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final tripData = req['tripData'];
    final seatData = req['seatData'];
    final passengerName = seatData['userName'] ?? 'راكب';
    final seatsBooked = seatData['seats'] ?? seatData['seatsBooked'] ?? 1;
    final hasPackage = seatData['hasPackage'] == true;
    final isDelivery = seatData['isDelivery'] == true ||
        seatData['transportType'] == 'package' ||
        seatData['packageType'] != null;
    final suggestedPrice = seatData['suggestedPrice'];
    final bool hasNegotiation = seatData['negotiationLog'] != null && (seatData['negotiationLog'] as Map).isNotEmpty;

    String displayTotal = '0';
    if (isDelivery) {
       displayTotal = (suggestedPrice ?? seatData['price'] ?? seatData['totalPrice'] ?? seatData['basePrice'] ?? '0').toString();
    } else {
       displayTotal = (seatData['basePrice'] ?? seatData['totalPrice'] ?? '0').toString();
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                UserProfileAvatar(
                  userId: seatData['userId']?.toString() ?? '',
                  radius: 25,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("$passengerName (${isDelivery ? "مرسل طرد" : "مسافر"})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (seatData['isRejoin'] == true)
                         const Text('طلب إعادة الانضمام للرحلة', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                           if (!isDelivery)
                             const SizedBox(width: 0),
                           Text("•  ${tripData['time']}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        ],
                      ),
                      if (!isDelivery)
                        Text("الإجمالي: $displayTotal دج", style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (suggestedPrice != null && (suggestedPrice as num) > 0)
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                     decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                     child: Column(
                       children: [
                         const Text("طلب تفاوض", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600)),
                         Text("$suggestedPrice دج", style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                         // Calculate difference
                         Builder(
                           builder: (context) {
                             double originalPrice = 0.0;
                             if (seatData['basePrice'] != null) {
                               originalPrice = (seatData['basePrice'] as num).toDouble();
                             } else if (seatData['totalPrice'] != null) {
                               originalPrice = (seatData['totalPrice'] as num).toDouble();
                             } else if (seatData['price'] != null) {
                               originalPrice = (seatData['price'] as num).toDouble();
                             } else if (tripData['price'] != null) {
                               originalPrice = (tripData['price'] as num).toDouble() * seatsBooked;
                             }
                             
                             if (originalPrice > 0) {
                               double diff = (suggestedPrice as num).toDouble() - originalPrice;
                               return Text(
                                 diff >= 0 ? "+${diff.toStringAsFixed(0)} دج" : "-${diff.abs().toStringAsFixed(0)} دج",
                                 style: TextStyle(
                                   color: diff >= 0 ? Colors.green : Colors.red,
                                   fontSize: 10,
                                   fontWeight: FontWeight.bold,
                                 ),
                               );
                             }
                             return const SizedBox.shrink();
                           }
                         ),
                       ],
                     ),
                   )
                else if (seatData['totalPrice'] != null)
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                     decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                     child: Text("${seatData['totalPrice']} دج", style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                   ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),
          if (isDelivery) ...[
             Padding(
               padding: const EdgeInsets.all(20),
               child: Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: Colors.orange.shade50,
                   borderRadius: BorderRadius.circular(12),
                   border: Border.all(color: Colors.orange.shade200),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Row(
                       children: const [
                         Icon(Icons.inventory_2, size: 16, color: Colors.orange),
                         SizedBox(width: 8),
                         Text("تفاصيل الطرد", style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                       ],
                     ),
                     const SizedBox(height: 8),
                     if (seatData['userName'] != null) Text("الاسم الكامل للزبون: ${seatData['userName']} ${seatData['userLastName'] ?? ''}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                     if (seatData['packageDetails'] != null) Text("الوصف: ${seatData['packageDetails']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
                     const SizedBox(height: 4),
                     if (seatData['packageType'] != null) Text("النوع: ${seatData['packageType']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (seatData['senderName'] != null) Text("المستلم: ${seatData['senderName']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (seatData['senderPhone'] != null) Text("هاتف المستلم: ${seatData['senderPhone']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     Text(
                       "السعر: ${_asDouble(suggestedPrice ?? seatData['price'] ?? seatData['totalPrice'] ?? seatData['basePrice']).toStringAsFixed(0)} دج",
                       style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                     ),
                   ],
                 ),
               ),
              ),
             if (seatData['negotiationLog'] != null) ...[
                Builder(
                  builder: (context) {
                    final logsRaw = seatData['negotiationLog'];
                    List<Map<dynamic, dynamic>> logs = [];
                    if (logsRaw is Map) {
                       logsRaw.forEach((key, value) {
                         if (value is Map) logs.add(value);
                       });
                    }
                    if (logs.isEmpty) return const SizedBox.shrink();

                    logs.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.history, size: 16, color: Colors.grey.shade700),
                                const SizedBox(width: 8),
                                Text("سجل التفاوض", style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...logs.map((log) {
                               bool isDriver = log['sender'] == 'driver';
                               return Padding(
                                 padding: const EdgeInsets.only(bottom: 4),
                                 child: Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                   children: [
                                     Text(isDriver ? "عرضك:" : "عرض الراكب:", style: TextStyle(fontSize: 12, color: isDriver ? const Color(0xFF43C59E) : Colors.blue.shade700)),
                                     Text("${log['price']} د.ج", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                   ],
                                 ),
                               );
                            }).toList(),
                          ],
                        ),
                      ),
                    );
                  }
                ),
             ],
             Container(height: 1, color: Colors.grey.shade100),
          ],
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildLocationRow(Icons.radio_button_checked, seatData['from'] ?? tripData['from'] ?? '', const Color(0xFF43C59E)),
                Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(width: 2, height: 10, color: Colors.grey[300]),
                  ),
                ),
                _buildLocationRow(Icons.location_on, seatData['to'] ?? tripData['to'] ?? '', Colors.pink),
                if (!isDelivery) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.airline_seat_recline_normal, size: 16, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getSeatsDescription(seatData),
                          style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => _handleRequest(req['tripId'], req['seatKey'], seatData['userId'], 'refused'),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("رفض", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () => _handleRequest(req['tripId'], req['seatKey'], seatData['userId'], 'pending'),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.orange.shade50,
                      foregroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("قيد الانتظار", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleRequest(req['tripId'], req['seatKey'], seatData['userId'], 'accepted'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43C59E),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text("قبول", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
     return Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Icon(Icons.inbox_outlined, size: 80, color: Colors.grey.shade300),
           const SizedBox(height: 16),
           Text("لا يوجد طلبات جديدة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
           const SizedBox(height: 8),
           Text("ستظهر طلبات الحجز الجديدة هنا", style: TextStyle(color: Colors.grey.shade400)),
         ],
       ),
     );
  }

  Widget _buildLocationRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

// ------------------------ Driver History Page ------------------------
class DriverHistoryPage extends StatefulWidget {
  const DriverHistoryPage({super.key});

  @override
  State<DriverHistoryPage> createState() => _DriverHistoryPageState();
}

class _DriverHistoryPageState extends State<DriverHistoryPage> {
   List<Map<String, dynamic>> _myTrips = [];
   StreamSubscription<DatabaseEvent>? _tripsSubscription;
   int _historyFilter = 0; // 0: Today, 1: Past

  int _asIntTimestamp(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int _dateToComparableValue(String dateStr) {
    if (dateStr.contains('-')) {
      try {
        final d = DateTime.parse(dateStr);
        return d.millisecondsSinceEpoch;
      } catch (_) {}
    }
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          return DateTime(y, m, d).millisecondsSinceEpoch;
        }
      }
    } catch (_) {}
    return 0;
  }

  bool _isToday(String dateStr) {
     final now = DateTime.now();
     final todayStr = "${now.day}/${now.month}/${now.year}";
     final todayStr2 = "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
     if (dateStr == todayStr || dateStr == todayStr2) return true;
     final todayIso = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
     if (dateStr == todayIso) return true;
     if (dateStr.contains('-')) {
        try {
           final d = DateTime.parse(dateStr);
           return d.year == now.year && d.month == now.month && d.day == now.day;
        } catch (_) {}
     }
     try {
       final parts = dateStr.split('/');
       if (parts.length == 3) {
         final d = int.tryParse(parts[0]);
         final m = int.tryParse(parts[1]);
         final y = int.tryParse(parts[2]);
         if (d == now.day && m == now.month && y == now.year) return true;
       }
     } catch (_) {}
     return false;
  }

  @override
  void initState() {
    super.initState();
    _loadMyTrips();
  }

  @override
  void dispose() {
    _tripsSubscription?.cancel();
    super.dispose();
  }

  void _loadMyTrips() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen to all trips and filter locally (Firebase Realtime DB filtering is limited)
    // Ideally we should have a 'driverTrips/$uid' node, but for now we query 'trips'.
    _tripsSubscription = FirebaseDatabase.instance
        .ref()
        .child('trips')
        .orderByChild('driverId')
        .equalTo(user.uid)
        .onValue
        .listen((event) {
          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          if (data == null) {
            setState(() => _myTrips = []);
            return;
          }

          final List<Map<String, dynamic>> loadedTrips = [];
          data.forEach((key, value) {
            final tripData = Map<String, dynamic>.from(value as Map);
            tripData['key'] = key;
            tripData['sortTimestamp'] = _asIntTimestamp(tripData['finishedAt']) > 0
                ? _asIntTimestamp(tripData['finishedAt'])
                : (_asIntTimestamp(tripData['updatedAt']) > 0
                    ? _asIntTimestamp(tripData['updatedAt'])
                    : (_asIntTimestamp(tripData['createdAt']) > 0
                        ? _asIntTimestamp(tripData['createdAt'])
                        : _dateToComparableValue(tripData['date']?.toString() ?? '')));
            loadedTrips.add(tripData);
          });
          
          // Sort newest first, with robust fallbacks.
          loadedTrips.sort((a, b) =>
              _asIntTimestamp(b['sortTimestamp']).compareTo(_asIntTimestamp(a['sortTimestamp'])));

          setState(() {
            _myTrips = loadedTrips;
          });
        });
  }

  Future<void> _updatePassengerStatus(String tripId, String seatIndex, String newStatus, String userId) async {
    try {
      final tripRef = FirebaseDatabase.instance.ref().child('trips').child(tripId);
      
      // Update trip status
      await tripRef.child('takenSeats').child(seatIndex).update({'status': newStatus});

      // Update customer history status
      final bookingRef = FirebaseDatabase.instance.ref().child('bookings').child(userId).child(seatIndex.toString());
      await bookingRef.update({
         'status': newStatus,
         'passengerSeen': false,
      });

      if (newStatus == 'accepted') {
         // Determine if this was a rejoin by checking if chatStatus was 'removed'
         final chatStatusSnap = await tripRef.child('chatStatus').child(userId).get();
         if (chatStatusSnap.exists && (chatStatusSnap.value == 'removed' || chatStatusSnap.value == 'deleted')) {
             await chatService.restorePassengerChat(tripId, userId);
         } else {
             // Also check the isRejoin flag inside takenSeats as fallback
             final seatSnap = await tripRef.child('takenSeats').child(seatIndex).child('isRejoin').get();
             if (seatSnap.exists && seatSnap.value == true) {
                 await chatService.restorePassengerChat(tripId, userId);
             }
         }
      }

      if (newStatus == 'refused') {
         // If refused, restore the seat count? 
         // Implementation decision: Refused means seat is free again.
         // We should remove from takenSeats or keep it as 'refused' but increment availableSeats.
         // Let's increment availableSeats.
         final tripSnapshot = await tripRef.get();
         if (tripSnapshot.exists) {
           final tripData = tripSnapshot.value as Map<dynamic, dynamic>;
           final takenSeats = tripData['takenSeats'] as Map<dynamic, dynamic>? ?? {};
           final seatData = takenSeats[seatIndex] as Map<dynamic, dynamic>? ?? {};
           final int seatsToRestore = (seatData['seats'] as num?)?.toInt() ?? (seatData['seatsBooked'] as num?)?.toInt() ?? 1;

           int currentAvailable = int.tryParse(tripData['availableSeats']?.toString() ?? '0') ?? 0;
           await tripRef.update({'availableSeats': currentAvailable + seatsToRestore});
         }
      }

      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
           content: Text(newStatus == 'accepted' ? 'تم قبول الراكب' : 'تم رفض الراكب'),
           backgroundColor: newStatus == 'accepted' ? const Color(0xFF43C59E) : Colors.red,
         ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _cancelPassenger(String tripId, String seatIndex) async {
    // Logic: Remove passenger from 'takenSeats', update 'availableSeats'
    try {
      final tripRef = FirebaseDatabase.instance.ref().child('trips').child(tripId);
      final snapshot = await tripRef.get();
      if (!snapshot.exists) return;

      final tripData = snapshot.value as Map<dynamic, dynamic>;
      final takenSeats = Map<dynamic, dynamic>.from(tripData['takenSeats'] ?? {});
      
      if (takenSeats.containsKey(seatIndex)) {
        final seatData = takenSeats[seatIndex] as Map<dynamic, dynamic>? ?? {};
        final int seatsToRestore = (seatData['seats'] as num?)?.toInt() ?? (seatData['seatsBooked'] as num?)?.toInt() ?? 1;

        // Update the passenger's history to canceled
        final userId = seatData['userId']?.toString();
        if (userId != null && userId.isNotEmpty) {
           await FirebaseDatabase.instance.ref().child('bookings').child(userId).child(seatIndex.toString()).update({
             'status': 'cancelled',
             'passengerSeen': false,
           });
        }
        await tripRef.child('takenSeats').child(seatIndex).remove();
        
        List<dynamic> indicesToRemove = [];
        if (seatData['seatIndices'] != null) {
          if (seatData['seatIndices'] is List) {
            indicesToRemove = List<dynamic>.from(seatData['seatIndices'] as List<dynamic>);
          } else if (seatData['seatIndices'] is Map) {
            indicesToRemove = (seatData['seatIndices'] as Map).values.toList();
          }
        }
        
        List<dynamic> existingIndices = [];
        if (tripData['bookedSeatIndices'] != null) {
          if (tripData['bookedSeatIndices'] is List) {
            existingIndices = List<dynamic>.from(tripData['bookedSeatIndices'] as List<dynamic>);
          } else if (tripData['bookedSeatIndices'] is Map) {
            existingIndices = (tripData['bookedSeatIndices'] as Map).values.toList();
          }
        }
        for (var index in indicesToRemove) {
          existingIndices.remove(index);
        }

        int currentAvailable = int.tryParse(tripData['availableSeats']?.toString() ?? '0') ?? 0;
        await tripRef.update({
          'availableSeats': currentAvailable + seatsToRestore,
          'bookedSeatIndices': existingIndices,
        });
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تمت إزالة الراكب")));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
  
   Future<void> _cancelEntireTrip(String tripId) async {
     try {
       final tripRef = FirebaseDatabase.instance.ref().child('trips').child(tripId);
       final tripSnapshot = await tripRef.get();
       
       if (tripSnapshot.exists) {
         final tripData = tripSnapshot.value as Map<dynamic, dynamic>;
         
         // Mark the trip itself as cancelled without clearing takenSeats or bookedSeatIndices
         await tripRef.update({
           'status': 'cancelled',
           // Removed: 'availableSeats': totalSeats, to preserve UI state
           // Removed: 'takenSeats': <String, dynamic>{},
           // Removed: 'bookedSeatIndices': <dynamic>[],
         });
         
         // Update all booked passengers' history and seat status to cancelled
         final takenSeats = tripData['takenSeats'] as Map<dynamic, dynamic>?;
         if (takenSeats != null) {
           for (var entry in takenSeats.entries) {
              final seatIndex = entry.key;
              final bookingVal = entry.value;
              final booking = bookingVal as Map<dynamic, dynamic>;
              
              // Update status in the trip's takenSeats node
              await tripRef.child('takenSeats').child(seatIndex.toString()).update({
                 'status': 'cancelled',
              });

              final userId = booking['userId']?.toString();
              if (userId != null && userId.isNotEmpty) {
                 await FirebaseDatabase.instance.ref().child('bookings').child(userId).child(seatIndex.toString()).update({
                    'status': 'cancelled',
                    'passengerSeen': false,
                 });
              }
           }
         }
       }
       
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إلغاء الرحلة بنجاح")));
     } catch(e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
     }
  }

  Future<void> _startTrip(String tripId, Map<dynamic, dynamic> tripData) async {
    try {
      final tripRef = FirebaseDatabase.instance.ref().child('trips').child(tripId);
      
      // Mark trip as 'starting'
      await tripRef.update({'status': 'starting'});

      // Also update customer history so customer app can listen if needed
      final takenSeats = tripData['takenSeats'] as Map<dynamic, dynamic>?;
      if (takenSeats != null) {
        for (var bookingVal in takenSeats.values) {
          final booking = bookingVal as Map<dynamic, dynamic>;
          final userId = booking['userId']?.toString();
          if (userId != null && userId.isNotEmpty && booking['status'] == 'accepted') {
             await FirebaseDatabase.instance.ref().child('bookings').child(userId).child(tripId).update({
                'tripStatus': 'starting',
                'passengerSeen': false,
             });
          }
        }
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("بدأت الرحلة! تم إشعار الركاب.")));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    }
  }


  Widget _buildSummaryBar(List<Map<String, dynamic>> trips) {
    int totalTrips = 0;
    double totalEarnings = 0.0;

    for (var trip in trips) {
      final takenSeats = trip['takenSeats'];
      if (takenSeats is Map<dynamic, dynamic>) {
        takenSeats.forEach((seatKey, bookingVal) {
          if (bookingVal is Map<dynamic, dynamic>) {
            final booking = bookingVal;
            if (booking['status'] == 'accepted') {
              totalTrips++;
              final double originalPrice = (booking['totalPrice'] as num?)?.toDouble() ?? 
                                           (booking['basePrice'] as num?)?.toDouble() ?? 
                                           (trip['price'] as num?)?.toDouble() ?? 0.0;
              final double? suggested = (booking['suggestedPrice'] as num?)?.toDouble();
              totalEarnings += suggested ?? originalPrice;
            }
          }
        });
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$totalTrips",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "الرحلات المكتملة",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey.shade200,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${totalEarnings.toStringAsFixed(0)} دج",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "إجمالي الأرباح",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSummaryBar(_myTrips),
        if (_myTrips.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.history, size: 80, color: Colors.grey.shade300),
                   const SizedBox(height: 20),
                   Text('لم يتم نشر أي رحلات بعد', style: TextStyle(color: Colors.grey.shade400, fontSize: 18, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   Text('أنشئ رحلة لرؤيتها هنا', style: TextStyle(color: Colors.grey.shade400)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _myTrips.length,
              itemBuilder: (context, index) {
                final trip = _myTrips[index];
                final takenSeats = trip['takenSeats'] as Map<dynamic, dynamic>? ?? {};
                int passengerCount = 0;
                int packageCount = 0;
                takenSeats.forEach((key, val) {
                   if (val is Map) {
                      if (val['isDelivery'] == true || val['transportType'] == 'package' || val['packageType'] != null) {
                         packageCount++;
                      } else {
                         passengerCount++;
                      }
                   }
                });

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 3))],
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.all(20),
                    childrenPadding: EdgeInsets.zero,
                    title: Column(
                      children: [
                         Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF43C59E).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                trip['date'] ?? '',
                                style: const TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            Text(trip['time'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Route
                        Row(
                          children: [
                             Expanded(
                               child: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                   _buildLocationRow(Icons.radio_button_checked, trip['from'] ?? '', const Color(0xFF43C59E)),
                                   Container(
                                     margin: const EdgeInsets.only(left: 7),
                                     padding: const EdgeInsets.symmetric(vertical: 4),
                                     child: Container(width: 2, height: 10, color: Colors.grey[300]),
                                   ),
                                   _buildLocationRow(Icons.location_on, trip['to'] ?? '', Colors.pink),
                                 ],
                               ),
                             ),
                          ],
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.sell_outlined, size: 16, color: Colors.grey[600]), 
                              const SizedBox(width: 6),
                              Text(
                                trip['price'] != null ? 'السعر: ${trip['price']} دج' : 'السعر: غير متوفر',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const SizedBox(width: 6),
                              const Spacer(),
                              const Text(
                                "التفاصيل",
                                style: TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    children: [
                      Container(height: 1, color: Colors.grey.shade100),
                    Padding(
                       padding: const EdgeInsets.all(16),
                       child: Column(
                         children: [
                           if (_shouldShowStartTripButton(trip['date']?.toString(), trip['time']?.toString()) && trip['status'] != 'starting')
                             SizedBox(
                               width: double.infinity,
                               child: ElevatedButton(
                                 onPressed: () => _startTrip(trip['key'], trip),
                                 style: ElevatedButton.styleFrom(
                                   backgroundColor: const Color(0xFF43C59E),
                                   padding: const EdgeInsets.symmetric(vertical: 12),
                                 ),
                                 child: const Text("بدأ الرحلة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                               ),
                             ),
                           if (_shouldShowStartTripButton(trip['date']?.toString(), trip['time']?.toString()) && trip['status'] != 'starting')
                             const SizedBox(height: 8),
                           if (trip['status'] == 'starting')
                             Container(
                               width: double.infinity,
                               padding: const EdgeInsets.symmetric(vertical: 12),
                               decoration: BoxDecoration(
                                 color: Colors.green.shade50,
                                 borderRadius: BorderRadius.circular(8),
                               ),
                               alignment: Alignment.center,
                               child: Text("الرحلة تبدأ", style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 16)),
                             ),
                           if (trip['status'] == 'starting')
                             const SizedBox(height: 8),
                           SizedBox(
                             width: double.infinity,
                             child: ElevatedButton(
                               onPressed: () {
                                 int parseInt(dynamic v, {int fallback = 0}) {
                                   if (v is int) return v;
                                   if (v is num) return v.toInt();
                                   if (v is String) return int.tryParse(v) ?? fallback;
                                   return fallback;
                                 }
                                 final totalSeats = parseInt(trip['totalSeats'], fallback: parseInt(trip['totalCapacity'], fallback: 4));
                                 Navigator.push(
                                   context,
                                   MaterialPageRoute(
                                     builder: (_) => DriverPassengerLogPage(
                                       tripId: trip['key'],
                                       driverName: trip['driverName']?.toString() ?? 'السائق',
                                       totalSeats: totalSeats,
                                     ),
                                   ),
                                 );
                               },
                               style: ElevatedButton.styleFrom(
                                 backgroundColor: Colors.blue.shade600,
                                 padding: const EdgeInsets.symmetric(vertical: 12),
                               ),
                               child: const Text("سجل الركاب", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                             ),
                           ),
                           const SizedBox(height: 8),
                           SizedBox(
                             width: double.infinity,
                             child: ElevatedButton(
                               onPressed: trip['status'] == 'cancelled' ? null : () async {
                                 final confirm = await showDialog<bool>(
                                   context: context,
                                   builder: (ctx) => AlertDialog(
                                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                     title: const Text("إلغاء الرحلة"),
                                     content: const Text("هل أنت متأكد أنك تريد إلغاء هذه الرحلة؟"),
                                     actions: [
                                       TextButton(
                                         onPressed: () => Navigator.pop(ctx, false),
                                         child: const Text("لا", style: TextStyle(color: Colors.grey)),
                                       ),
                                       ElevatedButton(
                                         onPressed: () => Navigator.pop(ctx, true),
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: Colors.red,
                                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                         ),
                                         child: const Text("نعم", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                       ),
                                     ],
                                   ),
                                 );
                                 if (confirm == true) {
                                   _cancelEntireTrip(trip['key']);
                                 }
                               },
                               style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                               child: Text(trip['status'] == 'cancelled' ? "ملغاة" : "إلغاء الرحلة", style: const TextStyle(color: Colors.white)),
                             ),
                           ),
                         ],
                       ),
                    ),
                  ],
                ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _shouldShowStartTripButton(String? dateStr, String? timeStr) {
    if (dateStr == null || timeStr == null || dateStr.isEmpty || timeStr.isEmpty) return false;

    try {
      final now = DateTime.now();
      
      // Parse DD/MM/YYYY
      final dateParts = dateStr.split('/');
      if (dateParts.length != 3) return false;
      final day = int.tryParse(dateParts[0]) ?? now.day;
      final month = int.tryParse(dateParts[1]) ?? now.month;
      final year = int.tryParse(dateParts[2]) ?? now.year;

      // Parse HH:mm
      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) return false;
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      final tripTime = DateTime(year, month, day, hour, minute);
      
      final difference = now.difference(tripTime).inMinutes;
      // Between 1 hour before and 1 hour after (-60 to +60 minutes)
      return difference >= -60 && difference <= 60;
    } catch (e) {
      return false;
    }
  }

  Widget _buildPassengerItem(String tripId, String seatIndex, Map<dynamic, dynamic> pData, String pName, String? tripStatus) {
    final isDelivery = pData['isDelivery'] == true ||
        pData['transportType'] == 'package' ||
        pData['packageType'] != null;

    int? asSeatIndex(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    List<int> extractSeatIndices(dynamic raw) {
      final List<int> result = [];
      if (raw is List) {
        for (final v in raw) {
          final idx = asSeatIndex(v);
          if (idx != null && idx > 0) result.add(idx);
        }
      } else if (raw is Map) {
        for (final v in raw.values) {
          final idx = asSeatIndex(v);
          if (idx != null && idx > 0) result.add(idx);
        }
      } else {
        final idx = asSeatIndex(raw);
        if (idx != null && idx > 0) result.add(idx);
      }
      return result.toSet().toList()..sort();
    }

    bool hasLuggageForSeat(dynamic seatLuggageRaw, int seatIdx) {
      if (seatLuggageRaw is Map) {
        return seatLuggageRaw[seatIdx.toString()] == true ||
            seatLuggageRaw[seatIdx] == true ||
            seatLuggageRaw[seatIdx.toString()]?.toString().toLowerCase() ==
                'true' ||
            seatLuggageRaw[seatIdx]?.toString().toLowerCase() == 'true';
      }
      if (seatLuggageRaw is List) {
        final listIdx = seatIdx - 1;
        if (listIdx >= 0 && listIdx < seatLuggageRaw.length) {
          final v = seatLuggageRaw[listIdx];
          return v == true || v?.toString().toLowerCase() == 'true';
        }
      }
      return false;
    }

    final seatIndices = extractSeatIndices(pData['seatIndices']);
    final seatLuggageRaw = pData['seatLuggage'];
    final seatIndicesLabel = seatIndices.isEmpty
        ? null
        : seatIndices
            .map((idx) => hasLuggageForSeat(seatLuggageRaw, idx) ? '$idx🧳' : '$idx')
            .join(', ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserProfileAvatar(userId: pData['userId']?.toString() ?? '', radius: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (!isDelivery)
                    Text(
                      seatIndicesLabel != null
                          ? 'المقاعد (${seatIndices.length}): $seatIndicesLabel'
                          : 'المقاعد: ${pData['seats'] ?? pData['seatsBooked'] ?? 1} ${(pData['hasPackage'] == true) ? "• 🧳 أمتعة" : ""}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  if (!isDelivery)
                    Text('الإجمالي: ${pData['basePrice'] ?? pData['totalPrice'] ?? '0'} دج', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                  if ((pData['suggestedPrice'] ?? (isDelivery ? pData['price'] : null)) != null)
                    Row(
                      children: [
                        Text('مقترح: ${(pData['suggestedPrice'] ?? (isDelivery ? pData['price'] : null))} دج', style: TextStyle(color: Colors.blue.shade700, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        if (pData['basePrice'] != null)
                          Text(
                            () {
                              double diff = (pData['suggestedPrice'] as num).toDouble() - (pData['basePrice'] as num).toDouble();
                              return diff >= 0 ? "(+${diff.toStringAsFixed(0)})" : "(-${diff.abs().toStringAsFixed(0)})";
                            }(),
                            style: TextStyle(
                              color: ((pData['suggestedPrice'] as num).toDouble() - (pData['basePrice'] as num).toDouble()) >= 0 ? Colors.green : Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  if (pData['status'] == 'booked' || pData['status'] == 'pending')
                     Text(pData['isRejoin'] == true ? 'طلب إعادة الانضمام للرحلة' : 'الحالة: قيد الانتظار', style: TextStyle(color: pData['isRejoin'] == true ? Colors.blue.shade700 : Colors.orange.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  if (pData['status'] == 'accepted')
                     Text('الحالة: مقبول', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  if (pData['status'] == 'refused')
                     Text('الحالة: مرفوض', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  if (tripStatus == 'starting' && pData['status'] == 'accepted')
                     Padding(
                       padding: const EdgeInsets.only(top: 4.0),
                       child: Row(
                         children: [
                           Icon(
                             pData['passengerConfirmed'] == true ? Icons.check_circle : (pData['passengerConfirmed'] == false ? Icons.cancel : Icons.help),
                             size: 14,
                             color: pData['passengerConfirmed'] == true ? Colors.green : (pData['passengerConfirmed'] == false ? Colors.red : Colors.orange),
                           ),
                           const SizedBox(width: 4),
                           Text(
                             pData['passengerConfirmed'] == true ? 'مؤكد' : (pData['passengerConfirmed'] == false ? 'غير مؤكد' : 'في انتظار الرد'),
                             style: TextStyle(
                               fontSize: 12,
                               fontWeight: FontWeight.bold,
                               color: pData['passengerConfirmed'] == true ? Colors.green.shade700 : (pData['passengerConfirmed'] == false ? Colors.red.shade700 : Colors.orange.shade700),
                             ),
                           ),
                         ],
                       ),
                     ),
                ],
              )),
              
              if (pData['status'] == 'booked' || pData['status'] == 'pending') ...[
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Color(0xFF43C59E)),
                  onPressed: () => _updatePassengerStatus(tripId, seatIndex, 'accepted', pData['userId']),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: () => _updatePassengerStatus(tripId, seatIndex, 'refused', pData['userId']),
                ),
              ] else if (pData['status'] == 'accepted')
                 IconButton(
                   icon: const Icon(Icons.delete_outline, color: Colors.grey),
                   onPressed: () => _cancelPassenger(tripId, seatIndex),
                 )
            ],
          ),
          if (isDelivery)
             Padding(
               padding: const EdgeInsets.only(top: 12.0),
               child: Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Row(
                       children: const [
                         Icon(Icons.inventory_2, size: 16, color: Colors.orange),
                         SizedBox(width: 8),
                         Text("تفاصيل الطرد", style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                       ],
                     ),
                     const SizedBox(height: 8),
                     if (pData['from'] != null) Text("من: ${pData['from']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (pData['to'] != null) Text("إلى: ${pData['to']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (pData['packageType'] != null) Text("النوع: ${pData['packageType']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (pData['packageDetails'] != null) Text("الوصف: ${pData['packageDetails']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (pData['userName'] != null) Text("طالب التوصيل: ${pData['userName']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (pData['senderName'] != null) Text("المرسل إليه: ${pData['senderName']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                     if (pData['senderPhone'] != null) Text("للتواصل: ${pData['senderPhone']}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                   ],
                 ),
               ),
             ),
          if (pData['status'] == 'accepted')
             Padding(
               padding: const EdgeInsets.only(top: 8.0),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.end,
                 children: [
                   TextButton.icon(
                     onPressed: () => _forgotItem(pName),
                     icon: const Icon(Icons.help_outline, size: 16, color: Colors.orange),
                     label: const Text("عنصر مفقود", style: TextStyle(color: Colors.orange, fontSize: 12)),
                   )
                 ],
               ),
             )
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  void _forgotItem(String passengerName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("تم إرسال تنبيه إلى $passengerName حول العنصر المفقود."),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

// ------------------------ Driver Special Offers Page ------------------------
class DriverOffersPage extends StatelessWidget {
  const DriverOffersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_offer, size: 80, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          const Text(
            'عروض خاصة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          const Text(
            'ستظهر العروض الترويجية هنا',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
