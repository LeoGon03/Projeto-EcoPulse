import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/relato_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ecopulse_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE relatos_locais (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id TEXT NOT NULL,
        descricao TEXT NOT NULL,
        tipo_risco TEXT NOT NULL,
        grau_severidade INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        criado_em TEXT
      )
    ''');
  }

  // Salvar relato no banco local
  Future<int> salvarRelatoLocal(RelatoModel relato, {bool synced = false}) async {
  final db = await instance.database;
  final map = relato.toSqliteJson();
  map['is_synced'] = synced ? 1 : 0;
  map.remove('id');
  return await db.insert('relatos_locais', map);
}

  // Buscar relatos que ainda não foram sincronizados com o backend
  Future<List<RelatoModel>> getRelatosPendentes() async {
    final db = await instance.database;
    final result = await db.query(
      'relatos_locais',
      where: 'is_synced = ?',
      whereArgs: [0],
    );

    return result.map((json) => RelatoModel.fromJson(json)).toList();
  }

  // Marcar relato como sincronizado após sucesso no envio para a API
  Future<int> marcarComoSincronizado(int localId) async {
    final db = await instance.database;
    return await db.update(
      'relatos_locais',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  // Retorna todos os relatos armazenados em cache local
  Future<List<RelatoModel>> getTodosRelatosLocais() async {
    final db = await instance.database;
    final result = await db.query('relatos_locais', orderBy: 'id DESC');
    return result.map((json) => RelatoModel.fromJson(json)).toList();
  }
}