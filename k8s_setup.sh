#!/bin/bash

set -e

KUBERNETES_VERSION="v1.32"
CRIO_VERSION="v1.32"
KUBERNETES_INSTALL_VERSION="1.32.5-1.1"

echo "[Step 1] Loading required kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo "[Step 2] Setting sysctl parameters..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo "[Step 3] Disabling swap..."
swapoff -a

echo "[Step 4] Installing dependencies..."
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common

echo "[Step 5] Installing CRI-O runtime..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | \
    tee /etc/apt/sources.list.d/cri-o.list

apt-get update -y
apt-get install -y cri-o

systemctl daemon-reload
systemctl enable crio --now

echo "[Step 6] Installing Kubernetes components..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | \
    tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet="$KUBERNETES_INSTALL_VERSION" kubeadm="$KUBERNETES_INSTALL_VERSION" kubectl="$KUBERNETES_INSTALL_VERSION"
apt-mark hold kubelet kubeadm kubectl

echo "✅ Basic Kubernetes setup completed."

# For master node only
if [[ "$1" == "master" ]]; then
    echo "[Master Step] Initializing master node..."
    kubeadm init

    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

    echo "[Master Step] Installing Calico CNI..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml
    curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/custom-resources.yaml
    nano custom-resources.yaml
    kubectl apply -f custom-resources.yaml

    echo "[Master Step] (Optional) You may now run 'kubectl get nodes' to verify the cluster status."
    echo "[Master Step] Save the output of 'kubeadm token create --print-join-command' to join workers."
fi

# For worker node
if [[ "$1" == "worker" ]]; then
    echo "🚀 Setup done. Paste your kubeadm join command below to join this node to the cluster."
    echo "Example:"
    echo "kubeadm join <MASTER_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
fi
