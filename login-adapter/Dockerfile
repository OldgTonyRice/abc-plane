FROM python:3.12-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENV PLANE_API_BASE=http://api:8000
ENV ALLOW_ORIGIN=http://148.113.10.170:18080
EXPOSE 8081
CMD ["gunicorn","-b","0.0.0.0:8081","app:app"]
