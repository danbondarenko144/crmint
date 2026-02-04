# Copyright 2018 Google Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM ubuntu:24.04 AS base

# Removes output stream buffering, allowing for more efficient logging
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries \
    && apt-get update \
    && apt-get install -y --no-install-recommends python3-pip python3-venv python-is-python3 default-mysql-client \
    # Cleaning
    && rm -rf /var/cache/apt/archives/*.deb \
    && rm -rf /var/lib/apt/lists/*

##
# Builder stage
#
FROM base as builder

RUN apt-get update \
    && apt-get install -y \
    git build-essential python3-dev python3-pip \
    # Cleaning
    && rm -rf /var/cache/apt/archives/*.deb \
    && rm -rf /var/lib/apt/lists/*

# TODO(dulacp): use pip-compile to compile a fresh version of dependencies
# Install pip-tools to compile requirements
RUN pip install pip-tools --break-system-packages

COPY ./common /app/common
COPY ./requirements-controller.in /app/requirements-controller.in

# Compile requirements to update them for Python 3.12
RUN pip-compile --generate-hashes --output-file /app/requirements-controller.txt /app/requirements-controller.in
RUN mkdir -p /install/dependencies
RUN mkdir -p /install/wheels
RUN pip install \
    --require-hashes \
    --break-system-packages \
    --disable-pip-version-check \
    --no-cache-dir \
    --target=/install/dependencies \
    -r /app/requirements-controller.txt \
    -f /install/wheels \
    && rm -rf /install/wheels

##
# Production stage
#
FROM base

# Copy installed dependencies
RUN mkdir -p /install/dependencies
COPY --from=builder /install/dependencies /install/dependencies
ENV PYTHONPATH="${PYTHONPATH}:/install/dependencies"
ENV PATH="${PATH}:/install/dependencies/bin"

COPY . /app

WORKDIR /app

ENV FLASK_APP controller_app.py
ENV FLASK_ENV production
ENV PORT 5000

RUN chmod +x ./controller_entrypoint.sh
ENTRYPOINT ["./controller_entrypoint.sh"]
