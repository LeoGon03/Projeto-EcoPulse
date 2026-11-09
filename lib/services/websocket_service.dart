import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/relato_model.dart';

class WebSocketService {
  WebSocketChannel? _channel;

  void conectar(Function(RelatoModel) onNovoAlerta) {
    try {
      final uri = Uri.parse('ws://10.0.2.2:8000/ws/alertas');
      _channel = IOWebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) {
          final data = json.decode(message);
          final relato = RelatoModel.fromJson(data);
          onNovoAlerta(relato);
        },
        onError: (error) {
          print('Erro no WebSocket: $error');
        },
        onDone: () {
          print('Conexão WebSocket encerrada.');
        },
      );
    } catch (e) {
      print('Erro ao conectar ao WebSocket: $e');
    }
  }

  void desconectar() {
    _channel?.sink.close();
  }
}