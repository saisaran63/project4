import os, pytest, httpx
from fastapi import status
from app import main

@pytest.fixture
def client():
    from fastapi.testclient import TestClient
    return TestClient(main.app)

def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == status.HTTP_200_OK

def test_create_list_cycle(monkeypatch, client):
    # mock boto3 table
    class FakeTable:
        def __init__(self): self.rows = {}
        def put_item(self, Item): self.rows[Item["id"]] = Item
        def get_item(self, Key): return {"Item": self.rows.get(Key["id"])}
        def update_item(self, Key, UpdateExpression=None, ExpressionAttributeValues=None):
            item = self.rows.get(Key["id"], {"id": Key["id"], "title": "", "done": False})
            item["title"] = ExpressionAttributeValues[":t"]
            item["done"] = ExpressionAttributeValues[":d"]
            self.rows[Key["id"]] = item
        def delete_item(self, Key): self.rows.pop(Key["id"], None)
        def scan(self, Limit=None): return {"Items": list(self.rows.values())}

    class FakeResource:
        def Table(self, name): return FakeTable()

    monkeypatch.setattr(main, "dynamodb", FakeResource())
    os.environ["TABLE_NAME"] = "unit-test"

    r = client.post("/todos", json={"title": "demo"})
    assert r.status_code == 201
    todo = r.json()
    tid = todo["id"]

    r = client.get(f"/todos/{tid}")
    assert r.status_code == 200

    r = client.put(f"/todos/{tid}", json={"title":"updated","done":True})
    assert r.status_code == 200
    assert r.json()["done"] is True

    r = client.get("/todos")
    assert r.status_code == 200
    assert len(r.json()) >= 1

    r = client.delete(f"/todos/{tid}")
    assert r.status_code == 204
