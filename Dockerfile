ARG ISCE_BASE_IMAGE=isce/isce2:20260308
FROM ${ISCE_BASE_IMAGE}

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    less \
    procps \
    unzip \
    python3-pip \
    python3-requests \
    python3-shapely \
    gdal-bin \
    python3-gdal \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

RUN python3 -m pip install --no-cache-dir \
    -r /tmp/requirements.txt

RUN git clone --depth=1 https://github.com/isce-framework/isce2.git /opt/isce2-src

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# copy scripts into container
COPY scripts /scripts
# make them executable
RUN find /scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;


ENV PATH="/opt/isce2-src/contrib/timeseries/prepStackToStaMPS/bin:/usr/local/bin:${PATH}"

RUN ln -sf /usr/lib/python3.8/dist-packages/isce2/applications/looks.py /usr/local/bin/looks.py

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]