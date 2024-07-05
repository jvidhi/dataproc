#!/bin/bash

# ........................................................................
# Purpose: Build custom container image for serverless spark
# Parameters: (1) Docker image tag (2) gs URI of BQ connector jar (3) GCP region
# e.g. ./vertexi-build-container-image.sh 3.0.0 gs://spark-lib/bigquery/spark-bigquery-with-dependencies_2.12-0.22.2.jar us-central1
# ........................................................................

# Variables
PROJECT_ID=`gcloud config list --format 'value(core.project)'`
LOCAL_SCRATCH_DIR=~/build
DOCKER_IMAGE_TAG=$1
DOCKER_IMAGE_NM="dataprocai"
#DOCKER_IMAGE_FQN="gcr.io/$PROJECT_ID/$DOCKER_IMAGE_NM:$DOCKER_IMAGE_TAG"
DOCKER_IMAGE_FQN="docker.pkg.dev/$PROJECT_ID/dataprocai/$DOCKER_IMAGE_NM:$DOCKER_IMAGE_TAG"

BQ_CONNECTOR_JAR_URI=$2
GCP_REGION=$3

# Create local directory
cd ~
mkdir build
cd build
rm -rf *
echo "Created local directory for the Docker image building"

# Create Dockerfile in local directory
cd $LOCAL_SCRATCH_DIR

cat << 'EOF' > Dockerfile
# Debian 11 is recommended.
FROM debian:11-slim
#FROM gcr.io/google-containers/dataproc/runtime:2.1-debian11
 
# Suppress interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# (Required) Install utilities required by Spark scripts.
RUN apt update && apt install -y procps tini libjemalloc2

# (Optiona) Install utilities required by XGBoost for Spark.
RUN apt install -y procps libgomp1

# Enable jemalloc2 as default memory allocator
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

# (Optional) Add extra jars.
ENV SPARK_EXTRA_JARS_DIR=/opt/spark/jars/
ENV SPARK_EXTRA_CLASSPATH='/opt/spark/jars/*'
RUN mkdir -p "${SPARK_EXTRA_JARS_DIR}"
COPY spark-bigquery-with-dependencies_2.12-0.22.2.jar "${SPARK_EXTRA_JARS_DIR}"

# (Optional) Install and configure Miniconda3.
ENV CONDA_HOME=/opt/miniconda3
ENV PYSPARK_PYTHON=${CONDA_HOME}/bin/python
ENV PATH=${CONDA_HOME}/bin:${PATH}
COPY Miniconda3-py39_4.10.3-Linux-x86_64.sh .
RUN bash Miniconda3-py39_4.10.3-Linux-x86_64.sh -b -p /opt/miniconda3 \
  && ${CONDA_HOME}/bin/conda config --system --set always_yes True \
  && ${CONDA_HOME}/bin/conda config --system --set auto_update_conda False \
  && ${CONDA_HOME}/bin/conda config --system --prepend channels conda-forge \
  && ${CONDA_HOME}/bin/conda config --system --set channel_priority flexible 
  
# Packages ipython and ipykernel are required if using custom conda and want to use this container for running notebooks.
RUN ${CONDA_HOME}/bin/conda install ipython ipykernel

# Install Mamba and packages, ignoring the "Could not parse mod/etag header" warning
RUN ${CONDA_HOME}/bin/conda update -n base -c defaults conda
RUN ${CONDA_HOME}/bin/conda install -n base -c conda-forge mamba
RUN ${CONDA_HOME}/bin/mamba update -c conda-forge mamba -y 

COPY environment.yml .
#only to install in a virtual environment
#RUN ${CONDA_HOME}/bin/mamba env remove -n newbase  
#RUN ${CONDA_HOME}/bin/mamba env create -f environment.yml
#RUN ${CONDA_HOME}/bin/mamba clean --all --yes
# Activate Environment:  Make the new environment the active one.
#SHELL ["conda", "run", "-n", "newbase", "/bin/bash", "-c"]  # Replace 'myenv' with your actual environment name

#to install on the container

RUN ${CONDA_HOME}/bin/mamba install \
  python=3.9.19 \
  conda==24.5.0 \
  grpc-google-iam-v1=0.13.1 \
  fastavro=1.9.4 \
  fastparquet=2024.5.0 \
  gcsfs=2024.6.1 \
  google-cloud-bigquery-storage=2.25.0 \
  google-cloud-bigtable=2.24.0 \
  google-cloud-dataproc=5.10.0 \
  google-cloud-datastore=2.19.0 \
  google-cloud-monitoring=2.22.0 \
  google-cloud-pubsub=2.21.5 \
  google-cloud-vision=3.7.2 \
  numba=0.60.0 \
  regex=2024.5.15 \
  scikit-image=0.24.0 \
  seaborn=0.13.2 \
  google-cloud-aiplatform=1.57.0 \
  kfp=2.8.0 \
  sqlalchemy=2.0.31 \
  koalas=1.8.2 \
  mleap=0.23.1 \
  rtree=1.2.0

COPY requirements.txt .
#RUN pip install -r requirements.txt
#RUN pip install -r tensorflow-data-validation 

# (Required) Create the 'spark' group/user.
# The GID and UID must be 1099. Home directory is required.
RUN groupadd -g 1099 spark
RUN useradd -u 1099 -g 1099 -d /home/spark -m spark
USER spark

EOF

echo "Completed Dockerfile creation"

# Download dependencies to be baked into image
cd $LOCAL_SCRATCH_DIR
gsutil cp $BQ_CONNECTOR_JAR_URI .
gsutil cp /home/jupyter/dataproc_serverless/s8s-spark-mlops-lab/02-scripts/bash/requirements.txt .
gsutil cp /home/jupyter/dataproc_serverless/s8s-spark-mlops-lab/02-scripts/bash/environment.yml .

wget -P . https://repo.anaconda.com/miniconda/Miniconda3-py39_4.10.3-Linux-x86_64.sh
echo "Completed downloading dependencies"

# Authenticate 
gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev -q

# Build image
#--no-cache 
docker build . --progress=plain -f Dockerfile -t ${GCP_REGION}-$DOCKER_IMAGE_FQN
echo "Completed docker image build"

# Push to GCR
docker push ${GCP_REGION}-$DOCKER_IMAGE_FQN
echo "Completed docker image push to Artifact registry"

