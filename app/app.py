import os
from flask import Flask, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time

app = Flask(__name__)

# ── Prometheus metrics ──────────────────────────────────────────────
# A Counter tracks how many times something has happened (never goes down).
# A Histogram tracks how long something took (like request duration).
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

# ── Middleware: runs before and after every request ─────────────────
@app.before_request
def start_timer():
    # Store the start time on the request context
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

# ── Routes ──────────────────────────────────────────────────────────
@app.route('/')
def home():
    app_version = os.environ.get('APP_VERSION', '1.0.0')
    environment = os.environ.get('ENVIRONMENT', 'development')
    return jsonify({
        'message': 'AutoDeploy Lab is running on Oracle Cloud via GitOps',
        'version': app_version,
        'environment': environment
    })

@app.route('/health')
def health():
    # Kubernetes will call this endpoint to know if the pod is alive.
    # It must return HTTP 200 when healthy.
    return jsonify({'status': 'healthy'}), 200

@app.route('/metrics')
def metrics():
    # Prometheus will scrape this endpoint on a schedule to collect metrics.
    # generate_latest() formats everything in the Prometheus text format.
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/items')
def items():
    # A simple second endpoint to give the app realistic traffic to observe.
    sample_items = [
        {'id': 1, 'name': 'Widget A'},
        {'id': 2, 'name': 'Widget B'},
        {'id': 3, 'name': 'Widget C'},
    ]
    return jsonify({'items': sample_items, 'count': len(sample_items)})

# ── Entry point ─────────────────────────────────────────────────────
if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('ENVIRONMENT', 'development') == 'development'
    app.run(host='0.0.0.0', port=port, debug=debug)