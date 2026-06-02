import os
from flask import Flask, jsonify, render_template
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time

app = Flask(__name__)

REQUEST_COUNT = Counter(
    'app_request_count_total',
    'Total number of requests received',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'app_request_latency_seconds',
    'Request latency in seconds',
    ['endpoint']
)

@app.before_request
def start_timer():
    from flask import g, request
    g.start_time = time.time()

@app.after_request
def record_metrics(response):
    from flask import g, request
    latency = time.time() - g.start_time
    REQUEST_LATENCY.labels(endpoint=request.path).observe(latency)
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        status=response.status_code
    ).inc()
    return response

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/api')
def api_info():
    app_version = os.environ.get('APP_VERSION', '1.0.0')
    environment = os.environ.get('ENVIRONMENT', 'development')
    return jsonify({
        'message': 'AutoDeploy Lab is running on Oracle Cloud via GitOps',
        'version': app_version,
        'environment': environment
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'}), 200

@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/items')
def items():
    sample_items = [
        {'id': 1, 'name': 'Widget A'},
        {'id': 2, 'name': 'Widget B'},
        {'id': 3, 'name': 'Widget C'},
    ]
    return jsonify({'items': sample_items, 'count': len(sample_items)})

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('ENVIRONMENT', 'development') == 'development'
    app.run(host='0.0.0.0', port=port, debug=debug)