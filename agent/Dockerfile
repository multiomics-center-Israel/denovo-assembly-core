FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        sqlite3 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chmod +x entrypoint.sh

# Container-internal paths (portable; override via env if desired)
ENV GFF_DB_PATH=/data/gff.sqlite \
    FUNC_DB_PATH=/data/functional.sqlite \
    RAG_INDEX_DIR=/data/rag \
    ASSEMBLY_FASTA=/data/genome/final_assembly.fa.gz \
    BLAST_RESULTS_DIR=/data/blast_results

EXPOSE 8000
CMD ["./entrypoint.sh"]
