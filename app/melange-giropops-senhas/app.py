from flask import Flask, render_template, request, jsonify
import logging
import os
from prometheus_client import Counter, Histogram, Gauge, start_http_server, generate_latest
import random
import redis
import socket
import string
import time

app = Flask(__name__, 
            template_folder='/usr/share/webapps/giropops-senhas/templates',
            static_folder='/usr/share/webapps/giropops-senhas/static')

redis_host = os.environ.get('REDIS_HOST', 'redis-service')
redis_port = 6379
redis_password = ""

senha_gerada_counter = Counter('senha_gerada', 'Contador de senhas geradas')
senha_gerada_numeros_counter = Counter('senha_gerada_numeros', 'Contador de senhas geradas com números')
senha_gerada_caracteres_especiais_counter = Counter('senha_gerada_caracteres_especiais', 'Contador de senhas geradas com caracteres especiais')
senha_gerada_sem_caracteres_especiais_counter = Counter('senha_gerada_sem_caracteres_especiais', 'Contador de senhas geradas sem caracteres especiais')
senha_gerada_sem_numeros_counter = Counter('senha_gerada_sem_numeros', 'Contador de senhas geradas sem números')
redis_connection_error_counter = Counter('redis_connection_errors', 'Contador de erros de conexão com Redis')
tempo_gerar_senha_histogram = Histogram('tempo_gerar_senha', 'Tempo para gerar uma senha')
tempo_resposta_api_histogram = Histogram('tempo_resposta_api', 'Tempo de resposta da API')
api_erro_counter = Counter('api_errors', 'Contador de erros de API', ['endpoint', 'status_code'])
tamanho_fila_senhas_gauge = Gauge('tamanho_fila_senhas', 'Tamanho da fila de senhas no Redis')

try:
    r = redis.StrictRedis(host=redis_host, port=redis_port, password=redis_password, decode_responses=True)
    r.ping()
except redis.ConnectionError:
    logging.error("Erro ao conectar ao Redis")
    redis_connection_error_counter.inc()
    r = None

def criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais):
    caracteres = string.ascii_letters

    if incluir_numeros:
        caracteres += string.digits
        senha_gerada_numeros_counter.inc()

    if incluir_caracteres_especiais:
        caracteres += string.punctuation
        senha_gerada_caracteres_especiais_counter.inc()
    else:
        senha_gerada_sem_caracteres_especiais_counter.inc()

    senha = ''.join(random.choices(caracteres, k=tamanho))

    if not any(char.isdigit() for char in senha):
        senha_gerada_sem_numeros_counter.inc()

    return senha

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        tamanho = int(request.form.get('tamanho', 8))
        incluir_numeros = request.form.get('incluir_numeros') == 'on'
        incluir_caracteres_especiais = request.form.get('incluir_caracteres_especiais') == 'on'

        #Medir time de gerar uma senha:
        start_time = time.time()
        senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)
        tempo_gerar_senha_histogram.observe(time.time() - start_time)

        if r:
            r.lpush("senhas", senha)
            senha_gerada_counter.inc()

    senhas = r.lrange("senhas", 0, 9) if r else []
    if senhas:
        senhas_geradas = [{"id": index + 1, "senha": senha} for index, senha in enumerate(senhas)]
        return render_template('index.html', senhas_geradas=senhas_geradas, senha=senhas_geradas[0]['senha'] or '' )
    return render_template('index.html')


@app.route('/api/gerar-senha', methods=['POST'])
@tempo_resposta_api_histogram.time()
def gerar_senha_api():
    dados = request.get_json()

    tamanho = int(dados.get('tamanho', 8))
    incluir_numeros = dados.get('incluir_numeros', False)
    incluir_caracteres_especiais = dados.get('incluir_caracteres_especiais', False)

    start_time = time.time()
    try:
        senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)
        tempo_gerar_senha_histogram.observe(time.time() - start_time)
        if r:
            r.lpush("senhas", senha)
            senha_gerada_counter.inc()
        return jsonify({"senha": senha}), 200
    except Exception as e:
        api_erro_counter.labels(endpoint='/api/gerar-senha', status_code='500').inc()
        logging.error(f"Erro na API /api/gerar-senha: {str(e)}", exc_info=True)
        return jsonify({"error": "Erro ao gerar senha"}), 500

@app.route('/api/senhas', methods=['GET'])
@tempo_resposta_api_histogram.time()
def listar_senhas():
    try:
        senhas = r.lrange("senhas", 0, 9) if r else []
        tamanho_fila_senhas_gauge.set(len(senhas))

        resposta = [{"id": index + 1, "senha": senha} for index, senha in enumerate(senhas)]
        return jsonify(resposta)
    except Exception as e:
        api_erro_counter.labels(endpoint='/api/senhas', status_code='500').inc()
        logging.error(f"Erro na API /api/senhas: {str(e)}", exc_info=True)
        return jsonify({"error": "Erro ao listar senhas"}), 500

@app.route('/metrics')
def metrics():
    return generate_latest()

def start_prometheus_server(port):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            if s.connect_ex(('0.0.0.0', port)) == 0:
                logging.error(f"Porta {port} já está em uso. Não será possível iniciar Prometheus.")
                return False
            
        start_http_server(port)
        return True
    except Exception as e:
        logging.error(f"Erro ao tentar iniciar Prometheus: {str(e)}", exc_info=True)
        return False
    
if __name__ == '__main__':
    logging.basicConfig(filename='tmp/error.log', level=logging.DEBUG)
    port = 8089  
    app.run(host='0.0.0.0', debug=False)
