import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class CampusNode {
  final String id;
  final String tipo;
  final String nombre;
  final int sector;
  final int? nivel;
  final latlong2.LatLng coord;
  final List<dynamic> vecinos;

  CampusNode({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.sector,
    this.nivel,
    required this.coord,
    required this.vecinos,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'nombre': nombre,
        'sector': sector,
        'nivel': nivel,
        'coord': {'lat': coord.latitude, 'lng': coord.longitude},
        'vecinos': vecinos,
      };
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
  int _selectedSector = 1;
  int _selectedNivel = 1;
  String _nombre = '';
  String _selectedTipo = 'camino'; 
  bool _showMap = false;
  bool _isManualMode = false; // Para cambiar entre modo manual y automático
  final MapController _mapController = MapController();
  final List<Marker> _markers = [];
  final List<String> _tipos = ['baño', 'camino', 'sala', 'departamento', 'biblioteca', 'bebedero'];
  final List<int> _niveles = List.generate(14, (index) => index - 3); 

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _saveNodesToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/campus_nodes.json');

    // Creamos nodos desde las posiciones capturadas
    final nodes = _positionHistory.asMap().entries.map((entry) {
      final index = entry.key;
      final lastIndex = _positionHistory.length - 1;
      final pos = entry.value;
      final sanitizedNombre = _nombre.replaceAll(' ', '_');
      final id = '${_selectedTipo}_${sanitizedNombre}_${_selectedSector}_${index+1}';
      final vecinos = <String>[];
      if (index == 0 && lastIndex >= 1) {
        // Primer nodo
        vecinos.add('${_selectedTipo}_${sanitizedNombre}_${_selectedSector}_${index + 2}');
      } else if (index == lastIndex && lastIndex >= 1) {
        // Último nodo
        vecinos.add('${_selectedTipo}_${sanitizedNombre}_${_selectedSector}_${index}');
      } else if (lastIndex >= 2) {
        // Nodo del medio
        vecinos.add('${_selectedTipo}_${sanitizedNombre}_${_selectedSector}_${index}');
        vecinos.add('${_selectedTipo}_${sanitizedNombre}_${_selectedSector}_${index + 2}');
      }
      return CampusNode(
        id: id,
        tipo: _selectedTipo,              // Podrías pedir al usuario el tipo
        nombre: _nombre,
        sector: _selectedSector,
        nivel: _selectedNivel,                
        coord: latlong2.LatLng(pos.latitude, pos.longitude),
        vecinos: vecinos,                // Lo puedes dejar vacío de momento
      );
    }).toList();

    final jsonList = nodes.map((n) => n.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await file.writeAsString(jsonString);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Archivo guardado en: ${file.path}')),
    );
  }

  Future<void> _shareNodesFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/campus_nodes.json';
    final file = File(filePath);

    if (await file.exists()) {
      await Share.shareXFiles([XFile(filePath)], text: 'Mis nodos del campus');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para compartir')),
      );
    }
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      await _positionStream?.cancel();
      setState(() {
        _isTracking = false;
        _positionStream = null;
      });
      await _saveNodesToFile();
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
      try {
        final initialPosition = await Geolocator.getCurrentPosition();
        setState(() {
          _currentPosition = initialPosition;
          _positionCount = 1;
          _positionHistory = [initialPosition];
        });
      } catch (e) {
        print("Error obteniendo posición inicial: $e");
      }
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((Position position) {
        setState(() {
          _currentPosition = position;
          if (!_isManualMode) {
            _positionCount++;
            _positionHistory.add(position);
            if (_showMap) {
              _updateMarkers();
            }
          }
        });
      });

      setState(() {
        _isTracking = true;
      });
    }
  }

  void _updateMarkers() {
    _markers.clear();
    for (int i = 0; i < _positionHistory.length; i++) {
      final position = _positionHistory[i];
      _markers.add(
        Marker(
          point: latlong2.LatLng(position.latitude, position.longitude),
          child: const Icon(
            Icons.location_on,
            color: Colors.red,
            size: 40.0,
          ),
        ),
      );
    }
    if (_positionHistory.isNotEmpty) {
      final lastPosition = _positionHistory.last;
      _mapController.move(
        latlong2.LatLng(lastPosition.latitude, lastPosition.longitude),
        15.0,
      );
    }
  }

  void _toggleMap() {
    setState(() {
      _showMap = !_showMap;
      if (_showMap && _positionHistory.isNotEmpty) {
        _updateMarkers();
      }
    });
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
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: _positionHistory.isNotEmpty ? _toggleMap : null,
            tooltip: 'Mostrar mapa',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _positionHistory.isNotEmpty ? _shareNodesFile : null,
            tooltip: 'Compartir datos',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showMap)
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _positionHistory.isNotEmpty
                      ? latlong2.LatLng(
                          _positionHistory.last.latitude,
                          _positionHistory.last.longitude,
                        )
                      : const latlong2.LatLng(0, 0),
                  initialZoom: 15.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.gps_tracker',
                  ),
                  MarkerLayer(
                    markers: _markers,
                  ),
                  if (_positionHistory.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _positionHistory
                              .map((p) => latlong2.LatLng(p.latitude, p.longitude))
                              .toList(),
                          color: Colors.blue,
                          strokeWidth: 4.0,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (!_showMap)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Campo de nombre
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Nombre:', style: TextStyle(fontSize: 18, color: Colors.black87)),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Ingrese el nombre',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                              ),
                              enabled: !_isTracking,
                              onChanged: (value) {
                                setState(() {
                                  _nombre = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Selector de tipo
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tipo:', style: TextStyle(fontSize: 18, color: Colors.black87)),
                          DropdownButton<String>(
                            value: _selectedTipo,
                            items: _tipos
                                .map((tipo) => DropdownMenuItem<String>(
                                      value: tipo,
                                      child: Text(tipo, style: const TextStyle(fontSize: 18)),
                                    ))
                                .toList(),
                            onChanged: _isTracking
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedTipo = value!;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    // Selector de sector
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sector:', style: TextStyle(fontSize: 18, color: Colors.black87)),
                          DropdownButton<int>(
                            value: _selectedSector,
                            items: List.generate(8, (index) => index + 1)
                                .map((sector) => DropdownMenuItem<int>(
                                      value: sector,
                                      child: Text(sector.toString(), 
                                          style: const TextStyle(fontSize: 18)),
                                    ))
                                .toList(),
                            onChanged: _isTracking 
                                ? null 
                                : (value) {
                                    setState(() {
                                      _selectedSector = value!;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    // Selector de nivel
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Nivel:', style: TextStyle(fontSize: 18, color: Colors.black87)),
                          DropdownButton<int>(
                            value: _selectedNivel,
                            items: _niveles
                                .map((nivel) => DropdownMenuItem<int>(
                                      value: nivel,
                                      child: Text(nivel.toString(), style: const TextStyle(fontSize: 18)),
                                    ))
                                .toList(),
                            onChanged: _isTracking
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedNivel = value!;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    _buildDataRow('Latitud:', lat),
                    _buildDataRow('Longitud:', lng),
                    _buildDataRow('Conteo de Nodos:', _positionCount.toString()),
                    // Switch para elegir modo manual o automático
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Modo manual', style: TextStyle(fontSize: 18, color: Colors.black87)),
                          Switch(
                            value: _isManualMode,
                            onChanged: (value) {
                              setState(() {
                                _isManualMode = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_isTracking && _isManualMode)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Añadir nodo actual'),
                            onPressed: _currentPosition == null
                                ? null
                                : () {
                                    setState(() {
                                      _positionHistory.add(_currentPosition!);
                                      _positionCount++;
                                      if (_showMap) {
                                        _updateMarkers();
                                      }
                                    });
                                  },
                          ),
                        ),
                      ),
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
            ),
        ],
      ),
    );
  }
}