import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const GpsTrackerScreen(),
    );
  }
}

class GpsTrackerScreen extends StatefulWidget {
  const GpsTrackerScreen({super.key});

  @override
  State<GpsTrackerScreen> createState() => _GpsTrackerScreenState();
}

class _GpsTrackerScreenState extends State<GpsTrackerScreen> {
  Position? _currentPosition;
  bool _isTracking = false;
  int _positionCount = 0;
  List<Position> _positionHistory = [];
  StreamSubscription<Position>? _positionStream;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
  Future<void> _saveNodesToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/gps_nodes.txt');
    final nodes = _positionHistory.map((pos) => '${pos.latitude},${pos.longitude}').join('\n');
    await file.writeAsString(nodes);

    print('Archivo guardado en: ${file.path}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Archivo guardado en: ${file.path}')),
    );
  }
  Future<void> _shareNodesFile() async {
  final directory = await getApplicationDocumentsDirectory();
  final filePath = '${directory.path}/gps_nodes.txt';
  final file = File(filePath);

  if (await file.exists()) {
    await Share.shareXFiles([XFile(filePath)], text: 'Mis nodos GPS');
  } else {
    print('Archivo no encontrado para compartir');
  }
}
  Future<void> _toggleTracking() async {
    if (_isTracking) {
      await _positionStream?.cancel();
      setState(() {
        _isTracking = false;
        _positionStream = null;
        _positionCount = 0;
      });
      await _saveNodesToFile();
      await _shareNodesFile();
    } else {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return;
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        setState(() {
          _currentPosition = position;
          _positionCount++;
          _positionHistory.add(position);
        });
      });

      setState(() {
        _isTracking = true;
      });
    }
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 18, color: Colors.black87)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lat = _currentPosition?.latitude.toStringAsFixed(5) ?? '--.--';
    final lng = _currentPosition?.longitude.toStringAsFixed(5) ?? '--.--';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento GPS'),
        centerTitle: true,
        elevation: 1,
        backgroundColor: Colors.indigo[50],
        foregroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDataRow('Latitud:', lat),
            _buildDataRow('Longitud:', lng),
            _buildDataRow('Conteo de Nodos:', _positionCount.toString()),
            const SizedBox(height: 40),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: _isTracking ? Colors.redAccent : Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextButton(
                onPressed: _toggleTracking,
                child: Text(
                  _isTracking ? 'Detener seguimiento' : 'Iniciar seguimiento',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
