from flask import Flask, render_template, request, jsonify
import logging
import os
from prometheus_client import Counter, start_http_server, generate_latest
import random
import redis
import socket
import string


app = Flask(__name__, 
            template_folder='/usr/share/webapps/giropops-senhas/templates',
            static_folder='/usr/share/webapps/giropops-senhas/static')

redis_host = os.environ.get('REDIS_HOST', 'redis-service')
redis_port = 6379
redis_password = ""

r = redis.StrictRedis(host=redis_host, port=redis_port, password=redis_password, decode_responses=True)

senha_gerada_counter = Counter('senha_gerada', 'Contador de senhas geradas')


def criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais):
    caracteres = string.ascii_letters

    if incluir_numeros:
        caracteres += string.digits

    if incluir_caracteres_especiais:
        caracteres += string.punctuation

    senha = ''.join(random.choices(caracteres, k=tamanho))

    return senha

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        tamanho = int(request.form.get('tamanho', 8))
        incluir_numeros = request.form.get('incluir_numeros') == 'on'
        incluir_caracteres_especiais = request.form.get('incluir_caracteres_especiais') == 'on'
        senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)

        r.lpush("senhas", senha)
        senha_gerada_counter.inc()
    senhas = r.lrange("senhas", 0, 9)
    if senhas:
        senhas_geradas = [{"id": index + 1, "senha": senha} for index, senha in enumerate(senhas)]
        return render_template('index.html', senhas_geradas=senhas_geradas, senha=senhas_geradas[0]['senha'] or '' )
    return render_template('index.html')


@app.route('/api/gerar-senha', methods=['POST'])
def gerar_senha_api():
    dados = request.get_json()

    tamanho = int(dados.get('tamanho', 8))
    incluir_numeros = dados.get('incluir_numeros', False)
    incluir_caracteres_especiais = dados.get('incluir_caracteres_especiais', False)

    senha = criar_senha(tamanho, incluir_numeros, incluir_caracteres_especiais)
    r.lpush("senhas", senha)
    senha_gerada_counter.inc()

    return jsonify({"senha": senha})

@app.route('/api/senhas', methods=['GET'])
def listar_senhas():
    senhas = r.lrange("senhas", 0, 9)

    resposta = [{"id": index + 1, "senha": senha} for index, senha in enumerate(senhas)]
    return jsonify(resposta)

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
