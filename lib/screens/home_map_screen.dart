import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/relato_model.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/novo_relato_modal.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({Key? key}) : super(key: key);

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  String _camadaAtiva = 'TODAS';
  List<RelatoModel> _relatos = [];
  bool _carregando = true;
  bool _sincronizando = false;
  final WebSocketService _wsService = WebSocketService();

  final MapController _mapController = MapController();
  LatLng _posicaoAtual = const LatLng(-23.55052, -46.633308); // Padrão SP

  @override
  void initState() {
    super.initState();
    _obterLocalizacaoAtual();
    _carregarRelatos();
    _iniciarWebSocket();
  }

  @override
  void dispose() {
    _wsService.desconectar();
    super.dispose();
  }

  Future<void> _obterLocalizacaoAtual() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final novasCoordenadas = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _posicaoAtual = novasCoordenadas;
        });
        _mapController.move(novasCoordenadas, 15);
        _carregarRelatos();
      }
    } catch (e) {
      print('Erro ao obter localização GPS: $e');
    }
  }

  void _abrirModalNovoRelato(BuildContext context, LatLng ponto) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => NovoRelatoModal(
        latitude: ponto.latitude,
        longitude: ponto.longitude,
        onRelatoCriado: (novoRelato) async {
          final enviadoSucesso = await ApiService.enviarRelato(novoRelato);
          final relatoComStatus = novoRelato.copyWith(isSynced: enviadoSucesso);

          if (mounted) {
            setState(() {
              _relatos.insert(0, relatoComStatus);
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  enviadoSucesso
                      ? '✅ Alerta publicado no servidor!'
                      : '📶 Sem conexão. Alerta salvo no SQLite local para sincronização posterior!',
                ),
                backgroundColor: enviadoSucesso ? Colors.green : Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _carregarRelatos() async {
    if (!mounted) return;
    setState(() => _carregando = true);
    try {
      final relatosServidor = await ApiService.getRelatos(
        latitude: _posicaoAtual.latitude,
        longitude: _posicaoAtual.longitude,
      );

      if (mounted) {
        setState(() {
          final relatosPendentesLocais = _relatos.where((r) => !r.isSynced).toList();
          final List<RelatoModel> listaUnificada = [...relatosServidor];

          for (final pendente in relatosPendentesLocais) {
            final jaExisteNoServidor = listaUnificada.any((s) =>
                (s.id != null && s.id == pendente.id) ||
                (s.latitude == pendente.latitude &&
                    s.longitude == pendente.longitude &&
                    s.descricao == pendente.descricao));

            if (!jaExisteNoServidor) {
              listaUnificada.add(pendente);
            }
          }

          _relatos = listaUnificada;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar relatos: $e')),
        );
      }
    }
  }

  Future<void> _sincronizarRelatosOffline() async {
    setState(() => _sincronizando = true);
    try {
      if (mounted) {
        setState(() {
          _relatos = _relatos.map((r) => r.copyWith(isSynced: true)).toList();
        });
      }

      final totalSincronizados = await ApiService.sincronizarPendentes();
      await _carregarRelatos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              totalSincronizados > 0
                  ? 'Sincronizados $totalSincronizados relato(s) pendentes com o servidor!'
                  : 'Nenhum relato pendente de sincronização.',
            ),
            backgroundColor: totalSincronizados > 0 ? Colors.green : Colors.blueGrey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sincronizar dados offline: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sincronizando = false);
      }
    }
  }

  void _iniciarWebSocket() {
    _wsService.conectar((novoRelato) {
      if (mounted) {
        setState(() {
          final index = _relatos.indexWhere((r) =>
              (r.id != null && r.id == novoRelato.id) ||
              (r.latitude == novoRelato.latitude &&
                  r.longitude == novoRelato.longitude &&
                  r.descricao == novoRelato.descricao));

          if (index != -1) {
            _relatos[index] = novoRelato.copyWith(isSynced: true);
          } else {
            _relatos.insert(0, novoRelato);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ NOVO ALERTA: ${_getTituloRisco(novoRelato.tipoRisco)} - ${novoRelato.descricao}'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  Color _getCorSeveridade(int severidade) {
    switch (severidade) {
      case 5: return Colors.red;
      case 4: return Colors.orange;
      case 3: return Colors.amber;
      case 2: return Colors.blue;
      default: return Colors.green;
    }
  }

  IconData _getIconeRisco(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'ALAGAMENTO': return Icons.water_damage;
      case 'QUALIDADE_AR': return Icons.air;
      case 'ILHA_CALOR': return Icons.thermostat;
      default: return Icons.warning_amber_rounded;
    }
  }

  String _getTituloRisco(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'ALAGAMENTO': return 'Alagamento';
      case 'QUALIDADE_AR': return 'Qualidade do Ar';
      case 'ILHA_CALOR': return 'Ilha de Calor';
      default: return tipo;
    }
  }

  void _exibirDetalhesRelato(BuildContext context, RelatoModel relato) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getIconeRisco(relato.tipoRisco),
                  color: _getCorSeveridade(relato.grauSeveridade),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  _getTituloRisco(relato.tipoRisco),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Chip(
                  label: Text('Severidade: ${relato.grauSeveridade}/5'),
                  backgroundColor: _getCorSeveridade(relato.grauSeveridade).withOpacity(0.2),
                ),
              ],
            ),
            if (!relato.isSynced) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 16, color: Colors.orange),
                    SizedBox(width: 6),
                    Text(
                      'Pendente de sincronização com o servidor',
                      style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 24),
            const Text('Descrição:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(relato.descricao, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            Text(
              'Coordenadas: ${relato.latitude.toStringAsFixed(4)}, ${relato.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relatosFiltrados = _camadaAtiva == 'TODAS'
        ? _relatos
        : _relatos.where((r) => r.tipoRisco == _camadaAtiva).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoPulse - Mapa de Riscos'),
        actions: [
          IconButton(
            icon: _sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar Pendentes (Offline)',
            onPressed: _sincronizando ? null : _sincronizarRelatosOffline,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar Mapa',
            onPressed: _carregarRelatos,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _posicaoAtual,
              initialZoom: 13,
              onTap: (tapPosition, point) => _abrirModalNovoRelato(context, point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ecopulse.app',
              ),
              CircleLayer(
                circles: relatosFiltrados.map((relato) {
                  return CircleMarker(
                    point: LatLng(relato.latitude, relato.longitude),
                    radius: relato.grauSeveridade * 60.0,
                    useRadiusInMeter: true,
                    color: _getCorSeveridade(relato.grauSeveridade).withOpacity(0.3),
                    borderColor: _getCorSeveridade(relato.grauSeveridade),
                    borderStrokeWidth: 2,
                  );
                }).toList(),
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _posicaoAtual,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                      child: const Center(
                        child: Icon(Icons.my_location, color: Colors.blue, size: 18),
                      ),
                    ),
                  ),
                  ...relatosFiltrados.map((relato) {
                    return Marker(
                      point: LatLng(relato.latitude, relato.longitude),
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        onTap: () => _exibirDetalhesRelato(context, relato),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: relato.isSynced ? Colors.transparent : Colors.orange,
                                  width: relato.isSynced ? 0 : 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  _getIconeRisco(relato.tipoRisco),
                                  color: _getCorSeveridade(relato.grauSeveridade),
                                  size: 26,
                                ),
                              ),
                            ),
                            if (!relato.isSynced)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.cloud_off,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ],
          ),
          if (_carregando)
            const Center(
              child: CircularProgressIndicator(),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _camadaAtiva,
                    icon: const Icon(Icons.layers),
                    onChanged: (String? novaCamada) {
                      if (novaCamada != null) {
                        setState(() => _camadaAtiva = novaCamada);
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'TODAS', child: Text('Todas as Camadas')),
                      DropdownMenuItem(value: 'ALAGAMENTO', child: Text('🌊 Alagamentos')),
                      DropdownMenuItem(value: 'QUALIDADE_AR', child: Text('🌬️ Qualidade do Ar')),
                      DropdownMenuItem(value: 'ILHA_CALOR', child: Text('🔥 Ilhas de Calor')),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'btn_gps',
              onPressed: _obterLocalizacaoAtual,
              backgroundColor: Colors.white,
              child: const Icon(Icons.gps_fixed, color: Colors.blue),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.touch_app, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Toque em qualquer local do mapa para emitir um alerta',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
