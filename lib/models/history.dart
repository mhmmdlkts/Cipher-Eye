import 'dart:io';

import 'package:cipher_eye/services/history_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/firestore_paths_service.dart';
import 'package:geolocator/geolocator.dart';

class History {
  String? id;
  String? uid;
  String? action;
  String? location;
  Timestamp? timestamp;
  String? password;
  String? deviceInfo;
  String? userAgent;

  History.create({required this.action, this.password}) {
    timestamp = Timestamp.now();
    id = FirestorePathsService.getHistoryCol().doc().id;
    uid = FirebaseAuth.instance.currentUser!.uid!;
  }

  Future init() async {
    await Future.wait([
      setLocation(),
      setDeviceInfo()
    ]);
  }

  Future<void> setDeviceInfo() async {
    DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
        userAgent = androidInfo.data.toString();
        deviceInfo = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
        userAgent = iosInfo.data.toString();
        deviceInfo = '${iosInfo.name} ${iosInfo.systemVersion}';
      } else if (kIsWeb) {
        WebBrowserInfo webInfo = await deviceInfoPlugin.webBrowserInfo;
        userAgent = webInfo.data.toString();
        deviceInfo = '${webInfo.browserName} ${webInfo.appVersion}';
      }
    } catch (e) {
      print('Error getting device info: $e');
    }
  }

  Future<void> setLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          HistoryService.locationDenied = true;
          return;
        }
        HistoryService.locationDenied = false;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      location = '${position.latitude},${position.longitude}';
    } catch (e) {
      print('Error getting location: $e');
    }
  }


  History.fromSnapshot(DocumentSnapshot<Object?> snap) {
    if (snap.data() == null) {
      return;
    }
    Map<String, dynamic> o = snap.data() as Map<String, dynamic>;

    id = snap.id;
    if (o.containsKey('action')) {
      action = o['action'];
    }
    if (o.containsKey('location')) {
      location = o['location'];
    }
    if (o.containsKey('timestamp')) {
      timestamp = o['timestamp'];
    }
    if (o.containsKey('password')) {
      password = o['password'];
    }
    if (o.containsKey('deviceInfo')) {
      deviceInfo = o['deviceInfo'];
    }
    if (o.containsKey('userAgent')) {
      userAgent = o['userAgent'];
    }
  }

  Map<String, dynamic> toJson({bool withNull = true}) {
    Map<String, dynamic> map = {
      'password': password,
      'timestamp': timestamp,
      'location': location,
      'action': action,
      'deviceInfo': deviceInfo,
      'userAgent': userAgent,
    };
    if (withNull) {
      return map;
    }
    Map<String, dynamic> newMap = {};
    map.forEach((key, value) {
      if (value != null) {
        newMap.addAll({key: value});
      }
    });
    return newMap;
  }

  Future push() async => await FirestorePathsService.geHistoryDoc(historyId: id!).set(toJson());
  Future update() async => await FirestorePathsService.geHistoryDoc(historyId: id!).update(toJson(withNull: false));
}