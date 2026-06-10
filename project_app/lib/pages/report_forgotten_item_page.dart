import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ReportForgottenItemPage extends StatefulWidget {
  final String tripId;
  final String driverName;
  final String date;
  final String from;
  final String to;

  const ReportForgottenItemPage({
    super.key,
    required this.tripId,
    required this.driverName,
    required this.date,
    required this.from,
    required this.to,
  });

  @override
  State<ReportForgottenItemPage> createState() => _ReportForgottenItemPageState();
}

class _ReportForgottenItemPageState extends State<ReportForgottenItemPage> {
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedLocation = 'غير متأكد';
  bool _isSubmitting = false;

  final List<String> _locationOptions = [
    'على المقعد',
    'تحت المقعد',
    'في الصندوق',
    'غير متأكد'
  ];

  Future<void> _submitRequest() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("الرجاء وصف العنصر المفقود"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      // We need passenger name and phone. Let's fetch passenger info.
      final userSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .get();

      String passengerName = "Passenger";
      String passengerPhone = "Unknown";
      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        final first = userData['firstName']?.toString() ?? '';
        final last = userData['lastName']?.toString() ?? '';
        
        if (first.isNotEmpty || last.isNotEmpty) {
           passengerName = '$first $last'.trim();
        } else if (userData['name'] != null) {
           passengerName = userData['name'].toString();
        } else if (userData['email'] != null) {
           passengerName = userData['email'].toString().split('@')[0];
        }

        passengerPhone = userData['phone']?.toString() ?? "Unknown";
      }

      // We need to find the driver id for this trip to save in their node.
      final tripId = widget.tripId;

      if (tripId.isEmpty) {
        throw "Trip ID is missing. Cannot report item.";
      }

      // 1. Get Driver ID from the trip
      final tripSnapshot = await FirebaseDatabase.instance.ref().child('trips').child(tripId).get();
      if (!tripSnapshot.exists) {
        throw "Trip record not found.";
      }
      
      final tripData = tripSnapshot.value as Map<dynamic, dynamic>;
      final driverId = tripData['driverId']?.toString();
      
      if (driverId == null || driverId.isEmpty) {
        throw "Could not identify the driver for this trip.";
      }

      // Save to forgottenItems/driverId
      final itemRef = FirebaseDatabase.instance
          .ref()
          .child('forgottenItems')
          .child(driverId)
          .push();

      await itemRef.set({
        'id': itemRef.key,
        'passengerId': user.uid,
        'passengerName': passengerName,
        'passengerPhone': passengerPhone,
        'tripId': widget.tripId,
        'driverName': widget.driverName,
        'from': widget.from,
        'to': widget.to,
        'date': widget.date,
        'description': description,
        'location': _selectedLocation,
        'timestamp': ServerValue.timestamp,
        'status': 'Pending', // Pending, Found, Not Found
        'driverSeen': false,
        'passengerSeen': true,
      });

      setState(() {
        _isSubmitting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم إرسال طلبك إلى السائق. سيتم إعلامك بمجرد رده."),
            backgroundColor: Color(0xFF43C59E),
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("خطأ: $e"),
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
        title: const Text(
          "الإبلاغ عن عنصر مفقود",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "صف ما فقدته حتى يتمكن السائق من التحقق منه.",
              style: TextStyle(
                fontSize: 15,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
            
            // Short Trip Reference details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Color(0xFF43C59E)),
                      const SizedBox(width: 8),
                      Text(
                        widget.date,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.circle, size: 10, color: Color(0xFF43C59E)),
                          Container(
                            height: 16,
                            width: 2,
                            color: Colors.grey[300],
                            margin: const EdgeInsets.symmetric(vertical: 2),
                          ),
                          const Icon(Icons.location_on, size: 10, color: Colors.pink),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.from, style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 14),
                            Text(widget.to, style: const TextStyle(fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "السائق: ${widget.driverName}",
                          style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Form Section
            const Text(
              "ما الذي نسيته؟",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "صف العنصر (اللون، العلامة التجارية، التفاصيل...)",
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF43C59E)),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            const Text(
              "أين تعتقد أنك تركته؟ (اختياري)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLocation,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                  items: _locationOptions.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedLocation = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43C59E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        "إرسال الطلب",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
