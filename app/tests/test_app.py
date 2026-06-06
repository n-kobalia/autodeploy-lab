import pytest
from app import app as flask_app, db

@pytest.fixture
def client():
    flask_app.config['TESTING'] = True
    flask_app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    with flask_app.app_context():
        db.create_all()
        yield flask_app.test_client()
        db.drop_all()

def test_home_returns_200(client):
    response = client.get('/')
    assert response.status_code == 200

def test_api_returns_json(client):
    response = client.get('/api')
    assert response.status_code == 200
    data = response.get_json()
    assert 'message' in data

def test_health_returns_200(client):
    response = client.get('/health')
    assert response.status_code == 200

def test_health_includes_database_status(client):
    response = client.get('/health')
    data = response.get_json()
    assert 'database' in data

def test_create_item(client):
    response = client.post('/items',
        json={'name': 'Test Item', 'description': 'A test item'})
    assert response.status_code == 201
    data = response.get_json()
    assert data['name'] == 'Test Item'

def test_get_items(client):
    client.post('/items', json={'name': 'Item 1'})
    client.post('/items', json={'name': 'Item 2'})
    response = client.get('/items')
    assert response.status_code == 200
    data = response.get_json()
    assert data['count'] == 2

def test_update_item(client):
    create = client.post('/items', json={'name': 'Original'})
    item_id = create.get_json()['id']
    response = client.put(f'/items/{item_id}', json={'name': 'Updated'})
    assert response.status_code == 200
    assert response.get_json()['name'] == 'Updated'

def test_delete_item(client):
    create = client.post('/items', json={'name': 'To Delete'})
    item_id = create.get_json()['id']
    response = client.delete(f'/items/{item_id}')
    assert response.status_code == 200

def test_metrics_endpoint_exists(client):
    response = client.get('/metrics')
    assert response.status_code == 200