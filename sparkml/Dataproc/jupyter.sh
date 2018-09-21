#!/bin/bash
# License: Public Domain.

echo "export PYSPARK_PYTHON=python3" | tee -a  /etc/profile.d/spark_config.sh  /etc/*bashrc /usr/lib/spark/conf/spark-env.sh
echo "export PYTHONHASHSEED=0" | tee -a /etc/profile.d/spark_config.sh /etc/*bashrc /usr/lib/spark/conf/spark-env.sh
echo "spark.executorEnv.PYTHONHASHSEED=0" >> /etc/spark/conf/spark-defaults.conf

# Only run on the master node
ROLE=$(/usr/share/google/get_metadata_value attributes/dataproc-role)
if [[ "${ROLE}" == 'Master' ]]; then
        
        # Install dependencies needed for iPython Notebook
        apt-get install build-essential python3-dev libpng-dev libfreetype6-dev libxft-dev pkg-config python3-matplotlib python3-requests python3-numpy python3-scipy -y
        curl https://bootstrap.pypa.io/get-pip.py | python3        
        
        # Install iPython Notebook with friends and create a profile
        pip3 install ipython jupyter sklearn seaborn pandas py4j gcloud jgscm
        ipython profile create pyspark
        
        # Setup script for iPython Notebook so it uses the cluster's Spark
        cat > /root/.ipython/profile_pyspark/startup/00-pyspark-setup.py <<'_EOF'
import os
import sys

spark_home = "/usr/lib/spark/"
os.environ["SPARK_HOME"] = spark_home
os.environ["PYSPARK_PYTHON"] = "python3"
sys.path.insert(0, os.path.join(spark_home, "python"))
with open(os.path.join(spark_home, "python/pyspark/shell.py")) as src:
    exec(src.read())
_EOF

        # Actiave JGSCM for Jupyter
        mkdir /root/.jupyter
        # Fool Jupyter so that it thinks it is migrated (it rm -rf .jupyter otherwise and our changes will be lost)
        date -Iseconds > /root/.jupyter/migrated
        cat > /root/.jupyter/jupyter_notebook_config.py <<'_EOF'
c.NotebookApp.contents_manager_class = "jgscm.GoogleStorageContentManager"
c.NotebookApp.token = ""
_EOF

        # Add PySpark kernel for Jupyter
        mkdir -p /usr/local/share/jupyter/kernels/pyspark
        cat > /usr/local/share/jupyter/kernels/pyspark/kernel.json <<'_EOF'
{
 "display_name": "PySpark 3",
 "language": "python3",
 "env": {"PYTHONHASHSEED": "0"},
 "argv": [
  "/usr/bin/python3",
  "-m",
  "IPython.kernel",
  "--profile=pyspark",
  "-f",
  "{connection_file}"
 ]
}
_EOF

        # Install Jupyter as the systemd service
        cat > /lib/systemd/system/jupyter.service <<'_EOF'
[Unit]
Description=Jupyter Notebook
After=hadoop-yarn-resourcemanager.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/root
StandardOutput=/var/log/jupyter.log
StandardError=/var/log/jupyter.log
ExecStart=/usr/bin/python3 /usr/local/bin/jupyter notebook --no-browser --ip=* --port=8123
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
_EOF
        
        # Start Jupyter Notebook on port 8123
        systemctl daemon-reload
        systemctl enable jupyter
        service jupyter start
else
        # Worker setup
        # No matplotlib, ipython, jupyter
        apt-get install build-essential python3-dev libpng-dev libfreetype6-dev libxft-dev pkg-config python3-requests python3-numpy python3-scipy -y
        curl https://bootstrap.pypa.io/get-pip.py | python3
        pip3 install sklearn pandas py4j gcloud
fi