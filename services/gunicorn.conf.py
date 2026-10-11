import os

bind = "0.0.0.0:5000"
# Un seul worker : le scheduler APScheduler tourne dans le process ; les threads absorbent les exports.
workers = 1
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
timeout = 300
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info")
