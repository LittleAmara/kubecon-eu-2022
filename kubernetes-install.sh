# Script to install a single node K8s cluster
#
# To use:  $ curl https://raw.githubusercontent.com/RX-M/classfiles/master/k8s.sh | sh
#
# N.B. The script turns off swap for the K8s control plane install but does
#      not disable swap permenantly. Please comment out any swap volumes in
#      the /etc/fstab before rebooting the VM.
#
#      This script will fail to run if the apt db is locked (wait 10 mins
#      and retry or reboot and retry).
#
#      Kubernetes single node clusters require a 4GB ram VM to run properly.

set -e

# Install Docker
wget -qO- https://get.docker.com/ | sh
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
sudo systemctl restart docker

# Configure Docker's bundled containerd to enable cni & use systemd for cgroups
sudo cp /etc/containerd/config.toml /etc/containerd/config.bak
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i -e 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# Initialize a control plane node
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
sudo apt-get update
sudo apt-get install -y kubeadm kubelet kubectl
sudo swapoff -a
if [ -z ${K8S_VERSION+x} ]; then K8S_VERSION="--kubernetes-version=stable-1" ; else K8S_VERSION="--kubernetes-version=$K8S_VERSION"; fi
sudo kubeadm init --cri-socket=unix:///var/run/containerd/containerd.sock  $K8S_VERSION
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl patch node $(hostname) -p '{"spec":{"taints":[]}}'

# Install the latest crictl (cni-tools package is not always the latest)
CRICTL_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases/latest|grep tag_name | cut -d '"' -f 4 | cut -b 2-)
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v$CRICTL_VERSION/crictl-v$CRICTL_VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-v$CRICTL_VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-v$CRICTL_VERSION-linux-amd64.tar.gz
echo "runtime-endpoint: unix:///run/containerd/containerd.sock" | sudo tee /etc/crictl.yaml
