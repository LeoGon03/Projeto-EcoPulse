import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/relato_model.dart';
import 'database_helper.dart';

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';

  static Future<List<RelatoModel>> getRelatos({
    double latitude = -23.55052,
    double longitude = -46.633308,
    double raioKm = 50.0,
  }) async {
    List<RelatoModel> relatosServidor = [];

    try {
      final url = '$baseUrl/relatos/proximos?latitude=$latitude&longitude=$longitude&raio_km=$raioKm';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final List<dynamic> lista = body['relatos'] ?? [];
        relatosServidor = lista.map((json) => RelatoModel.fromJson(json)).toList();

        for (var r in relatosServidor) {
          await DatabaseHelper.instance.salvarRelatoLocal(r, synced: true);
        }
      }
    } catch (e) {
      print('Dispositivo Offline ou timeout. Carregando dados exclusivos do SQLite local...');
      return await DatabaseHelper.instance.getTodosRelatosLocais();
    }

    final pendentesLocais = await DatabaseHelper.instance.getRelatosPendentes();
    return [...pendentesLocais, ...relatosServidor];
  }

  static Future<bool> enviarRelato(RelatoModel relato) async {
    try {
      final payload = json.encode(relato.toApiJson());
      print('📤 Enviando Payload para API: $payload');

      final response = await http.post(
        Uri.parse('$baseUrl/relatos'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      ).timeout(const Duration(seconds: 4));

      print('📥 Resposta da API Status: ${response.statusCode}');
      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
        await DatabaseHelper.instance.salvarRelatoLocal(relato, synced: true);
        return true;
      } else {
        print('❌ Erro da API (${response.statusCode}): ${response.body}');
      }
    } on SocketException catch (_) {
      print('Sem conexão com a internet. Salvando offline...');
    } catch (e) {
      print('Erro ao enviar para API: $e. Salvando offline...');
    }

    await DatabaseHelper.instance.salvarRelatoLocal(relato, synced: false);
    return false;
  }

  static Future<int> sincronizarPendentes() async {
    final pendentes = await DatabaseHelper.instance.getRelatosPendentes();
    int enviadosComSucesso = 0;

    for (var relato in pendentes) {
      try {
        final payload = json.encode(relato.toApiJson());
        print('🔄 Sincronizando ID ${relato.id}: $payload');

        final response = await http.post(
          Uri.parse('$baseUrl/relatos'),
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );

        if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
          if (relato.id != null) {
            await DatabaseHelper.instance.marcarComoSincronizado(relato.id!);
          }
          enviadosComSucesso++;
        } else {
          print('❌ Falha na sincronização do ID ${relato.id} (${response.statusCode}): ${response.body}');
        }
      } catch (e) {
        print('Falha ao sincronizar registro id ${relato.id}: $e');
      }
    }
    return enviadosComSucesso;
  }
}