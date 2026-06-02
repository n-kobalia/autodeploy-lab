import pytest
from app import app as flask_app

@pytest.fixture
def client():
    # Sets Flask into testing mode (no real server, no debug errors hiding)
    flask_app.config['TESTING'] = True
    with flask_app.test_client() as client:
        yield client

def test_home_returns_200(client):
    response = client.get('/')
    assert response.status_code == 200


def test_health_returns_200(client):
    response = client.get('/health')
    assert response.status_code == 200

def test_health_status_is_healthy(client):
    response = client.get('/health')
    data = response.get_json()
    assert data['status'] == 'healthy'

def test_items_returns_list(client):
    response = client.get('/items')
    assert response.status_code == 200
    data = response.get_json()
    assert 'items' in data
    assert len(data['items']) == 3

def test_metrics_endpoint_exists(client):
    response = client.get('/metrics')
    assert response.status_code == 200

def test_api_returns_json(client):
    response = client.get('/api')
    assert response.status_code == 200
    data = response.get_json()
    assert 'message' in data