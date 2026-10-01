import os
import requests
from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

BACKEND_URL = os.getenv('BACKEND_URL', 'http://backend:8080')

@app.route('/', methods=['GET'])
def index():
    try:
        response = requests.get(f'{BACKEND_URL}/api', timeout=5)
        backend_data = response.json()
        return jsonify({
            'service': 'frontend',
            'timestamp': datetime.utcnow().isoformat(),
            'backend_response': backend_data,
            'backend_url_used': BACKEND_URL
        })
    except requests.exceptions.RequestException as e:
        return jsonify({
            'service': 'frontend',
            'error': str(e),
            'backend_url_used': BACKEND_URL
        }), 502

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
