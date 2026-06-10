import 'package:firebase_database/firebase_database.dart';
import '../models/chat_message.dart';
import 'dart:async';

class ChatService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  Set<String> _extractParticipantIds(Map<dynamic, dynamic> tripData) {
    final ids = <String>{};
    final driverId = tripData['driverId']?.toString();
    if (driverId != null && driverId.isNotEmpty) {
      ids.add(driverId);
    }

    final seats = tripData['seats'] as Map<dynamic, dynamic>?;
    if (seats != null) {
      for (final seat in seats.values) {
        if (seat is Map) {
          final pId = seat['reservedBy']?.toString();
          if (pId != null && pId.isNotEmpty) ids.add(pId);
        }
      }
    }

    final takenSeats = tripData['takenSeats'] as Map<dynamic, dynamic>?;
    if (takenSeats != null) {
      for (final seat in takenSeats.values) {
        if (seat is Map) {
          final pId = seat['userId']?.toString();
          if (pId != null && pId.isNotEmpty) ids.add(pId);
        }
      }
    }
    return ids;
  }

  // Set user online status
  Future<void> setOnlineStatus(String userId, bool isOnline) async {
    final ref = _database.ref().child('users').child(userId);
    await ref.update({'isOnline': isOnline});
    
    if (isOnline) {
      ref.child('isOnline').onDisconnect().set(false);
    }
  }

  // Get user online status stream
  Stream<bool> getUserOnlineStatus(String userId) {
    return _database.ref().child('users').child(userId).child('isOnline').onValue.map((event) {
      return event.snapshot.value == true;
    });
  }

  // Set typing status
  Future<void> setTypingStatus(String tripId, String userId, bool isTyping) async {
    final ref = _database.ref().child('chats').child(tripId).child('typing').child(userId);
    await ref.set(isTyping);
    if (isTyping) {
      ref.onDisconnect().set(false);
    }
  }

  // Get typing status stream
  Stream<bool> getTypingStatus(String tripId, String otherUserId) {
    return _database.ref().child('chats').child(tripId).child('typing').child(otherUserId).onValue.map((event) {
      return event.snapshot.value == true;
    });
  }

  // Clear messages for a user
  Future<void> clearChatForUser(String tripId, String userId) async {
    await _database.ref().child('chats').child(tripId).child('clearedAt').child(userId).set(ServerValue.timestamp);
  }

  // Archive chat (Moves it to Previous)
  Future<void> archiveChat(String tripId, String userId) async {
    await _database.ref().child('trips').child(tripId).child('chatStatus').child(userId).set('archived');
  }

  // Delete chat completely
  Future<void> deleteChatComplete(String tripId, String userId) async {
    await _database.ref().child('trips').child(tripId).child('chatStatus').child(userId).set('deleted');
    await clearChatForUser(tripId, userId);
  }

  // Get stream of messages for a specific trip
  Stream<List<ChatMessage>> getMessagesStream(String tripId, String currentUserId) {
    return _database.ref().child('chats').child(tripId).child('clearedAt').child(currentUserId).onValue.asyncMap((event) async {
       return (event.snapshot.value as num?)?.toInt() ?? 0;
    }).asyncExpand((clearedAt) {
      return _database
          .ref()
          .child('chats')
          .child(tripId)
          .child('messages')
          .orderByChild('timestamp')
          .startAt(clearedAt)
          .onValue
          .map((event) {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) return [];

        final List<ChatMessage> messages = [];
        data.forEach((key, value) {
          messages.add(ChatMessage.fromMap(value as Map<dynamic, dynamic>, key.toString()));
        });

        // Sort by timestamp descending
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return messages;
      });
    });
  }

  // Send a message
  Future<void> sendMessage(String tripId, String senderId, String senderName, String message, {bool isSystemMessage = false}) async {
    if (message.trim().isEmpty) return;

    // A removed/deleted passenger can still view the chat but must not send messages.
    if (!isSystemMessage) {
      final chatStatusSnap = await _database
          .ref()
          .child('trips')
          .child(tripId)
          .child('chatStatus')
          .child(senderId)
          .get();
      final chatStatus = chatStatusSnap.value?.toString();
      if (chatStatus == 'removed' || chatStatus == 'deleted') {
        return;
      }
    }
    
    final chatRef = _database.ref().child('chats').child(tripId).child('messages').push();
    final timestamp = ServerValue.timestamp;
    
    await chatRef.set({
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'timestamp': timestamp,
      'status': isSystemMessage ? 'read' : 'delivered',
      'isSystemMessage': isSystemMessage,
    });
    
    await setTypingStatus(tripId, senderId, false);

    final userChatsSnap = await _database.ref().child('trips').child(tripId).get();
    if(userChatsSnap.exists && userChatsSnap.value != null){
      final tripData = userChatsSnap.value as Map<dynamic, dynamic>;
      final updates = <String, dynamic>{};
      final participantIds = _extractParticipantIds(tripData);

      for (final pId in participantIds) {
        updates['userChats/$pId/$tripId/lastMessage'] = message;
        updates['userChats/$pId/$tripId/timestamp'] = timestamp;
      }
      if(updates.isNotEmpty){
         await _database.ref().update(updates);
      }
    }
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String tripId, String currentUserId) async {
    final ref = _database.ref().child('chats').child(tripId).child('messages');
    final snap = await ref.get();
    
    if (snap.exists) {
      final updates = <String, dynamic>{};
      final data = snap.value as Map<dynamic, dynamic>;
      
      data.forEach((key, value) {
        final msg = Map<String, dynamic>.from(value as Map);
        if (msg['senderId'] != currentUserId && msg['status'] != 'read') {
          updates['$key/status'] = 'read';
        }
      });
      
      if (updates.isNotEmpty) {
        await ref.update(updates);
      }
    }
  }

  // Get a stream of the last message for a trip
  Stream<ChatMessage?> getLastMessageStream(String tripId, String currentUserId) {
    return _database.ref().child('chats').child(tripId).child('clearedAt').child(currentUserId).onValue.asyncMap((event) {
       return (event.snapshot.value as num?)?.toInt() ?? 0;
    }).asyncExpand((clearedAt) {
      return _database
          .ref()
          .child('chats')
          .child(tripId)
          .child('messages')
          .orderByChild('timestamp')
          .startAt(clearedAt)
          .limitToLast(1)
          .onValue
          .map((event) {
            final data = event.snapshot.value as Map<dynamic, dynamic>?;
            if (data == null || data.isEmpty) return null;
            final key = data.keys.first;
            return ChatMessage.fromMap(data[key] as Map<dynamic, dynamic>, key.toString());
          });
    });
  }

  // Get unread count for a single trip
  Stream<int> getUnreadCountStream(String tripId, String currentUserId) {
    return _database.ref().child('chats').child(tripId).child('clearedAt').child(currentUserId).onValue.asyncMap((event) {
       return (event.snapshot.value as num?)?.toInt() ?? 0;
    }).asyncExpand((clearedAt) {
      return _database
          .ref()
          .child('chats')
          .child(tripId)
          .child('messages')
          .orderByChild('timestamp')
          .startAt(clearedAt)
          .onValue
          .map((event) {
            final data = event.snapshot.value as Map<dynamic, dynamic>?;
            if (data == null) return 0;
            
            int count = 0;
            data.forEach((key, value) {
              final msg = value as Map<dynamic, dynamic>;
              if (msg['senderId'] != currentUserId && msg['status'] != 'read') {
                count++;
              }
            });
            return count;
      });
    });
  }

  // Admin: Remove a passenger from the trip
  Future<void> removePassenger(String tripId, String seatId, String passengerId) async {
    final tripRef = _database.ref().child('trips').child(tripId);
    bool removed = false;

    final txResult = await tripRef.runTransaction((Object? post) {
      if (post == null) return Transaction.abort();
      Map<dynamic, dynamic> trip = Map<dynamic, dynamic>.from(post as Map);

      int seatsToRestore = 1;
      List<dynamic> indicesToRemove = [];

      if (trip['seats'] != null) {
        final seats = Map<dynamic, dynamic>.from(trip['seats']);
        if (seats[seatId] != null && seats[seatId]['reservedBy']?.toString() == passengerId) {
          final seatData = seats[seatId] as Map<dynamic, dynamic>;
          seatsToRestore = (seatData['seats'] as num?)?.toInt() ?? (seatData['seatsBooked'] as num?)?.toInt() ?? 1;
          if (seatData['seatIndices'] != null && seatData['seatIndices'] is List) {
            indicesToRemove = List<dynamic>.from(seatData['seatIndices'] as List<dynamic>);
          }
          seats.remove(seatId);
          trip['seats'] = seats;
          removed = true;
        }
      }

      if (trip['takenSeats'] != null) {
        final takenSeats = Map<dynamic, dynamic>.from(trip['takenSeats']);
        if (takenSeats[seatId] != null && takenSeats[seatId]['userId']?.toString() == passengerId) {
          final seatData = takenSeats[seatId] as Map<dynamic, dynamic>;
          seatsToRestore = (seatData['seats'] as num?)?.toInt() ?? (seatData['seatsBooked'] as num?)?.toInt() ?? 1;
          if (seatData['seatIndices'] != null) {
            if (seatData['seatIndices'] is List) {
              indicesToRemove = List<dynamic>.from(seatData['seatIndices'] as List<dynamic>);
            } else if (seatData['seatIndices'] is Map) {
              indicesToRemove = (seatData['seatIndices'] as Map).values.toList();
            }
          }
          takenSeats.remove(seatId);
          trip['takenSeats'] = takenSeats;
          removed = true;
        }
      }

      if (removed) {
        final currentAvailableSeats =
            int.tryParse(trip['availableSeats']?.toString() ?? '0') ?? 0;
        trip['availableSeats'] = currentAvailableSeats + seatsToRestore;
        if (trip['status'] == 'full') trip['status'] = 'active';
        
        if (trip['bookedSeatIndices'] != null && trip['bookedSeatIndices'] is List) {
           List<dynamic> existingIndices = List<dynamic>.from(trip['bookedSeatIndices'] as List<dynamic>);
           for (var index in indicesToRemove) {
              existingIndices.remove(index);
           }
           trip['bookedSeatIndices'] = existingIndices;
        }

        return Transaction.success(trip);
      }
      return Transaction.abort();
    });

    removed = txResult.committed;
    if (!removed) return;

    // Keep chat visible but block passenger sending.
    await _database
        .ref()
        .child('trips')
        .child(tripId)
        .child('chatStatus')
        .child(passengerId)
        .set('removed');

    // Update passenger booking entry if this key exists.
    await _database.ref().child('bookings').child(passengerId).child(seatId).update({
      'status': 'cancelled',
      'removedByDriver': true,
      'passengerSeen': false,
    });

    // Update passenger history
    final historySnap = await _database.ref().child('history').child(passengerId).child('trips').child(tripId).get();
    if (historySnap.exists) {
       await _database.ref().child('history').child(passengerId).child('trips').child(tripId).update({
          'status': 'cancelled',
       });
    }
    
    // Notify in chat
    await sendMessage(tripId, 'system', 'نظام', 'تم إزالة راكب من الرحلة بواسطة السائق', isSystemMessage: true);
  }

  // Restore a passenger's chat access (e.g. after driver accepts a rejoin request)
  Future<void> restorePassengerChat(String tripId, String passengerId) async {
    // Remove the 'removed' status so they can chat again
    await _database
        .ref()
        .child('trips')
        .child(tripId)
        .child('chatStatus')
        .child(passengerId)
        .remove();

    // Send the system message for rejoin
    await sendMessage(
      tripId, 
      'system', 
      'نظام', 
      'تمت إعادة انضمام الراكب إلى الرحلة', 
      isSystemMessage: true
    );
  }

  // Submit Driver Rating
  Future<void> submitRating(String driverId, String tripId, String passengerId, double rating) async {
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5.');
    }

    final tripSnap = await _database.ref().child('trips').child(tripId).get();
    if (!tripSnap.exists || tripSnap.value == null || tripSnap.value is! Map) {
      throw Exception('Trip not found.');
    }

    final tripData = Map<dynamic, dynamic>.from(tripSnap.value as Map);
    final tripStatus = tripData['status']?.toString().toLowerCase() ?? '';
    final allowedStatuses = {'archived', 'completed', 'finished'};
    if (!allowedStatuses.contains(tripStatus)) {
      throw Exception('Rating is allowed only after trip completion.');
    }

    final tripDriverId = tripData['driverId']?.toString() ?? '';
    if (tripDriverId != driverId) {
      throw Exception('Driver mismatch for this trip.');
    }

    bool isPassengerInTrip = false;
    final takenSeats = tripData['takenSeats'];
    if (takenSeats is Map) {
      for (final rawBooking in takenSeats.values) {
        if (rawBooking is Map && rawBooking['userId']?.toString() == passengerId) {
          isPassengerInTrip = true;
          break;
        }
      }
    }
    if (!isPassengerInTrip) {
      throw Exception('Only trip passengers can submit a rating.');
    }

    final ratingRef = _database.ref().child('driverRatings').child(driverId).child(tripId).child(passengerId);
    final ratingTx = await ratingRef.runTransaction((currentData) {
      if (currentData != null) {
        return Transaction.abort();
      }
      return Transaction.success({
        'rating': rating,
        'timestamp': ServerValue.timestamp,
      });
    });
    if (!ratingTx.committed) {
      throw Exception('You have already rated this trip.');
    }

    final allRatingsSnap = await _database.ref().child('driverRatings').child(driverId).get();
    if (allRatingsSnap.exists) {
      double totalStars = 0;
      int count = 0;
      final tripsData = allRatingsSnap.value as Map<dynamic, dynamic>;
      tripsData.forEach((tId, passengersData) {
         final pData = passengersData as Map<dynamic, dynamic>;
         pData.forEach((pId, rateData) {
            final rateMap = rateData as Map<dynamic, dynamic>;
            totalStars += (rateMap['rating'] as num).toDouble();
            count++;
         });
      });

      if (count > 0) {
        double average = double.parse((totalStars / count).toStringAsFixed(1));
        await _database.ref().child('users').child(driverId).update({'rating': average, 'ratingCount': count});
      }
    }

    // Archive chat for both passenger and driver after rating is submitted.
    await _database.ref().child('trips').child(tripId).child('chatStatus').update({
      passengerId: 'archived',
      driverId: 'archived',
    });
  }

  // Stream to check if a passenger has already rated this trip
  Stream<bool> hasPassengerRated(String driverId, String tripId, String passengerId) {
     return _database.ref().child('driverRatings').child(driverId).child(tripId).child(passengerId).onValue.map((event) {
        return event.snapshot.exists;
     });
  }

  Stream<bool> getAnyTypingStatus(String tripId, String currentUserId) {
    return _database.ref().child('chats').child(tripId).child('typing').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return false;
      for (final entry in data.entries) {
        if (entry.key.toString() == currentUserId) continue;
        if (entry.value == true) return true;
      }
      return false;
    });
  }
}

final chatService = ChatService();
