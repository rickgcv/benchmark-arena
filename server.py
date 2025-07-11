from flask import Flask, send_from_directory, send_file
import os

app = Flask(__name__)

@app.route("/")
def index():
    return send_file("index.html")

@app.route("/<path:filename>")
def static_files(filename):
    return send_from_directory(".", filename)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False) 