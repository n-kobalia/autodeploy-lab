import os
import time
from flask import Flask, jsonify, render_template, request
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# ── Database configuration ───────────────────────────────────────────
# Reads connection string from environment variable.
# Falls back to SQLite for local development and testing.
database_url = os.environ.get('DATABASE_URL', 'sqlite:///dev.db')
# psycopg3 uses postgresql+psycopg:// prefix
if database_url.startswith('postgresql://'):
    database_url = database_url.replace('postgresql://', 'postgresql+psycopg://', 1)
app.config['SQLALCHEMY_DATABASE_URI'] = database_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
migrate = Migrate(app, db)

# ── Database model ───────────────────────────────────────────────────
class Item(db.Model):
    __tablename__ = 'items'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    description = db.Column(db.String(255), nullable=True)
    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'created_at': str(self.created_at)
        }

# ── Prometheus metrics ───────────────────────────────────────────────
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
    from flask import g
    g.start_time = time.time()

@app.after_request
def record_metrics(response):
    from flask import g
    latency = time.time() - g.start_time
    REQUEST_LATENCY.labels(endpoint=request.path).observe(latency)
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        status=response.status_code
    ).inc()
    return response

# ── Routes ───────────────────────────────────────────────────────────
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
    # Also checks database connectivity
    try:
        db.session.execute(db.text('SELECT 1'))
        db_status = 'healthy'
    except Exception:
        db_status = 'unhealthy'
    
    status = 'healthy' if db_status == 'healthy' else 'degraded'
    code = 200 if status == 'healthy' else 503
    return jsonify({
        'status': status,
        'database': db_status
    }), code

@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

# ── CRUD endpoints ───────────────────────────────────────────────────
@app.route('/items', methods=['GET'])
def get_items():
    items = Item.query.all()
    return jsonify({
        'items': [item.to_dict() for item in items],
        'count': len(items)
    })

@app.route('/items', methods=['POST'])
def create_item():
    data = request.get_json()
    if not data or 'name' not in data:
        return jsonify({'error': 'name is required'}), 400
    item = Item(
        name=data['name'],
        description=data.get('description', '')
    )
    db.session.add(item)
    db.session.commit()
    return jsonify(item.to_dict()), 201

@app.route('/items/<int:item_id>', methods=['PUT'])
def update_item(item_id):
    item = db.get_or_404(Item, item_id)
    data = request.get_json()
    if 'name' in data:
        item.name = data['name']
    if 'description' in data:
        item.description = data['description']
    db.session.commit()
    return jsonify(item.to_dict())

@app.route('/items/<int:item_id>', methods=['DELETE'])
def delete_item(item_id):
    item = db.get_or_404(Item, item_id)
    db.session.delete(item)
    db.session.commit()
    return jsonify({'message': f'Item {item_id} deleted'}), 200

# ── Entry point ──────────────────────────────────────────────────────
if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('ENVIRONMENT', 'development') == 'development'
    app.run(host='0.0.0.0', port=port, debug=debug)