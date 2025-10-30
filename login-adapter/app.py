from flask import Flask, request, Response
import requests, os

API_BASE = os.environ.get("PLANE_API_BASE", "http://api:8000")
ALLOW_ORIGIN = os.environ.get("ALLOW_ORIGIN","http://148.113.10.170:8080")

app = Flask(__name__)

def _corsify(resp):
    # Không thực sự cần CORS khi cùng domain, nhưng giữ cho chắc
    resp.headers["Access-Control-Allow-Credentials"] = "true"
    resp.headers["Access-Control-Allow-Origin"] = ALLOW_ORIGIN
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type, X-CSRFToken"
    resp.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    return resp

@app.after_request
def after(resp):
    return _corsify(resp)

@app.route("/auth/spaces/sign-in/", methods=["POST","OPTIONS"])
def signin():
    if request.method == "OPTIONS":
        return _corsify(Response(status=204))

    # 1) Nhận JSON từ FE
    data = request.get_json(silent=True) or {}
    form = {
        "email": data.get("email",""),
        "password": data.get("password","")
    }

    # 2) Header sang API: dùng form-urlencoded + forward CSRF/Origin/Referer
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if "X-CSRFToken" in request.headers:
        headers["X-CSRFToken"] = request.headers["X-CSRFToken"]
    if "Origin" in request.headers:
        headers["Origin"] = request.headers["Origin"]
    if "Referer" in request.headers:
        headers["Referer"] = request.headers["Referer"]

    # 3) Forward cookie (csrftoken) sang API để Django so khớp CSRF
    r = requests.post(
        f"{API_BASE}/auth/spaces/sign-in/",
        data=form,
        headers=headers,
        cookies=request.cookies,
        allow_redirects=False,
    )

    # 4) Trả nguyên trạng các header quan trọng
    resp = Response(r.content, status=r.status_code)
    for k, v in r.headers.items():
        if k.lower() in ("set-cookie","location","content-type"):
            resp.headers[k] = v
    return resp

# Fallback
@app.route("/", defaults={"path": ""}, methods=["GET","POST","PUT","PATCH","DELETE","OPTIONS"])
@app.route("/<path:path>", methods=["GET","POST","PUT","PATCH","DELETE","OPTIONS"])
def passthrough(path):
    return Response('{"error":"Page not found."}', status=404, mimetype="application/json")
