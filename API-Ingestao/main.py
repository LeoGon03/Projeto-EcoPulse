import asyncio
from contextlib import asynccontextmanager
from enum import Enum
import json
import os
from typing import List

from fastapi import (
    FastAPI,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from pydantic import BaseModel, Field
import pika
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
import redis.asyncio as aioredis

#  Configurações de Infraestrutura (Variáveis de Ambiente com Fallback) 
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "localhost")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", 5672))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "ecopulse")
RABBITMQ_PASS = os.getenv("RABBITMQ_PASS", "ecopulse_pass")

QUEUE_NAME = "relatos_ambientais_queue"
DLX_NAME = "relatos_dlx"
DLQ_ROUTING_KEY = "relatos_dead_letter"

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "ecopulse_db")
DB_USER = os.getenv("DB_USER", "ecopulse_user")
DB_PASS = os.getenv("DB_PASS", "ecopulse_password")

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_CHANNEL = "alertas_tempo_real"

# Cliente Redis Síncrono (Cache de Consultas)
sync_redis = redis.Redis(
    host=REDIS_HOST, port=REDIS_PORT, db=0, decode_responses=True
)


#  Gerenciador de Conexões WebSocket 
class ConnectionManager:

    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: str):
        for connection in list(self.active_connections):
            try:
                await connection.send_text(message)
            except Exception:
                self.disconnect(connection)


manager = ConnectionManager()

#  Tarefa Assíncrona: Escutar Redis Pub/Sub e retransmitir via WebSocket 
async def listen_to_redis_pubsub():
    async_redis = aioredis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0)
    pubsub = async_redis.pubsub()
    await pubsub.subscribe(REDIS_CHANNEL)

    try:
        async for message in pubsub.listen():
            if message["type"] == "message":
                dados_alerta = message["data"].decode("utf-8")
                await manager.broadcast(dados_alerta)
    except asyncio.CancelledError:
        await pubsub.unsubscribe(REDIS_CHANNEL)


#  Ciclo de Vida da Aplicação (Lifespan) 
@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(listen_to_redis_pubsub())
    yield
    task.cancel()

# Inicialização da API
app = FastAPI(
    title="EcoPulse - API de Ingestão, Consulta e Alertas Tempo Real",
    description="Backend distribuído com suporte a WebSockets, Redis Cache, RabbitMQ DLQ e PostGIS",
    version="1.2.0",
    lifespan=lifespan,
)


#  Enums e Schemas Pydantic 
class TipoRisco(str, Enum):
    OBSTRUCAO = "OBSTRUCAO"
    ILHA_CALOR = "ILHA_CALOR"
    QUALIDADE_AR = "QUALIDADE_AR"
    INVERSAO_TERMICA = "INVERSAO_TERMICA"
    ALAGAMENTO = "ALAGAMENTO"


class RelatoSchema(BaseModel):
    usuario_id: str
    descricao: str
    tipo_risco: TipoRisco
    grau_severidade: int = Field(..., ge=1, le=5)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


#  Auxiliar de Conexão com o PostgreSQL 
def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        cursor_factory=RealDictCursor,
    )

# ENDPOINT WEBSOCKET: ALERTAS EM TEMPO REAL

@app.websocket("/ws/alertas")
async def websocket_endpoint(websocket: WebSocket):
    """Canal WebSocket para recepção assíncrona de alertas ambientais em tempo real."""
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

# ENDPOINT HTTP POST: INGESTÃO DE RELATOS

@app.post("/api/v1/relatos", status_code=status.HTTP_202_ACCEPTED)
def registrar_relato(relato: RelatoSchema):
    """Envia o relato para a fila do RabbitMQ (com suporte à DLQ)."""
    try:
        credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
        parameters = pika.ConnectionParameters(
            host=RABBITMQ_HOST, port=RABBITMQ_PORT, credentials=credentials
        )
        connection = pika.BlockingConnection(parameters)
        channel = connection.channel()

        # Argumentos alinhados com a configuração da DLQ do consumidor
        queue_args = {
            "x-dead-letter-exchange": DLX_NAME,
            "x-dead-letter-routing-key": DLQ_ROUTING_KEY,
        }

        channel.queue_declare(
            queue=QUEUE_NAME, durable=True, arguments=queue_args
        )

        mensagem = relato.model_dump()
        channel.basic_publish(
            exchange="",
            routing_key=QUEUE_NAME,
            body=json.dumps(mensagem),
            properties=pika.BasicProperties(delivery_mode=2),
        )

        connection.close()
        return {
            "status": "aceito",
            "mensagem": "Relato enfileirado para processamento assíncrono.",
            "dados": mensagem,
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Erro ao publicar no RabbitMQ: {str(e)}",
        )

# ENDPOINT HTTP GET: CONSULTA GEOESPACIAL

@app.get("/api/v1/relatos/proximos", status_code=status.HTTP_200_OK)
def listar_relatos_proximos(
    latitude: float = Query(
        ..., ge=-90, le=90, description="Latitude atual do usuário"
    ),
    longitude: float = Query(
        ..., ge=-180, le=180, description="Longitude atual do usuário"
    ),
    raio_km: float = Query(
        5.0, gt=0, le=50, description="Raio de busca em quilômetros"
    ),
):
    """Consulta relatos por proximidade geográfica via PostGIS com cache no Redis (60s)."""
    cache_key = (
        f"relatos_proximos:{round(latitude, 4)}:{round(longitude, 4)}:{raio_km}"
    )

    try:
        # 1. Tenta recuperar do Redis
        cached_data = sync_redis.get(cache_key)
        if cached_data:
            response = json.loads(cached_data)
            response["origem"] = "CACHE_REDIS"
            return response

        # 2. Se houver Cache Miss, consulta o PostGIS
        conn = get_db_connection()
        cursor = conn.cursor()

        query = """
            SELECT 
                id, 
                usuario_id, 
                descricao, 
                tipo_risco, 
                grau_severidade,
                ST_Y(localizacao::geometry) AS latitude,
                ST_X(localizacao::geometry) AS longitude,
                ROUND((ST_DistanceSphere(localizacao, ST_SetSRID(ST_MakePoint(%s, %s), 4326)) / 1000.0)::numeric, 2)::float AS distancia_km,
                TO_CHAR(criado_em, 'YYYY-MM-DD"T"HH24:MI:SS') AS criado_em
            FROM relatos
            WHERE ST_DWithin(
                localizacao::geography, 
                ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, 
                %s * 1000
            )
            ORDER BY distancia_km ASC;
        """

        cursor.execute(
            query, (longitude, latitude, longitude, latitude, raio_km)
        )
        relatos_proximos = cursor.fetchall()

        cursor.close()
        conn.close()

        resultado = {
            "total": len(relatos_proximos),
            "raio_km": raio_km,
            "relatos": relatos_proximos,
            "origem": "BANCO_POSTGIS",
        }

        # 3. Guarda no Redis por 60 segundos
        sync_redis.setex(cache_key, 60, json.dumps(resultado))
        return resultado

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Erro no processamento: {str(e)}",
        )