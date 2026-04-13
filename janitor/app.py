import json
import os
from flask import Flask, jsonify, request

app = Flask(__name__)

with open(os.path.join(os.path.dirname(__file__), "machines.json")) as f:
    MACHINES = json.load(f)

API_TOKEN = os.environ.get("JANITOR_API_TOKEN", "")


def check_auth():
    auth = request.headers.get("Authorization", "")
    if not API_TOKEN or auth != f"Bearer {API_TOKEN}":
        return False
    return True


@app.route("/machines/<machine_id>")
def get_machine(machine_id):
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    machine = MACHINES.get(machine_id)
    if not machine:
        return jsonify({"error": "Machine not found"}), 404
    return jsonify({"id": machine_id, **machine})


@app.route("/machines")
def get_machines():
    if not check_auth():
        return jsonify({"error": "Unauthorized"}), 401
    ids = request.args.get("ids", "")
    machine_ids = [i.strip() for i in ids.split(",") if i.strip()]
    results = []
    for machine_id in machine_ids:
        machine = MACHINES.get(machine_id)
        if machine:
            results.append({"id": machine_id, **machine})
        else:
            results.append({"id": machine_id, "error": "Not found"})
    return jsonify(results)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
