FROM cgr.dev/chainguard/python:latest-dev AS python-builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt \
    && chmod 777 /home/nonroot/.local/lib/python3.12/site-packages/flask

FROM cgr.dev/chainguard/python:latest
WORKDIR /opt/app
ENV REDIS_HOST=localhost
COPY app.py .
COPY static/ static/
COPY templates/ templates/
COPY --from=python-builder /home/nonroot/.local/lib/python3.12/site-packages /home/nonroot/.local/lib/python3.12/site-packages
COPY --from=python-builder /home/nonroot/.local/bin  /home/nonroot/.local/bin
ENV PATH=$PATH:/home/nonroot/.local/bin
EXPOSE 5000
ENTRYPOINT ["flask", "run", "--host=0.0.0.0"]
