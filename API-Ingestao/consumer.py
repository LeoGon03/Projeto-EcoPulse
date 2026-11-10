import json
import os
import pika
import psycopg2
import redis
import time

# Configurações do RabbitMQ
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "localhost")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", 5672))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "ecopulse")
RABBITMQ_PASS = os.getenv("RABBITMQ_PASS", "ecopulse_pass")

QUEUE_NAME = "relatos_ambientais_queue"
DLX_NAME = "relatos_dlx"
DLQ_NAME = "relatos_ambientais_dlq"
DLQ_ROUTING_KEY = "relatos_dead_letter"

# Configurações do PostgreSQL / PostGIS
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "ecopulse_db")
DB_USER = os.getenv("DB_USER", "ecopulse_user")
DB_PASS = os.getenv("DB_PASS", "ecopulse_password")

# Configurações do Redis Pub/Sub
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_CHANNEL = "alertas_tempo_real"

redis_client = redis.Redis(
    host=REDIS_HOST, port=REDIS_PORT, db=0, decode_responses=True
)


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
    )


def inicializar_banco():
    tentativas = 5
    while tentativas > 0:
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("CREATE EXTENSION IF NOT EXISTS postgis;")
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS relatos (
                    id SERIAL PRIMARY KEY,
                    usuario_id VARCHAR(100) NOT NULL,
                    descricao TEXT NOT NULL,
                    tipo_risco VARCHAR(50) NOT NULL,
                    grau_severidade INT NOT NULL,
                    localizacao GEOMETRY(Point, 4326) NOT NULL,
                    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """
            )
            conn.commit()
            cursor.close()
            conn.close()
            print(" [✓] Banco PostGIS conectado e inicializado com sucesso!")
            return
        except Exception as e:
            tentativas -= 1
            print(
                f" [!] Aguardando banco de dados/rede Docker... ({e}). Tentativas restantes: {tentativas}"
            )
            time.sleep(3)

    raise Exception(
        "Não foi possível conectar ao banco PostGIS após várias tentativas."
    )


def salvar_relato_no_banco(dados: dict):
    conn = get_db_connection()
    cursor = conn.cursor()

    # Validação defensiva de campos obrigatórios
    campos_obrigatorios = [
        "usuario_id",
        "descricao",
        "tipo_risco",
        "grau_severidade",
        "latitude",
        "longitude",
    ]
    for campo in campos_obrigatorios:
        if campo not in dados or dados[campo] is None:
            raise ValueError(f"Campo obrigatório ausente no payload: '{campo}'")

    query = """
        INSERT INTO relatos (usuario_id, descricao, tipo_risco, grau_severidade, localizacao)
        VALUES (%s, %s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326));
    """

    cursor.execute(
        query,
        (
            dados["usuario_id"],
            dados["descricao"],
            dados["tipo_risco"],
            dados["grau_severidade"],
            dados["longitude"],
            dados["latitude"],
        ),
    )

    conn.commit()
    cursor.close()
    conn.close()


def callback(ch, method, properties, body):
    try:
        dados = json.loads(body.decode("utf-8"))
        print(
            f" [x] Processando relato: {dados.get('tipo_risco')} - {dados.get('descricao')}"
        )

        # Persiste no PostGIS
        salvar_relato_no_banco(dados)
        print(" [✓] Relato persistido no PostgreSQL/PostGIS com sucesso!")

        # Define a flag indicando que o registro já foi sincronizado/confirmado pelo servidor
        dados["is_synced"] = True

        # Publica no canal Redis Pub/Sub para que o FastAPI envie via WebSocket
        redis_client.publish(REDIS_CHANNEL, json.dumps(dados))
        print(
            f" [📡] Alerta transmitido no canal Redis Pub/Sub ('{REDIS_CHANNEL}')."
        )

        # Confirma o processamento com ACK
        ch.basic_ack(delivery_tag=method.delivery_tag)

    except Exception as e:
        print(f" [!] FALHA ao processar mensagem: {e}")
        print(
            f" [↳] Redirecionando mensagem para a Dead Letter Queue ({DLQ_NAME})..."
        )

        # NACK com requeue=False envia a mensagem para a DLQ configurada
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
def iniciar_consumidor():
    inicializar_banco()

    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
    parameters = pika.ConnectionParameters(
        host=RABBITMQ_HOST, port=RABBITMQ_PORT, credentials=credentials
    )

    connection = pika.BlockingConnection(parameters)
    channel = connection.channel()

    # Declaração da DLX (Dead Letter Exchange) e DLQ
    channel.exchange_declare(
        exchange=DLX_NAME, exchange_type="direct", durable=True
    )
    channel.queue_declare(queue=DLQ_NAME, durable=True)
    channel.queue_bind(
        exchange=DLX_NAME, queue=DLQ_NAME, routing_key=DLQ_ROUTING_KEY
    )

    # Declaração da Fila Principal vinculada à DLX
    queue_args = {
        "x-dead-letter-exchange": DLX_NAME,
        "x-dead-letter-routing-key": DLQ_ROUTING_KEY,
    }

    try:
        channel.queue_delete(queue=QUEUE_NAME)
    except Exception:
        pass

    channel.queue_declare(queue=QUEUE_NAME, durable=True, arguments=queue_args)

    channel.basic_qos(prefetch_count=1)
    channel.basic_consume(queue=QUEUE_NAME, on_message_callback=callback)

    print(
        f" [*] Worker resiliente iniciado. Fila Principal: '{QUEUE_NAME}' | DLQ: '{DLQ_NAME}'"
    )
    print(" [*] Aguardando novas mensagens... Para sair pressione CTRL+C")
    channel.start_consuming()


if __name__ == "__main__":
    iniciar_consumidor()