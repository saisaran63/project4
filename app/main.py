from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import os, uuid, boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.getenv("TABLE_NAME", "todos-dev")
dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION","us-east-1"))
table = dynamodb.Table(TABLE_NAME)

app = FastAPI(title="ToDo API", version="1.0.0")

class Todo(BaseModel):
    id: str | None = None
    title: str
    done: bool = False

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/todos")
def list_todos():
    try:
        resp = table.scan(Limit=100)
        return resp.get("Items", [])
    except ClientError as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/todos", status_code=201)
def create_todo(todo: Todo):
    todo.id = todo.id or str(uuid.uuid4())
    item = {"id": todo.id, "title": todo.title, "done": todo.done}
    try:
        table.put_item(Item=item)
        return item
    except ClientError as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/todos/{todo_id}")
def get_todo(todo_id: str):
    try:
        resp = table.get_item(Key={"id": todo_id})
        item = resp.get("Item")
        if not item:
            raise HTTPException(status_code=404, detail="Not found")
        return item
    except ClientError as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/todos/{todo_id}")
def update_todo(todo_id: str, todo: Todo):
    try:
        table.update_item(
            Key={"id": todo_id},
            UpdateExpression="SET title = :t, done = :d",
            ExpressionAttributeValues={":t": todo.title, ":d": todo.done},
        )
        return {"id": todo_id, "title": todo.title, "done": todo.done}
    except ClientError as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/todos/{todo_id}", status_code=204)
def delete_todo(todo_id: str):
    try:
        table.delete_item(Key={"id": todo_id})
        return
    except ClientError as e:
        raise HTTPException(status_code=500, detail=str(e))
