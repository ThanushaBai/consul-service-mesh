from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route('/api', methods=['GET'])
def api():
    return jsonify({
        'service': 'backend',
        'timestamp' : datetime.utcnow().isoformat(),
        'message': 'Hello from the backend!'
    })

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)